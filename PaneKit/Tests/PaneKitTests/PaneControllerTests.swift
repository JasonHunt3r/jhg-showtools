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
}
