import XCTest
import CoreGraphics
@testable import PaneKit

/// PaneKit's layout arithmetic: pure, so it's pinned here, not by eye.
/// Coordinates are flipped (y grows downward).
final class PaneLayoutTests: XCTestCase {
    /// Finder's shape: a sidebar that keeps its width, and the rest.
    let finder: PaneNode = .split("window", .horizontal, sized: .first, size: 200, range: 150...300,
                                  .pane("sidebar", title: "Sidebar", popOut: .panel),
                                  .pane("files", title: "Files"))

    let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testDefaults() {
        let r = PaneLayout.layout(finder, in: rect, state: PaneKitState())
        XCTAssertEqual(r.panes["sidebar"], CGRect(x: 0, y: 0, width: 200, height: 600))
        XCTAssertEqual(r.dividers["window"], CGRect(x: 200, y: 0, width: 1, height: 600))
        XCTAssertEqual(r.panes["files"], CGRect(x: 201, y: 0, width: 799, height: 600))
        XCTAssertTrue(r.handles.isEmpty)
    }

    /// A window resize goes to the main side; the sized side keeps its width.
    func testWindowResizeGoesToMain() {
        let wide = CGRect(x: 0, y: 0, width: 1400, height: 600)
        let r = PaneLayout.layout(finder, in: wide, state: PaneKitState())
        XCTAssertEqual(r.panes["sidebar"]?.width, 200)
        XCTAssertEqual(r.panes["files"]?.width, 1199)
    }

    func testStoredSizeIsKeptInsideItsRange() {
        var s = PaneKitState()
        s.splits["window"] = SplitState(size: 1000)
        XCTAssertEqual(PaneLayout.layout(finder, in: rect, state: s).panes["sidebar"]?.width, 300)
        s.splits["window"] = SplitState(size: 10)
        XCTAssertEqual(PaneLayout.layout(finder, in: rect, state: s).panes["sidebar"]?.width, 150)
    }

    /// A narrow window squeezes the sized side to keep the main side at its
    /// minimum, without touching the stored size: widen it, and the size
    /// comes back.
    func testSqueezeDoesNotChangeTheStoredSize() {
        var s = PaneKitState()
        s.splits["window"] = SplitState(size: 250)
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
        // files' minimum is 80: 300 - 1 - 80 = 219.
        XCTAssertEqual(PaneLayout.layout(finder, in: narrow, state: s).panes["sidebar"]?.width, 219)
        XCTAssertEqual(s.splits["window"]?.size, 250)
        XCTAssertEqual(PaneLayout.layout(finder, in: rect, state: s).panes["sidebar"]?.width, 250)
    }

    /// Closed against its edge, a pane leaves a handle there, and the main
    /// side takes the rest.
    func testCollapsedLeavesAHandleOnItsEdge() {
        var s = PaneKitState()
        s.splits["window"] = SplitState(size: 250, collapsed: true)
        let r = PaneLayout.layout(finder, in: rect, state: s)
        XCTAssertNil(r.panes["sidebar"])
        XCTAssertNil(r.dividers["window"])
        XCTAssertEqual(r.handles["window"], CGRect(x: 0, y: 0, width: PaneLayout.handleThickness, height: 600))
        XCTAssertEqual(r.panes["files"], CGRect(x: 12, y: 0, width: 988, height: 600))
    }

    func testTrailingAndBottomHandles() {
        let mail: PaneNode = .split("window", .horizontal, sized: .second, size: 300, range: 200...500,
                                    .pane("list"), .pane("inspector"))
        var s = PaneKitState()
        s.splits["window"] = SplitState(collapsed: true)
        let r = PaneLayout.layout(mail, in: rect, state: s)
        XCTAssertEqual(r.handles["window"], CGRect(x: 988, y: 0, width: 12, height: 600))
        XCTAssertEqual(r.panes["list"], CGRect(x: 0, y: 0, width: 988, height: 600))

        let stacked: PaneNode = .split("window", .vertical, sized: .second, size: 200, range: 100...400,
                                       .pane("top"), .pane("bottom"))
        let open = PaneLayout.layout(stacked, in: rect, state: PaneKitState())
        XCTAssertEqual(open.panes["bottom"], CGRect(x: 0, y: 400, width: 1000, height: 200))
        XCTAssertEqual(open.dividers["window"], CGRect(x: 0, y: 399, width: 1000, height: 1))
        XCTAssertEqual(open.panes["top"], CGRect(x: 0, y: 0, width: 1000, height: 399))
        let closed = PaneLayout.layout(stacked, in: rect, state: PaneKitState(splits: ["window": SplitState(collapsed: true)]))
        XCTAssertEqual(closed.handles["window"], CGRect(x: 0, y: 588, width: 1000, height: 12))
    }

