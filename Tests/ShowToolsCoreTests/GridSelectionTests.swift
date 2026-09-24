import XCTest
@testable import ShowToolsCore

final class GridSelectionTests: XCTestCase {
    let items = Array(1...10)

    func testClickSelectsOnlyThatOneAndAnchorsThere() {
        let r = GridSelection.click(5)
        XCTAssertEqual(r.selected, [5])
        XCTAssertEqual(r.anchor, 5)
        XCTAssertEqual(r.base, [5])
        XCTAssertEqual(r.cursor, 5)
    }

    func testCommandClickTogglesAndMovesTheAnchor() {
        let added = GridSelection.commandClick(5, selected: [2])
        XCTAssertEqual(added.selected, [2, 5])
        XCTAssertEqual(added.anchor, 5, "the anchor follows the ⌘-click, not the plain click before it")
        XCTAssertEqual(added.base, [2, 5])

        let removed = GridSelection.commandClick(2, selected: [2, 5])
        XCTAssertEqual(removed.selected, [5])
        XCTAssertEqual(removed.anchor, 2)
    }

    func testShiftClickSelectsTheRangeFromTheAnchor() {
        let anchored = GridSelection.click(5)
        let r = GridSelection.shiftClick(8, anchor: anchored.anchor, base: anchored.base, in: items)
        XCTAssertEqual(r.selected, [5, 6, 7, 8])
        XCTAssertEqual(r.anchor, 5, "the anchor doesn't move on a ⇧-click")
        // Backwards works too.
        let back = GridSelection.shiftClick(2, anchor: anchored.anchor, base: anchored.base, in: items)
        XCTAssertEqual(back.selected, [2, 3, 4, 5])
    }

    /// B3's exact example: click 5, ⇧-click 10, ⇧-click 7 — Finder leaves
    /// 5–7 selected, not 5–10 (the old `.formUnion` bug only ever added).
    func testRepeatedShiftClicksReplaceRatherThanAccumulate() {
        let clicked = GridSelection.click(5)
        let extended = GridSelection.shiftClick(10, anchor: clicked.anchor, base: clicked.base, in: items)
        XCTAssertEqual(extended.selected, Set(5...10))
        let shrunk = GridSelection.shiftClick(7, anchor: extended.anchor, base: extended.base, in: items)
        XCTAssertEqual(shrunk.selected, [5, 6, 7], "replaced, not unioned with the 5–10 the first ⇧-click made")
    }

    /// E1's exact example: click 2, ⌘-click 8, ⇧-click 10 — Finder and
    /// Final Cut add 8–10 to what was already selected (2 and 8), because
    /// the anchor is wherever was last plainly or ⌘-clicked (8), not the
    /// first selected item (which the storyline's old bug used instead).
    func testShiftClickAnchorsAtTheLastPlainOrCommandClick() {
        let clicked = GridSelection.click(2)
        let added = GridSelection.commandClick(8, selected: clicked.selected)
        let extended = GridSelection.shiftClick(10, anchor: added.anchor, base: added.base, in: items)
        XCTAssertEqual(extended.selected, [2, 8, 9, 10])
    }

    func testShiftClickWithNoAnchorActsLikeAPlainClick() {
        let r = GridSelection.shiftClick(5, anchor: nil, base: [], in: items)
        XCTAssertEqual(r.selected, [5])
        XCTAssertEqual(r.anchor, 5)
    }

    func testShiftClickOfAnIDNotInItemsActsLikeAPlainClick() {
        let r = GridSelection.shiftClick(99, anchor: 3, base: [3], in: items)
        XCTAssertEqual(r.selected, [99])
        XCTAssertEqual(r.anchor, 99)
    }

    // MARK: Arrow-key stepping (the index arithmetic for B2/E2)

    func testStepMovesByDeltaAndReplacesTheSelection() {
        let r = GridSelection.step(from: 5, by: 1, anchor: 5, base: [5], in: items, extend: false)
        XCTAssertEqual(r.selected, [6])
        XCTAssertEqual(r.anchor, 6, "a plain step moves the anchor with it")
        XCTAssertEqual(GridSelection.step(from: 5, by: -1, anchor: 5, base: [5], in: items, extend: false).selected, [4])
    }

    /// ↑/↓ in a grid step by the column count, not always 1.
    func testStepByAColumnCountMovesARow() {
        let r = GridSelection.step(from: 3, by: 4, anchor: 3, base: [3], in: items, extend: false)
        XCTAssertEqual(r.selected, [7])
    }

    func testStepFromNoCursorStartsAtAnEnd() {
        XCTAssertEqual(GridSelection.step(from: nil, by: 1, anchor: nil, base: [], in: items, extend: false).selected, [1])
        XCTAssertEqual(GridSelection.step(from: nil, by: -1, anchor: nil, base: [], in: items, extend: false).selected, [10])
    }

    func testStepClampsAtTheEnds() {
        XCTAssertEqual(GridSelection.step(from: 10, by: 1, anchor: 10, base: [10], in: items, extend: false).selected, [10])
        XCTAssertEqual(GridSelection.step(from: 1, by: -1, anchor: 1, base: [1], in: items, extend: false).selected, [1])
    }

    func testStepOnEmptyItemsSelectsNothing() {
        let r = GridSelection.step(from: 1, by: 1, anchor: 1, base: [1], in: [], extend: false)
        XCTAssertEqual(r.selected, [])
        XCTAssertNil(r.anchor)
    }

    /// A run of ⇧-arrows grows (or shrinks, reversing) the same range a run
    /// of ⇧-clicks would — the anchor stays put across the whole run, and
    /// each step moves on from where the last one left the cursor, not
    /// back from the anchor.
    func testExtendingStepsGrowARangeFromAFixedAnchor() {
        let start = GridSelection.click(5)
        let out1 = GridSelection.step(from: start.cursor, by: 1, anchor: start.anchor, base: start.base, in: items, extend: true)
        XCTAssertEqual(out1.selected, [5, 6])
        let out2 = GridSelection.step(from: out1.cursor, by: 1, anchor: out1.anchor, base: out1.base, in: items, extend: true)
        XCTAssertEqual(out2.selected, [5, 6, 7])
        // Stepping back past the anchor shrinks, then crosses to the other side.
        let out3 = GridSelection.step(from: out2.cursor, by: -3, anchor: out2.anchor, base: out2.base, in: items, extend: true)
        XCTAssertEqual(out3.selected, [4, 5], "crossed one past the anchor, onto the other side")
    }

    func testExtendingWithNoAnchorActsLikeAPlainStep() {
        let r = GridSelection.step(from: 5, by: 1, anchor: nil, base: [], in: items, extend: true)
        XCTAssertEqual(r.selected, [6])
    }
}
