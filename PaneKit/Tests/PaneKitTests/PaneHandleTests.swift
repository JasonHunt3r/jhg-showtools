import XCTest
import AppKit
@testable import PaneKit

/// `PaneHandleStyle.external`: the app's own view is the handle (Jason,
/// 2026-09-26 — a grid's header bar under ShowTools' viewer drawer).
@MainActor
final class PaneHandleTests: XCTestCase {
    /// A drawer on top (the viewer), main below (the grid, its bar at the top).
    static let drawer: PaneNode = .split("viewer", .vertical, sized: .first, size: 200, range: 80...500,
                                         handle: .external,
                                         .pane("viewer", minSize: 80), .pane("grid", minSize: 150))
    let rect = CGRect(x: 0, y: 0, width: 800, height: 600)

    func closed() -> PaneKitState { PaneKitState(splits: ["viewer": SplitState(collapsed: true)]) }

    func testClosedTakesNoRoomAndLeavesNoHandle() {
        let r = PaneLayout.layout(Self.drawer, in: rect, state: closed())
        XCTAssertNil(r.handles["viewer"])
        XCTAssertNil(r.dividers["viewer"])
        XCTAssertEqual(r.panes["grid"], rect)                 // the bar sits at the very top
        XCTAssertEqual(r.panes["viewer"]?.height ?? 0, 0)
    }

    func testOpenIsAnOrdinarySplit() {
        let r = PaneLayout.layout(Self.drawer, in: rect, state: PaneKitState())
        XCTAssertEqual(r.panes["viewer"], CGRect(x: 0, y: 0, width: 800, height: 200))
        XCTAssertEqual(r.dividers["viewer"], CGRect(x: 0, y: 200, width: 800, height: 1))
        XCTAssertEqual(r.panes["grid"], CGRect(x: 0, y: 201, width: 800, height: 399))
    }

    func testClosedMinimumIsJustMain() {
        XCTAssertEqual(PaneLayout.minExtent(Self.drawer, along: .vertical, state: closed()), 150)
        XCTAssertEqual(PaneLayout.closedThickness(Self.drawer.split("viewer")!), 0)
    }

    /// The app's view stays where the app put it, so no switching sides,
    /// even if asked for.
    func testCannotSwitchSides() {
        let split = Self.drawer.split("viewer")!
        XCTAssertFalse(split.canSwitchSides)
        var s = PaneKitState()
        dragResize(split, root: Self.drawer, fromEdge: 590, total: 600, start: PaneKitState(), into: &s)
        XCTAssertFalse(s.isOnOtherSide("viewer"))
        XCTAssertEqual(s.splits["viewer"]?.size, 500)         // just clamped to the range
    }

    /// Grabbed anywhere on the bar, the drawer follows by how far the
    /// pointer moves — it doesn't jump to the pointer.
    func testDragKeepsTheGrabOffset() {
        // Closed, the bar grabbed 14 pt below the top, dragged down 220.
        XCTAssertEqual(handleDragExtent(startExtent: 0, grabbedAt: 14, pointerAt: 234), 220)
        // Open at 200: the bar starts at 201; grabbed at 215, dragged up 50.
        XCTAssertEqual(handleDragExtent(startExtent: 200, grabbedAt: 215, pointerAt: 165), 150)
    }

    func testDragOpensFromClosedAndClosesPastHalfTheMinimum() {
        let split = Self.drawer.split("viewer")!
        var s = closed()
        dragResize(split, root: Self.drawer, fromEdge: 220, total: 600, start: closed(), into: &s)
        XCTAssertFalse(s.isCollapsed("viewer"))
        XCTAssertEqual(s.splits["viewer"]?.size, 220)
        var t = PaneKitState()
        dragResize(split, root: Self.drawer, fromEdge: 30, total: 600, start: PaneKitState(), into: &t)
        XCTAssertTrue(t.isCollapsed("viewer"))
    }

    /// No edge handle view is made for it: the app's view is the handle.
    func testContainerMakesNoEdgeHandle() {
        let c = PaneController(id: "test.\(UUID())", root: Self.drawer,
                               store: UserDefaults(suiteName: #function + UUID().uuidString)!)
        let view = PaneContainerView(controller: c, content: [:])
        XCTAssertFalse(view.subviews.contains { String(describing: type(of: $0)) == "PaneEdgeHandleView" })
    }

    /// A double-click's toggle: open and closed both ways, one transaction each.
    func testToggle() {
        let c = PaneController(id: "test.\(UUID())", root: Self.drawer,
                               store: UserDefaults(suiteName: #function + UUID().uuidString)!)
        c.toggle("viewer")
        XCTAssertFalse(c.isOpen("viewer"))
        c.toggle("viewer")
        XCTAssertTrue(c.isOpen("viewer"))
    }
}
