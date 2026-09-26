import SwiftUI
import PaneKit

/// What `ColumnsSplitView` measured and enforced by hand, now PaneKit's job
/// (`spec/panekit.md`, step 3). Edit Show's three columns: preview, the
/// Browser (pane id `list`) and the inspector.
///
/// **Two drawers, nested from the right (item 13, 2026-09-25).** The
/// outer split's sized side is the inspector; its main side is a second
/// split whose sized side is the Browser, with preview as main. So:
/// - both the Browser and the inspector close to their own edge handle,
///   and with both closed the two handles stack at the right edge;
/// - closing, opening or dragging either hands the change to preview, so
///   the Browser only ever changes width from its own (left) divider —
///   what `.row`'s `nearIsRigid` was built for (Jason, 2026-09-24), now
///   just what this nesting does, with no linked split;
/// - in too narrow a window the inspector gives way before the Browser
///   (only reachable below the app's own minimum window size).
///
/// Until 2026-09-25 this was `PaneNode.row` with `nearIsRigid`, whose
/// `near` (the Browser) was the inner split's main side and so couldn't
/// close. Its split ids were `columns`/`columns.near`; the new ids don't
/// reuse them, so an old saved state can't be misread as the new one.
enum EditColumnsLayout {
    static let mainMin: CGFloat = 420
    static let listMin: CGFloat = 180
    static let inspectorRange: ClosedRange<CGFloat> = 320...440
    static let inspectorDefault: CGFloat = 320
    /// The Browser's starting width and the most a drag can make it.
    static let listDefault: CGFloat = 230
    static let listMax: CGFloat = 420
    /// The two drawers' split ids: the inspector's, and the Browser's.
    static let inspectorSplit = "columns.inspector"
    static let browserSplit = "columns.browser"

    /// The inspector is the first detachable area (`spec/windows.md`, "A
    /// possible order", step 4): it pops out as a panel, to prove the
    /// pattern PaneKit already built — undo sharing (the popped-out
    /// window's own `undoManager` falls back to the main window, since
    /// `PaneWindowController` is handed `container.window` as `parent`),
    /// the main window closing up (`PaneLayout.isEmpty`, already generic),
    /// and the state surviving a relaunch (`PaneKitState.panes`, already
    /// codable). Edit Slides' own inspector stays inline for now — this is
    /// the first case, not a port of both at once.
    static var threeColumns: PaneNode {
        .split(inspectorSplit, .horizontal, sized: .second, size: inspectorDefault, range: inspectorRange,
               title: "Inspector",
               .split(browserSplit, .horizontal, sized: .second, size: listDefault, range: listMin...listMax,
                      title: "Browser",
                      .pane("preview", minSize: mainMin),
                      .pane("list", title: "Browser", minSize: listMin)),
               .leaf(Pane("inspector", title: "Inspector", minSize: inspectorRange.lowerBound, popOut: .panel)))
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