    /// A popped-out pane's slot closes up: no divider, no handle, and its
    /// neighbour takes the space.
    func testPoppedOutPaneClosesItsSlot() {
        var s = PaneKitState()
        s.panes["sidebar"] = PaneWindowState(poppedOut: true)
        let r = PaneLayout.layout(finder, in: rect, state: s)
        XCTAssertNil(r.panes["sidebar"])
        XCTAssertTrue(r.dividers.isEmpty)
        XCTAssertTrue(r.handles.isEmpty)
        XCTAssertEqual(r.panes["files"], rect)
    }

    /// ShowTools' shape, the demanding example: a timeline pane edge to edge
    /// under a Library pane, and three columns beside it — built from
    /// `.row(…)`, the same recipe Edit Show's preview/list/inspector uses.
    static let showTools: PaneNode =
        .split("window", .vertical, sized: .second, size: 240, range: 120...600, title: "Timeline",
               .split("top", .horizontal, sized: .first, size: 219, range: 180...360, title: "Library",
                      .pane("library", title: "Library", popOut: .panel),
                      .row("columns", .horizontal, mainFirst: true,
                           main: Pane("viewer", title: "Viewer", minSize: 300),
                           near: Pane("browser", title: "Browser", popOut: .panel), nearDefault: 245, nearMax: 419,
                           far: Pane("inspector", title: "Inspector", popOut: .panel),
                           farSize: 320, farRange: 260...480)),
               .pane("timeline", title: "Timeline", popOut: .window))

