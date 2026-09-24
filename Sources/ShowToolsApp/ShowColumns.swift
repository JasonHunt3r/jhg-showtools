import SwiftUI
import PaneKit

/// What `ColumnsSplitView` measured and enforced by hand, now PaneKit's job
/// (`spec/panekit.md`, step 3). Edit Show's three columns (preview, list,
/// inspector) are two nested PaneKit splits, not one three-way primitive:
/// the outer's main is the preview, so a window resize goes there; the
/// inner's main is the list, so dragging the preview|list divider changes
/// only those two, not the inspector. **Divider isolation over exactly
/// matching `ColumnsSplitView`'s old narrow-window squeeze order**
/// (settled, Jason, 2026-09-24): that order had the inspector give way
/// before the list, which this can't reproduce without breaking the
/// preview|list divider into also moving the inspector. In a window too
/// narrow for all three at their floors, list now gives way before the
/// inspector instead — the reverse of before, and only reachable well
/// below the app's own minimum window size. The list column also loses
/// its old upper bound (420): it's the "main" side of its own split now,
/// which PaneKit doesn't cap, only floors.
enum EditColumnsLayout {
    static let mainMin: CGFloat = 420
    static let listMin: CGFloat = 180
    static let inspectorRange: ClosedRange<CGFloat> = 320...440
    static let inspectorDefault: CGFloat = 320
    /// The list+inspector region's own range and default, chosen so a
    /// fresh install shows about what `ColumnsSplitView` did (list ~230,
    /// inspector ~320).
    static let sideRange: ClosedRange<CGFloat> = 501...861
    static let sideDefault: CGFloat = 551

    /// Edit Show's three columns, plus the storyline below them
    /// (`EditShowView`'s own tree: the outer split is vertical, in place
    /// of the old `VSplitView`).
    static func editShowTree(storylineMin: CGFloat, storylineDefault: CGFloat) -> PaneNode {
        .split("editShow", .vertical, sized: .second, size: storylineDefault,
               range: storylineMin...(storylineDefault + 400), collapsible: false,
               threeColumns,
               .pane("storyline", minSize: storylineMin))
    }

    static var threeColumns: PaneNode {
        .split("columns", .horizontal, sized: .second, size: sideDefault, range: sideRange, collapsible: false,
               .pane("preview", minSize: mainMin),
               .split("listInspector", .horizontal, sized: .second, size: inspectorDefault, range: inspectorRange,
                      .pane("list", minSize: listMin),
                      .pane("inspector", minSize: inspectorRange.lowerBound)))
    }

    /// Edit Slides' two columns: no list, so it's one split, not nested.
    static var twoColumns: PaneNode {
        .split("columns", .horizontal, sized: .second, size: inspectorDefault, range: inspectorRange,
               .pane("main", minSize: mainMin),
               .pane("inspector", minSize: inspectorRange.lowerBound))
    }
}

/// Edit Slides' two columns — the slide list and its inspector — on
/// PaneKit. Bridges the inspector's open/closed state both ways with
/// `inspectorShown`, which the toolbar button and the View menu's own
/// toggle also read and set.
struct TwoColumns<Main: View, Inspector: View>: View {
    @Binding var inspectorShown: Bool
    let model: AppModel
    let panes: PaneController
    let main: Main
    let inspector: Inspector

    var body: some View {
        PaneLayoutView(controller: panes, content: [
            "main": AnyView(main.environment(model)),
            "inspector": AnyView(inspector.environment(model)),
        ])
        .onAppear { panes.setOpen("columns", inspectorShown) }
        .onChange(of: inspectorShown) { _, shown in panes.setOpen("columns", shown) }
        .onChange(of: panes.isOpen("columns")) { _, shown in
            if shown != inspectorShown { inspectorShown = shown }
        }
    }
}
