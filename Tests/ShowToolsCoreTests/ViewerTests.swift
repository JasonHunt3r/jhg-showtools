import XCTest
import CoreGraphics
@testable import ShowToolsCore

/// The viewer drawer's pure parts (`spec/plan.md`, "The viewer drawer").
final class ViewerTests: XCTestCase {
    // MARK: Which are shown

    func testUnderTheCapShowsAllWithNoMore() {
        let r = Viewer.shown([1, 2, 3], primary: 2)
        XCTAssertEqual(r.ids, [1, 2, 3])
        XCTAssertEqual(r.more, 0)
    }

    func testOverTheCapShowsTheFirstTwelveAndCountsTheRest() {
        let r = Viewer.shown(Array(1...4000), primary: 5)
        XCTAssertEqual(r.ids, Array(1...12))
        XCTAssertEqual(r.more, 3988)
    }

    /// The outlined one is always on screen, even past the cap.
    func testAnOutlinedFilePastTheCapTakesTheLastPlace() {
        let r = Viewer.shown(Array(1...20), primary: 17)
        XCTAssertEqual(r.ids, Array(1...11) + [17])
        XCTAssertEqual(r.more, 8)
    }

    // MARK: ← / → within the selection

    func testStepWrapsBothWays() {
        let ids = [4, 8, 15]
        XCTAssertEqual(Viewer.step(ids, from: 8, by: 1), 15)
        XCTAssertEqual(Viewer.step(ids, from: 15, by: 1), 4)
        XCTAssertEqual(Viewer.step(ids, from: 4, by: -1), 15)
    }

    func testStepWithNoneOutlinedStartsAtAnEnd() {
        XCTAssertEqual(Viewer.step([4, 8, 15], from: nil, by: 1), 4)
        XCTAssertEqual(Viewer.step([4, 8, 15], from: nil, by: -1), 15)
        XCTAssertEqual(Viewer.step([4, 8, 15], from: 99, by: 1), 4, "an outline that left the selection restarts")
        XCTAssertNil(Viewer.step([Int](), from: nil, by: 1))
    }

    // MARK: Side by side

    func testOnePictureFillsTheBoxFitted() {
        let f = Viewer.sideBySide(aspects: [2], in: CGSize(width: 800, height: 300))
        XCTAssertEqual(f, [CGRect(x: 100, y: 0, width: 600, height: 300)])
    }

    /// Two landscape pictures in a wide, short drawer go side by side, not
    /// stacked: that's where they come out largest.
    func testTwoLandscapesInAWideDrawerSitSideBySide() {
        let f = Viewer.sideBySide(aspects: [1.5, 1.5], in: CGSize(width: 1000, height: 300), spacing: 10)
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f[0].minY, f[1].minY)
        XCTAssertLessThan(f[0].maxX, f[1].minX)
        XCTAssertEqual(f[0].height, 300)
    }

    /// Two in a tall drawer stack into one column instead.
    func testTwoLandscapesInATallDrawerStack() {
        let f = Viewer.sideBySide(aspects: [1.5, 1.5], in: CGSize(width: 400, height: 700), spacing: 10)
        XCTAssertEqual(f[0].minX, f[1].minX)
        XCTAssertLessThan(f[0].maxY, f[1].minY)
    }

    /// Every frame stays inside the box, none overlap, and a short last row
    /// is centred.
    func testFramesStayInsideWithoutOverlapAndTheLastRowIsCentred() {
        let box = CGSize(width: 900, height: 400)
        let f = Viewer.sideBySide(aspects: [1.5, 0.75, 1, 1.5, 1.33], in: box, spacing: 8)
        XCTAssertEqual(f.count, 5)
        for r in f {
            XCTAssertGreaterThanOrEqual(r.minX, -0.001)
            XCTAssertGreaterThanOrEqual(r.minY, -0.001)
            XCTAssertLessThanOrEqual(r.maxX, box.width + 0.001)
            XCTAssertLessThanOrEqual(r.maxY, box.height + 0.001)
        }
        for i in f.indices { for j in f.indices where j > i { XCTAssertFalse(f[i].intersects(f[j]), "\(i) and \(j)") } }
        // Whatever the layout, a row that's short sits centred.
        let rows = Dictionary(grouping: f, by: { $0.midY.rounded() })
        let fullest = rows.values.map(\.count).max()!
        for row in rows.values where row.count < fullest {
            let left = row.map(\.minX).min()!, right = box.width - row.map(\.maxX).max()!
            XCTAssertEqual(left, right, accuracy: 40, "a short row is roughly centred")
        }
    }

    func testNothingToShow() {
        XCTAssertEqual(Viewer.sideBySide(aspects: [], in: CGSize(width: 100, height: 100)), [])
        XCTAssertEqual(Viewer.sideBySide(aspects: [1], in: .zero), [])
    }

    /// Audio has no picture size (0 × 0): it's placed as a square.
    func testNoAspectCountsAsSquare() {
        let f = Viewer.sideBySide(aspects: [0], in: CGSize(width: 300, height: 100))
        XCTAssertEqual(f, [CGRect(x: 100, y: 0, width: 100, height: 100)])
    }
}