    func testShowToolsShape() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 835)
        let r = PaneLayout.layout(Self.showTools, in: window, state: PaneKitState())
        // The timeline runs the whole width, under everything.
        XCTAssertEqual(r.panes["timeline"], CGRect(x: 0, y: 595, width: 1376, height: 240))
        XCTAssertEqual(r.panes["library"], CGRect(x: 0, y: 0, width: 219, height: 594))
        XCTAssertEqual(r.panes["viewer"], CGRect(x: 220, y: 0, width: 589, height: 594))
        XCTAssertEqual(r.panes["browser"], CGRect(x: 810, y: 0, width: 245, height: 594))
        XCTAssertEqual(r.panes["inspector"], CGRect(x: 1056, y: 0, width: 320, height: 594))
        XCTAssertEqual(r.dividers.count, 4)
    }

    /// Closing the inspector gives its width to its neighbour (the browser
    /// slides over), and the viewer keeps its size: the columns' split keeps
    /// its 566.
    func testClosingTheInspectorKeepsTheOtherSizes() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 835)
        let r = PaneLayout.layout(Self.showTools, in: window,
                                  state: PaneKitState(splits: ["columns.near": SplitState(collapsed: true)]))
        XCTAssertNil(r.panes["inspector"])
        XCTAssertEqual(r.panes["viewer"]?.width, 589)
        XCTAssertEqual(r.panes["browser"], CGRect(x: 810, y: 0, width: 554, height: 594))
        XCTAssertEqual(r.handles["columns.near"], CGRect(x: 1364, y: 0, width: 12, height: 594))
    }

    /// Popping out the browser and the inspector empties the columns'
    /// sized side, so the viewer takes that space too.
    func testPoppingOutBothRightPanesGivesTheViewerTheSpace() {
        let window = CGRect(x: 0, y: 0, width: 1376, height: 835)
        var s = PaneKitState()
        s.panes["browser"] = PaneWindowState(poppedOut: true)
        s.panes["inspector"] = PaneWindowState(poppedOut: true)
        let r = PaneLayout.layout(Self.showTools, in: window, state: s)
        XCTAssertEqual(r.panes["viewer"], CGRect(x: 220, y: 0, width: 1156, height: 594))
        XCTAssertNil(r.dividers["columns"])
        XCTAssertNil(r.dividers["right"])
    }

    func testMinimumExtentOfANestedTree() {
        // Across: library's range minimum (180) + 1 + the columns' own floor
        // (browser's 80 + 1 + inspector's 260, `.row`'s own arithmetic) + 1 + viewer's 300.
        XCTAssertEqual(PaneLayout.minExtent(Self.showTools, along: .horizontal, state: PaneKitState()),
                       180 + 1 + (80 + 1 + 260) + 1 + 300)
        // Down: the timeline's minimum (120) + 1 + the top's tallest minimum.
        XCTAssertEqual(PaneLayout.minExtent(Self.showTools, along: .vertical, state: PaneKitState()),
                       120 + 1 + 300)
    }

    /// Saved state decodes field by field: one bad field loses only itself.
    func testStateDecodesLeniently() throws {
        let json = """
        {"splits": {"window": {"size": "wide", "collapsed": true}},
         "panes": {"sidebar": {"poppedOut": true, "windowFrame": "nowhere"}},
         "somethingNew": 1}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(PaneKitState.self, from: json)
        XCTAssertEqual(s.splits["window"], SplitState(size: nil, collapsed: true))
        XCTAssertEqual(s.panes["sidebar"], PaneWindowState(poppedOut: true, windowFrame: nil))
    }

    func testStateRoundTrips() throws {
        let s = PaneKitState(splits: ["window": SplitState(size: 240, collapsed: false)],
                             panes: ["sidebar": PaneWindowState(poppedOut: true,
                                                                windowFrame: CGRect(x: 10, y: 20, width: 300, height: 400))])
        let back = try JSONDecoder().decode(PaneKitState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testEdges() {
        XCTAssertEqual(Self.showTools.split("window")?.edge, .bottom)
        XCTAssertEqual(Self.showTools.split("top")?.edge, .leading)
        XCTAssertEqual(Self.showTools.split("columns.near")?.edge, .trailing)
        XCTAssertEqual(Self.showTools.split("columns.near")?.sizedTitle, "Inspector")
    }

    // MARK: `.row` — three independently-sized siblings from two nested splits

    /// A synthetic row: `main` first, `near` next to it, `far` at the edge.
    static let row: PaneNode = .row("row", .horizontal, mainFirst: true,
                                    main: Pane("main", minSize: 400),
                                    near: Pane("near", minSize: 100), nearDefault: 150, nearMax: 300,
                                    far: Pane("far", minSize: 150), farSize: 200, farRange: 150...250)

    func testRowDefaults() {
        let r = PaneLayout.layout(Self.row, in: CGRect(x: 0, y: 0, width: 1000, height: 500), state: PaneKitState())
        XCTAssertEqual(r.panes["far"]?.width, 200)
        XCTAssertEqual(r.panes["near"]?.width, 150)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 200 - 1 - 150)
    }

    /// The two invariants `.row` promises for all three panes, not just two:
    /// a divider only moves its own two neighbors, and a resize goes to
    /// `main`.
    func testRowDividerIsolationAndMainAbsorbsResize() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 500)
        // Dragging main|near (the outer split) changes main and near, never far.
        var s = PaneKitState()
        s.splits["row"] = SplitState(size: 260 + 1 + 200)   // near widened to 260
        var r = PaneLayout.layout(Self.row, in: rect, state: s)
        XCTAssertEqual(r.panes["far"]?.width, 200)
        XCTAssertEqual(r.panes["near"]?.width, 260)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 260 - 1 - 200)
        // Dragging near|far (the inner split) changes near and far, never main.
        s = PaneKitState()
        s.splits["row.near"] = SplitState(size: 230)   // far widened to 230
        r = PaneLayout.layout(Self.row, in: rect, state: s)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 150 - 1 - 200)   // the default combo, unmoved
        XCTAssertEqual(r.panes["far"]?.width, 230)
        XCTAssertEqual(r.panes["near"]?.width, 150 + 1 + 200 - 1 - 230)
        // A window resize goes to main; near and far keep their widths.
        let wider = CGRect(x: 0, y: 0, width: 1400, height: 500)
        r = PaneLayout.layout(Self.row, in: wider, state: PaneKitState())
        XCTAssertEqual(r.panes["far"]?.width, 200)
        XCTAssertEqual(r.panes["near"]?.width, 150)
        XCTAssertEqual(r.panes["main"]?.width, 1400 - 1 - 200 - 1 - 150)
    }

    /// A narrow row squeezes `near` before `far`: `main` first, down to its
    /// floor; then `near`, down to its; `far` doesn't move until both do.
    func testRowNearGivesWayBeforeFar() {
        // main's floor (400) + 1 + near.minSize (100) + 1 + far's default (200) = 702.
        let justFitting = CGRect(x: 0, y: 0, width: 702, height: 500)
        var r = PaneLayout.layout(Self.row, in: justFitting, state: PaneKitState())
        XCTAssertEqual(r.panes["main"]?.width, 400)
        XCTAssertEqual(r.panes["near"]?.width, 100)
        XCTAssertEqual(r.panes["far"]?.width, 200)
        // Narrower still: near is already at its floor, so far gives way.
        let narrower = CGRect(x: 0, y: 0, width: 680, height: 500)
        r = PaneLayout.layout(Self.row, in: narrower, state: PaneKitState())
        XCTAssertEqual(r.panes["main"]?.width, 400)
        XCTAssertEqual(r.panes["near"]?.width, 100)
        XCTAssertEqual(r.panes["far"]?.width, 178)
    }

    /// Closing `far` hands its space to `near` (its neighbor), not `main`.
    func testRowClosingFarGrowsNear() {
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let r = PaneLayout.layout(Self.row, in: rect,
                                  state: PaneKitState(splits: ["row.near": SplitState(collapsed: true)]))
        XCTAssertNil(r.panes["far"])
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 200 - 1 - 150)
        XCTAssertEqual(r.panes["near"]?.width, 200 + 1 + 150 - 12)
    }
}
