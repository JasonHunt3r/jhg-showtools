import XCTest
@testable import ShowToolsCore

final class BatchRenameTests: XCTestCase {
    func testReplaceTextKeepsTheExtensionAndIgnoresIt() {
        let out = BatchRename.apply(.replaceText(find: "IMG", with: "Beach"),
                                     to: ["IMG_001.jpg", "IMG_IMG.heic", "vacation.png"])
        XCTAssertEqual(out, ["Beach_001.jpg", "Beach_Beach.heic", "vacation.png"])
    }

    func testEmptyFindChangesNothing() {
        XCTAssertEqual(BatchRename.apply(.replaceText(find: "", with: "x"), to: ["a.jpg"]), ["a.jpg"])
    }

    func testAddTextBeforeOrAfterTheNameNotTheExtension() {
        XCTAssertEqual(BatchRename.apply(.addText("Trip - ", .before), to: ["a.jpg"]), ["Trip - a.jpg"])
        XCTAssertEqual(BatchRename.apply(.addText(" (edited)", .after), to: ["a.jpg"]), ["a (edited).jpg"])
    }

    func testFormatIndexCountsUpFromStart() {
        let out = BatchRename.apply(.format(name: "Wedding", counter: .index, start: 5),
                                     to: ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(out, ["Wedding 5.jpg", "Wedding 6.jpg", "Wedding 7.jpg"])
    }

    /// Padded to whatever width the batch's highest number needs, not a
    /// fixed guess: ten files starting at 1 need two digits for all of them.
    func testFormatCounterPadsToTheBatchsWidth() {
        let names = (1...10).map { "photo\($0).jpg" }
        let out = BatchRename.apply(.format(name: "Show", counter: .counter, start: 1), to: names)
        XCTAssertEqual(out.first, "Show 01.jpg")
        XCTAssertEqual(out.last, "Show 10.jpg")
    }

    func testFormatDateStaysUniqueAcrossTheBatch() {
        let out = BatchRename.apply(.format(name: "Show", counter: .date, start: 1), to: ["a.jpg", "b.jpg"])
        XCTAssertEqual(out.count, 2)
        XCTAssertNotEqual(out[0], out[1])
        XCTAssertTrue(out[0].hasPrefix("Show "))
    }

    func testANameWithNoExtensionIsLeftBare() {
        XCTAssertEqual(BatchRename.apply(.addText("!", .after), to: ["README"]), ["README!"])
    }
}
