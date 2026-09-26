import XCTest
@testable import ShowToolsCore

/// Item 20: Aperture's rating keys and the filter that hides rejects.
final class RatingTests: XCTestCase {
    func testKeysAreAperturesKeys() {
        XCTAssertEqual(Rating.Key("0"), .set(0))
        XCTAssertEqual(Rating.Key("3"), .set(3))
        XCTAssertEqual(Rating.Key("5"), .set(5))
        XCTAssertEqual(Rating.Key("9"), .set(Rating.rejected))
        XCTAssertEqual(Rating.Key("-"), .step(-1))
        XCTAssertEqual(Rating.Key("="), .step(1))
        for other in ["6", "7", "8", "u", "y", "", "12"] { XCTAssertNil(Rating.Key(other), other) }
    }

    func testSteppingStopsAtUnratedAndFive() {
        XCTAssertEqual(Rating.stepped(3, by: -1), 2)
        XCTAssertEqual(Rating.stepped(1, by: -1), 0)
        XCTAssertEqual(Rating.stepped(0, by: -1), 0, "− never rejects; that's 9's job")
        XCTAssertEqual(Rating.stepped(5, by: 1), 5)
        XCTAssertEqual(Rating.stepped(0, by: 1), 1)
    }

    func testSteppingAReject() {
        XCTAssertEqual(Rating.stepped(Rating.rejected, by: 1), 0, "= lifts a reject to unrated")
        XCTAssertEqual(Rating.stepped(Rating.rejected, by: -1), Rating.rejected, "− leaves it alone")
    }

    func testEachFileStepsFromItsOwnRating() {
        let key = Rating.Key("=")!
        XCTAssertEqual([0, 2, 5, -1].map(key.applied), [1, 3, 5, 0])
        XCTAssertEqual([0, 2, 5, -1].map(Rating.Key("4")!.applied), [4, 4, 4, 4])
    }

    func testFilterHidesRejectsUnlessAsked() {
        let ratings = [-1, 0, 1, 3, 5]
        func shown(_ f: Int) -> [Int] { ratings.filter { Rating.Filter.matches($0, filter: f) } }
        XCTAssertEqual(shown(Rating.Filter.unratedOrBetter), [0, 1, 3, 5], "the default, and every older saved filter")
        XCTAssertEqual(shown(Rating.Filter.showAll), ratings)
        XCTAssertEqual(shown(Rating.Filter.rejectedOnly), [-1])
        XCTAssertEqual(shown(3), [3, 5])
    }

    func testOnlyTheDefaultFilterIsInactive() {
        XCTAssertFalse(Rating.Filter.isActive(0))
        for f in [-2, -1, 1, 5] { XCTAssertTrue(Rating.Filter.isActive(f), "\(f)") }
    }

    func testClamped() {
        XCTAssertEqual(Rating.clamped(-5), -1)
        XCTAssertEqual(Rating.clamped(9), 5)
        XCTAssertEqual(Rating.clamped(2), 2)
    }
}
