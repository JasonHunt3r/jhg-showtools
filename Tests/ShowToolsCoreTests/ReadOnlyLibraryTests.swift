import XCTest
@testable import ShowToolsCore

/// BGTools' way in (spec/bgtools.md, "BGTools' read path").
final class ReadOnlyLibraryTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("showtools-ro-\(UUID().uuidString)/Lib.noindex")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func testRefusesAMissingLibraryWithoutCreatingOne() {
        XCTAssertThrowsError(try Library(readingOnly: root)) {
            XCTAssertEqual($0 as? LibraryReadError, .missing(root))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSeesSavesAndCannotWrite() throws {
        let writer = try Library(root: root)
        let reader = try Library(readingOnly: root)
        let before = reader.changeCount
        let saved = try writer.createShow(name: "Desk")
        XCTAssertNotEqual(reader.changeCount, before)
        let shows = try reader.snapshot { try reader.allShows() }
        XCTAssertEqual(shows.map(\.name), ["Desk"])

        var renamed = saved
        renamed.name = "Changed"
        XCTAssertThrowsError(try reader.saveShow(renamed))
        XCTAssertThrowsError(try reader.createShow(name: "Nope"))
        XCTAssertThrowsError(try reader.identifier())
        XCTAssertEqual(try writer.allShows().map(\.name), ["Desk"])
    }

    func testRefusesAnOtherSchema() throws {
        _ = try Library(root: root)
        let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
        try db.exec("PRAGMA user_version = \(Library.schemaVersion - 1)")
        XCTAssertThrowsError(try Library(readingOnly: root)) {
            XCTAssertEqual($0 as? LibraryReadError, .version(found: Library.schemaVersion - 1, known: Library.schemaVersion))
        }
    }
}
