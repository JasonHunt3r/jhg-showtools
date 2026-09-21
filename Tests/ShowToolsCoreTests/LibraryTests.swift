import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ShowToolsCore

final class LibraryTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("showtools-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func writePNG(_ name: String, colour: CGFloat, frames: Int = 1) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let type = frames > 1 ? UTType.gif : UTType.png
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil)!
        for f in 0..<frames {
            let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(red: colour, green: CGFloat(f) / CGFloat(frames), blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]] as CFDictionary
            CGImageDestinationAddImage(dest, ctx.makeImage()!, frames > 1 ? props : nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func testIngestCopiesVerifiesAndDedupes() async throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib.noindex"))
        let src = try writePNG("red.png", colour: 1)
        let hash = try Ingest.sha256(of: src)
        XCTAssertNil(try lib.itemID(forHash: hash))

        let copied = try await Ingest.copyIn(src, expectedHash: hash, mediaDir: lib.mediaURL)
        XCTAssertEqual(copied.probe.kind, .image)
        XCTAssertEqual(copied.probe.width, 64)
        let item = try lib.insertItem(relativePath: copied.relativePath, hash: hash,
                                      probe: copied.probe, sourcePath: src.path)
        XCTAssertEqual(try lib.itemID(forHash: hash), item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.url(for: item).path))

        // A second file of the same name gets numbered, not overwritten.
        let other = try writePNG("red2.png", colour: 0.5)
        let dupName = dir.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: dupName, withIntermediateDirectories: true)
        let moved = dupName.appendingPathComponent("red.png")
        try FileManager.default.moveItem(at: other, to: moved)
        let c2 = try await Ingest.copyIn(moved, expectedHash: try Ingest.sha256(of: moved),
                                         mediaDir: lib.mediaURL)
        XCTAssertEqual(c2.relativePath, "red 2.png")
    }

    func testAnimatedGIFProbe() async throws {
        let gif = try writePNG("anim.gif", colour: 1, frames: 4)
        let p = await MediaProbe.read(gif)
        XCTAssertEqual(p?.kind, .animatedImage)
        XCTAssertEqual(p?.duration ?? 0, 1.0, accuracy: 0.01)
    }

    func testShowsRoundTripAndReorder() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        let b = try lib.insertItem(relativePath: "b.jpg", hash: "b", probe: probe, sourcePath: "")

        var show = try lib.createShow(name: "Trip", itemIDs: [a.id, b.id, a.id])
        XCTAssertEqual(show.slides.count, 3)
        XCTAssertTrue(show.slides.allSatisfy { $0.id > 0 })

        show.slides[2].settings.length = .seconds(9)
        show.slides.swapAt(0, 1)
        show.slides.remove(at: 1)
        show.defaults.kenBurns = .auto
        try lib.saveShow(show)

        let loaded = try lib.allShows()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].slides.map(\.itemID), [b.id, a.id])
        XCTAssertEqual(loaded[0].slides[1].settings.length, .seconds(9))
        XCTAssertEqual(loaded[0].defaults.kenBurns, .auto)

        try lib.deleteShow(id: show.id)
        XCTAssertTrue(try lib.allShows().isEmpty)
    }

    func testRefusesICloudLocation() {
        let icloud = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/ShowToolsTest")
        XCTAssertThrowsError(try Library(root: icloud))
        XCTAssertFalse(FileManager.default.fileExists(atPath: icloud.path))
    }
}

final class DecodingTests: XCTestCase {
    func testOneBadFieldDoesNotResetTheRest() throws {
        let json = #"{"length":7,"kenBurns":"garbage","loop":false,"fit":"fit"}"#
        let d = try JSONDecoder().decode(ShowDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(d.length, 7)
        XCTAssertEqual(d.loop, false)
        XCTAssertEqual(d.fit, .fit)
        XCTAssertEqual(d.kenBurns, .off, "unreadable field falls back alone")

        let s = try JSONDecoder().decode(SlideSettings.self,
            from: Data(#"{"length":{"seconds":{"_0":3}},"transition":{"style":"nope"}}"#.utf8))
        XCTAssertEqual(s.length, .seconds(3))
        XCTAssertNil(s.transition)
    }
}

final class UndoSupportTests: XCTestCase {
    func testSavingAnOldSnapshotRestoresRemovedSlidesWithTheirIDs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("st-undo-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try Library(root: dir)
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        var show = try lib.createShow(name: "S", itemIDs: [a.id, a.id, a.id])
        show.slides[1].settings.length = .seconds(7)
        show = try lib.saveShow(show)
        let before = show

        show.slides.remove(at: 1)
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].slides.count, 2)

        try lib.saveShow(before)   // what undo does
        let restored = try lib.allShows()[0]
        XCTAssertEqual(restored.slides.map(\.id), before.slides.map(\.id))
        XCTAssertEqual(restored.slides[1].settings.length, .seconds(7))
    }
}

final class FramingTests: XCTestCase {
    func testViewRegionFillLandscapeIntoWideOutput() {
        let r = Compositor.viewRegion(imageSize: CGSize(width: 4000, height: 3000), fit: .fill,
                                      kb: .centred, outputSize: CGSize(width: 1600, height: 900))
        XCTAssertEqual(r.width, 4000, accuracy: 0.01)
        XCTAssertEqual(r.height, 2250, accuracy: 0.01)
        XCTAssertEqual(r.minY, 375, accuracy: 0.01)
    }

    func testZoomAndTopLeftCentreClampsInsideImage() {
        let r = Compositor.viewRegion(imageSize: CGSize(width: 4000, height: 3000), fit: .fill,
                                      kb: KenBurnsFrame(x: 0, y: 0, zoom: 2),
                                      outputSize: CGSize(width: 1600, height: 900))
        XCTAssertEqual(r.origin, .zero)
        XCTAssertEqual(r.width, 2000, accuracy: 0.01)
    }
}

extension LibraryTests {
    /// A library written before ratings existed (schema version 1), opened by
    /// this build: the file comes through unrated and nothing else changes.
    func testAVersionOneLibraryUpgradesToRatings() throws {
        let root = dir.appendingPathComponent("Old.noindex")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Media"),
                                                withIntermediateDirectories: true)
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("""
                CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, rel_path TEXT NOT NULL UNIQUE,
                    hash TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, width INTEGER NOT NULL,
                    height INTEGER NOT NULL, duration REAL, ingested_at REAL NOT NULL,
                    source_path TEXT NOT NULL);
                CREATE TABLE shows (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    defaults TEXT NOT NULL, created_at REAL NOT NULL);
                CREATE TABLE slides (id INTEGER PRIMARY KEY AUTOINCREMENT,
                    show_id INTEGER NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, item_id INTEGER NOT NULL REFERENCES items(id),
                    settings TEXT NOT NULL);
                INSERT INTO items (rel_path, hash, kind, width, height, duration, ingested_at, source_path)
                    VALUES ('a.jpg', 'h1', 'image', 400, 300, NULL, 0, '/x/a.jpg');
                PRAGMA user_version = 1;
                """)
        }
        let lib = try Library(root: root)
        let items = try lib.allItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].relativePath, "a.jpg")
        XCTAssertEqual(items[0].pixelWidth, 400)
        XCTAssertEqual(items[0].rating, 0)

        try lib.setRating(4, for: [items[0].id])
        XCTAssertEqual(try Library(root: root).allItems()[0].rating, 4)
        try lib.setRating(9, for: [items[0].id])                  // clamped
        XCTAssertEqual(try Library(root: root).allItems()[0].rating, 5)
    }
}
