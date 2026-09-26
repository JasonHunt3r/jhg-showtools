import XCTest
@testable import ShowToolsCore

final class ReorderTests: XCTestCase {
    // A 3-column grid of 186.5 × 216 pitch, as measured in the app.
    func slot(_ x: Double, _ y: Double, count: Int = 8, block: Int = 1) -> Int {
        Reorder.slot(x: x, y: y, columns: 3, pitchX: 186.5, pitchY: 216, count: count, blockSize: block)
    }

    func testSlotIsTheCellUnderThePoint() {
        XCTAssertEqual(slot(10, 10), 0)
        XCTAssertEqual(slot(200, 10), 1)
        XCTAssertEqual(slot(400, 10), 2)
        XCTAssertEqual(slot(10, 220), 3)
        XCTAssertEqual(slot(200, 220), 4)
    }

    func testSlotClampsToTheGrid() {
        XCTAssertEqual(slot(-50, -50), 0, "above or left of the first cell is the start")
        XCTAssertEqual(slot(5000, 10), 2, "right of the last column stays in that row")
        XCTAssertEqual(slot(10, 5000), 7, "below the last row is the end")
        XCTAssertEqual(slot(400, 220, count: 5), 4, "past the last tile in a short last row is the end")
    }

    func testSlotLeavesRoomForTheWholeBlock() {
        XCTAssertEqual(slot(10, 5000, block: 3), 5, "a block of 3 among 8 starts at 5 at the latest")
    }

    func testSlotDoesNotDependOnWhatIsDrawnThere() {
        // The same point gives the same slot every time: nothing to oscillate.
        XCTAssertEqual(slot(200, 220), slot(200, 220))
    }

    func testMovingPutsTheBlockAtTheIndex() {
        XCTAssertEqual(Reorder.moving([3], in: [1, 2, 3], to: 0), [3, 1, 2])
        XCTAssertEqual(Reorder.moving([1], in: [1, 2, 3], to: 2), [2, 3, 1], "to the very end")
        XCTAssertEqual(Reorder.moving([2], in: [1, 2, 3], to: 1), [1, 2, 3], "over its own slot, nothing moves")
        XCTAssertEqual(Reorder.moving([4, 1], in: [1, 2, 3, 4, 5], to: 2), [2, 3, 1, 4, 5],
                       "a selection keeps its own relative order, as one block")
        XCTAssertEqual(Reorder.moving([1], in: [1, 2, 3], to: 99), [2, 3, 1])
    }

    func testMergeKeepsHiddenFilesWhereTheyWere() {
        // all: 1 2 3 4 5; a filter hides 2 and 4; on screen 1 3 5 becomes 5 1 3.
        XCTAssertEqual(Reorder.merge([5, 1, 3], into: [1, 2, 3, 4, 5]), [5, 2, 1, 4, 3])
    }

    func testMergeFromAnotherSortSavesWhatIsOnScreen() {
        // Custom order 3 1 2; sorted by name the screen shows 1 2 3; a drop
        // there makes it 2 1 3. With nothing hidden, that's the new order.
        XCTAssertEqual(Reorder.merge([2, 1, 3], into: [3, 1, 2]), [2, 1, 3])
    }
}
