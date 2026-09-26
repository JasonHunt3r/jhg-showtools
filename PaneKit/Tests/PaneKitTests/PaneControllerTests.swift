import XCTest
import CoreGraphics
@testable import PaneKit

/// `PaneController`'s own transactions — collapse/reopen under
/// `nearIsRigid`, which `PaneLayoutTests` can't cover since the linkage
/// lives in `setOpen`, not in the pure layout arithmetic.
@MainActor
final class PaneControllerTests: XCTestCase {
    static let rigidRow: PaneNode = .row("row", .horizontal, mainFirst: true,
                                         main: Pane("main", minSize: 400),
                                         near: Pane("near", minSize: 100), nearDefault: 150, nearMax: 300,
                                         far: Pane("far", minSize: 150), farSize: 200, farRange: 150...250,
                                         nearIsRigid: true)
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 500)

    func makeController() -> PaneController {
        PaneController(id: "test.\(UUID())", root: Self.rigidRow, store: UserDefaults(suiteName: #function + UUID().uuidString)!)
    }

    /// Item 1, `ShowTools Feedback — Worklist for Next CC Session.md`:
    /// closing `far` under `nearIsRigid` must hand its space to `main`, not
    /// `near` — the reverse of `.row`'s own default (`testRowClosingFarGrowsNear`
    /// in `PaneLayoutTests`), which is what a plain `.row` (without
    /// `nearIsRigid`) still does on purpose.
    func testClosingFarUnderNearIsRigidGrowsMainNotNear() {
        let c = makeController()
        c.setOpen("row.near", false)
        let r = PaneLayout.layout(Self.rigidRow, in: rect, state: c.state)
        XCTAssertNil(r.panes["far"])
        XCTAssertEqual(r.panes["near"]?.width, 150)                        // unchanged
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 12 - 1 - 150)        // grew by far's freed space
    }

    /// Reopening restores `far` and `near` to their original widths.
    func testReopeningFarUnderNearIsRigidRestoresBothWidths() {
        let c = makeController()
        c.setOpen("row.near", false)
        c.setOpen("row.near", true)
        let r = PaneLayout.layout(Self.rigidRow, in: rect, state: c.state)
        XCTAssertEqual(r.panes["near"]?.width, 150)
        XCTAssertEqual(r.panes["far"]?.width, 200)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 150 - 1 - 200)
    }

    /// Dragging `far` shut must leave `near` exactly as closing it by
    /// double-click does — measured wrong on Jason's own copy, 2026-09-25:
    /// Edit Show's Browser went 236 → 545 pt on a drag shut, because the
    /// drag set "closed" without taking far's width off the ancestor.
    func testDraggingFarShutUnderNearIsRigidLeavesNear() {
        let split = Self.rigidRow.split("row.near")!
        let start = PaneKitState()
        var s = start
        dragResize(split, root: Self.rigidRow, fromEdge: 180, total: 1000, start: start, into: &s)   // resize on the way
        dragResize(split, root: Self.rigidRow, fromEdge: 20, total: 1000, start: start, into: &s)    // then past half its floor
        XCTAssertTrue(s.isCollapsed("row.near"))
        let r = PaneLayout.layout(Self.rigidRow, in: rect, state: s)
        XCTAssertEqual(r.panes["near"]?.width, 150)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 12 - 1 - 150)
    }

    /// And the reverse: dragging `far` open from its handle doesn't shrink `near`.
    func testDraggingFarOpenFromHandleUnderNearIsRigidLeavesNear() {
        let c = makeController()
        c.setOpen("row.near", false)
        let split = Self.rigidRow.split("row.near")!
        var s = c.state
        dragResize(split, root: Self.rigidRow, fromEdge: 220, total: 1000, start: c.state, into: &s)
        let r = PaneLayout.layout(Self.rigidRow, in: rect, state: s)
        XCTAssertEqual(r.panes["near"]?.width, 150)
        XCTAssertEqual(r.panes["far"]?.width, 220)
        XCTAssertEqual(r.panes["main"]?.width, 1000 - 1 - 150 - 1 - 220)
    }

    // MARK: Switching sides

    static let drawer: PaneNode = .split("s", .horizontal, sized: .second, size: 200, range: 150...300,
                                         .pane("main", minSize: 100), .pane("drawer", minSize: 150))
    static let fixedDrawer: PaneNode = .split("s", .horizontal, sized: .second, size: 200, range: 150...300,
                                              canSwitchSides: false,
                                              .pane("main", minSize: 100), .pane("drawer", minSize: 150))

    func drag(_ node: PaneNode, from start: PaneKitState, to fromEdge: CGFloat) -> PaneKitState {
        var s = start
        dragResize(node.split("s")!, root: node, fromEdge: fromEdge, total: 1000, start: start, into: &s)
        return s
    }

    /// Dragged across main until less than its starting size is left, the
    /// drawer trades places: mounted on the opposite edge at that size.
    func testDraggingAcrossSwitchesSides() {
        let s = drag(Self.drawer, from: PaneKitState(), to: 850)          // 150 left < 200
        XCTAssertTrue(s.isOnOtherSide("s"))
        let r = PaneLayout.layout(Self.drawer, in: rect, state: s)
        XCTAssertEqual(r.panes["drawer"], CGRect(x: 0, y: 0, width: 200, height: 500))
        XCTAssertEqual(r.panes["main"]?.minX, 201)
    }

    /// Short of that, it's an ordinary resize, capped at the range.
    func testDraggingShortOfTheThresholdOnlyResizes() {
        let s = drag(Self.drawer, from: PaneKitState(), to: 750)          // 250 left ≥ 200
        XCTAssertFalse(s.isOnOtherSide("s"))
        XCTAssertEqual(s.splits["s"]?.size, 300)
    }

    /// From the other side, the same drag the other way switches it back —
    /// measured from the edge it's on now.
    func testDraggingBackSwitchesBack() {
        let flipped = drag(Self.drawer, from: PaneKitState(), to: 850)
        let s = drag(Self.drawer, from: flipped, to: 850)
        XCTAssertFalse(s.isOnOtherSide("s"))
        XCTAssertEqual(PaneLayout.layout(Self.drawer, in: rect, state: s).panes["drawer"]?.minX, 800)
    }

    /// A closed drawer's handle dragged across opens it on the other side,
    /// and the handle sits on the edge it closes against now.
    func testClosedDrawerDraggedAcrossOpensOnTheOtherSide() {
        var closed = PaneKitState()
        closed.splits["s"] = SplitState(collapsed: true)
        let s = drag(Self.drawer, from: closed, to: 900)
        XCTAssertTrue(s.isOnOtherSide("s"))
        XCTAssertFalse(s.isCollapsed("s"))
        var shut = s
        shut.splits["s"]?.collapsed = true
        XCTAssertEqual(PaneLayout.layout(Self.drawer, in: rect, state: shut).handles["s"]?.minX, 0)
        XCTAssertEqual(Self.drawer.split("s")!.edge(in: shut), .leading)
    }

    func testCanSwitchSidesFalseNeverSwitches() {
        let s = drag(Self.fixedDrawer, from: PaneKitState(), to: 900)
        XCTAssertFalse(s.isOnOtherSide("s"))
    }

    /// A state saved before `onOtherSide` existed still reads, on its own side.
    func testOldSavedStateReadsWithoutOnOtherSide() throws {
        let old = #"{"splits":{"s":{"collapsed":true,"size":250}},"panes":{}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PaneKitState.self, from: old)
        XCTAssertEqual(s.splits["s"]?.size, 250)
        XCTAssertTrue(s.isCollapsed("s"))
        XCTAssertFalse(s.isOnOtherSide("s"))
    }
}
