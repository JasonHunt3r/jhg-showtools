import SwiftUI
import PaneKit

/// What `ColumnsSplitView` measured and enforced by hand, now PaneKit's job
/// (`spec/panekit.md`, step 3). Edit Show's three columns (preview, list,
/// inspector) are `PaneNode.row` — preview is `main`, list is `near`,
/// inspector is `far` — **divider isolation over exactly matching
/// `ColumnsSplitView`'s old narrow-window squeeze order** (settled, Jason,
/// 2026-09-24): that order had the inspector give way before the list,
/// which can't be had without breaking the preview|list divider into also
/// moving the inspector. `.row`'s own trade instead: list now gives way
/// before the inspector in too narrow a window (the reverse of before, and
/// only reachable well below the app's own minimum window size), and list
/// loses its old upper bound (420) — it's `.row`'s uncapped "near" side.
///
/// **`nearIsRigid` (Jason, 2026-09-24, watching over a shoulder):** list
/// only changes size from its own (left) divider. Dragging the
/// list|inspector divider resizes preview and the inspector; list just
/// slides over, same width. Built into `.row` itself, not a ShowTools
/// one-off — `spec/panekit.md`, "Building a row".
enum EditColumnsLayout {
    static let mainMin: CGFloat = 420
    static let listMin: CGFloat = 180
    static let inspectorRange: ClosedRange<CGFloat> = 320...440
    static let inspectorDefault: CGFloat = 320
    /// List's own starting width and the most a preview|list drag can grow
    /// it to — `.row`'s `near` has no split of its own to remember these,
    /// so they only seed the list+inspector region's own size and range.
    static let listDefault: CGFloat = 230
    static let listMax: CGFloat = 420

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
        .row("columns", .horizontal, mainFirst: true,
             main: Pane("preview", minSize: mainMin),
             near: Pane("list", minSize: listMin), nearDefault: listDefault, nearMax: listMax,
             far: Pane("inspector", minSize: inspectorRange.lowerBound),
             farSize: inspectorDefault, farRange: inspectorRange, nearIsRigid: true)
    }

    /// Edit Slides' two columns: no list, so it's one split, not `.row`.
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
