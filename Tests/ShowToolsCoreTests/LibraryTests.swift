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
        show.defaults.panAndZoom = .auto
        try lib.saveShow(show)

        let loaded = try lib.allShows()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].slides.map(\.itemID), [b.id, a.id])
        XCTAssertEqual(loaded[0].slides[1].settings.length, .seconds(9))
        XCTAssertEqual(loaded[0].defaults.panAndZoom, .auto)

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
        let json = #"{"length":7,"panAndZoom":"garbage","loop":false,"fit":"fit"}"#
        let d = try JSONDecoder().decode(ShowDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(d.length, 7)
        XCTAssertEqual(d.loop, false)
        XCTAssertEqual(d.fit, .fit)
        XCTAssertEqual(d.panAndZoom, .off, "unreadable field falls back alone")

        let s = try JSONDecoder().decode(SlideSettings.self,
            from: Data(#"{"length":{"seconds":{"_0":3}},"transition":{"style":"nope"}}"#.utf8))
        XCTAssertEqual(s.length, .seconds(3))
        XCTAssertNil(s.transition)
    }

    /// The small value types inside the settings fall back field by field
    /// too, so a field added later can't cost a saved Pan and Zoom move, pivot
    /// or background.
    func testSmallValueTypesDecodeFieldByField() throws {
        let kb = try JSONDecoder().decode(PanAndZoom.self, from: Data(
            #"{"start":{"x":0.2,"y":0.3,"zoom":1.5},"end":{"x":0.7,"zoom":"bad"}}"#.utf8))
        XCTAssertEqual(kb.start, PanAndZoomFrame(x: 0.2, y: 0.3, zoom: 1.5))
        XCTAssertEqual(kb.end, PanAndZoomFrame(x: 0.7, y: 0.5, zoom: 1))

        let p = try JSONDecoder().decode(ImagePoint.self, from: Data(#"{"x":0.1,"future":true}"#.utf8))
        XCTAssertEqual(p, ImagePoint(x: 0.1, y: 0.5))

        let s = try JSONDecoder().decode(SlideSettings.self, from: Data(
            #"{"length":{"seconds":{"_0":3}},"background":{"red":1,"green":0.5}}"#.utf8))
        XCTAssertEqual(s.background, SRGBColor(red: 1, green: 0.5, blue: 0))
        XCTAssertEqual(s.length, .seconds(3))
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
                                      kb: PanAndZoomFrame(x: 0, y: 0, zoom: 2),
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

extension LibraryTests {
    func testOverlaysRoundTrip() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        let logo = try lib.insertItem(relativePath: "logo.png", hash: "l", probe: probe, sourcePath: "")
        var show = try lib.createShow(name: "Over", itemIDs: [a.id])
        XCTAssertEqual(show.overlays, [])
        var clip = OverlayClip(itemID: logo.id, start: 2, length: 3)
        clip.blend = .screen; clip.opacity = 0.7
        clip.transform.scale = 0.3; clip.transform.offsetX = 0.35
        show.overlays = [clip]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].overlays, [clip])
    }

    func testRowOrderRoundTrips() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        var show = try lib.createShow(name: "Rows")
        XCTAssertEqual(show.rows.map(\.kind), [.images, .transitions, .slides, .music])
        show.rows = [show.rows[3], show.rows[2], show.rows[0], show.rows[1]]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].rows, show.rows)
    }

    /// A version-6 library's shows have no saved rows: they read as the
    /// default order, and the new order saves.
    func testAVersionSixLibraryGetsRowsInTheDefaultOrder() throws {
        let root = dir.appendingPathComponent("Six.noindex")
        do {
            let lib = try Library(root: root)
            _ = try lib.createShow(name: "Old")
        }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE group_items; DROP TABLE groups; DROP TABLE rhythm_patterns; ALTER TABLE shows DROP COLUMN editor; ALTER TABLE shows DROP COLUMN markers; ALTER TABLE shows DROP COLUMN music; ALTER TABLE shows DROP COLUMN rows; PRAGMA user_version = 6;")
        }
        let lib = try Library(root: root)
        var show = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(show.rows.map(\.kind), [.images, .transitions, .slides, .music])
        show.rows.swapAt(0, 3)
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].rows.map(\.kind), [.music, .transitions, .slides, .images])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library.sqlite.v6.bak").path))
    }

    func testAVersionTenLibraryGetsRhythmPatterns() throws {
        let root = dir.appendingPathComponent("Ten.noindex")
        do { _ = try Library(root: root) }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE group_items; DROP TABLE groups; DROP TABLE rhythm_patterns; PRAGMA user_version = 10;")
        }
        let lib = try Library(root: root)
        XCTAssertEqual(try lib.allRhythmPatterns(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library.sqlite.v10.bak").path))
    }

    func testAVersionElevenLibrarysPatternsKeepTheirSettingAsIs() throws {
        let root = dir.appendingPathComponent("Eleven.noindex")
        do {
            let lib = try Library(root: root)
            try lib.saveRhythmPattern(name: "old", RhythmPattern(text: "h q q"))
        }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE group_items; DROP TABLE groups; ALTER TABLE rhythm_patterns DROP COLUMN beats_per_quarter; PRAGMA user_version = 11;")
        }
        let lib = try Library(root: root)
        XCTAssertEqual(try lib.allRhythmPatterns().map(\.pattern.text), ["h q q"])
        XCTAssertNil(try lib.allRhythmPatterns().first?.beatsPerQuarter, "no setting: leave it as it is")
        try lib.saveRhythmPattern(name: "new", RhythmPattern(text: "q"), beatsPerQuarter: 2)
        XCTAssertEqual(try lib.allRhythmPatterns().first { $0.name == "new" }?.beatsPerQuarter, 2)
    }

    func testRhythmPatternsSaveByNameAndReplaceASameName() throws {
        let lib = try Library(root: dir.appendingPathComponent("R.noindex"))
        let a = try lib.saveRhythmPattern(name: "verse", RhythmPattern(text: "h q q"))
        try lib.saveRhythmPattern(name: "Chorus", RhythmPattern(text: "e e q"))
        let again = try lib.saveRhythmPattern(name: "verse", RhythmPattern(text: "w"))
        XCTAssertEqual(again.id, a.id, "same name: replaced, not doubled")
        XCTAssertEqual(try lib.allRhythmPatterns().map(\.name), ["Chorus", "verse"])
        XCTAssertEqual(try lib.allRhythmPatterns().map(\.pattern.text), ["e e q", "w"])
        try lib.deleteRhythmPattern(id: a.id)
        XCTAssertEqual(try lib.allRhythmPatterns().map(\.name), ["Chorus"])
    }

    func testRowsNormalizeToEveryKindOnce() {
        let music = TimelineRow(kind: .music), slides = TimelineRow(kind: .slides)
        // Missing kinds go back after the rows the default order puts before them.
        let n = TimelineRow.normalized([music, slides])
        XCTAssertEqual(n.map(\.kind), [.images, .transitions, .music, .slides])
        XCTAssertEqual(n[2].id, music.id)
        // A duplicate kind keeps its first appearance.
        XCTAssertEqual(TimelineRow.normalized([slides, slides, music]).map(\.kind),
                       [.images, .transitions, .slides, .music])
        // An unreadable row is skipped; the rest are kept.
        let json = #"[{"kind":"music","id":"\#(music.id)"},{"kind":"hologram"},{"kind":"slides"}]"#
        XCTAssertEqual(TimelineRow.decodeList(json).map(\.kind), [.music, .slides])
        XCTAssertEqual(TimelineRow.decodeList(json).first?.id, music.id)
    }

    func testOneUnreadableOverlayDoesNotCostTheOthers() {
        let json = #"""
            [{"itemID":1,"start":0,"length":2,"blend":"screen"},
             {"itemID":"nope","start":1},
             {"itemID":2,"start":5,"length":1,"blend":"sparkly"}]
            """#
        let clips = OverlayClip.decodeList(json)
        XCTAssertEqual(clips.map(\.itemID), [1, 2])
        XCTAssertEqual(clips[0].blend, .screen)
        XCTAssertEqual(clips[1].blend, .normal)       // the bad field falls back alone
        XCTAssertEqual(OverlayClip.decodeList("not json"), [])
    }
}

// MARK: - Collections (schema 4)

extension LibraryTests {
    /// A library as schema 3 left it, with a show and a file the show
    /// doesn't use: after the upgrade, one starting collection has both
    /// files and the show is in it.
    func testAVersionThreeLibraryGetsAStartingCollection() throws {
        let root = dir.appendingPathComponent("V3.noindex")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Media"),
                                                withIntermediateDirectories: true)
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("""
                CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, rel_path TEXT NOT NULL UNIQUE,
                    hash TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, width INTEGER NOT NULL,
                    height INTEGER NOT NULL, duration REAL, ingested_at REAL NOT NULL,
                    source_path TEXT NOT NULL, rating INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE shows (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
                    defaults TEXT NOT NULL, created_at REAL NOT NULL, overlays TEXT NOT NULL DEFAULT '[]');
                CREATE TABLE slides (id INTEGER PRIMARY KEY AUTOINCREMENT,
                    show_id INTEGER NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL, item_id INTEGER NOT NULL REFERENCES items(id),
                    settings TEXT NOT NULL);
                INSERT INTO items (rel_path, hash, kind, width, height, duration, ingested_at, source_path, rating)
                    VALUES ('a.jpg', 'h1', 'image', 400, 300, NULL, 1, '', 3),
                           ('b.jpg', 'h2', 'image', 400, 300, NULL, 2, '', 0);
                INSERT INTO shows (name, defaults, created_at) VALUES ('Test Show', '{}', 0);
                INSERT INTO slides (show_id, position, item_id, settings) VALUES (1, 0, 1, '{}');
                PRAGMA user_version = 3;
                """)
        }
        let lib = try Library(root: root)
        let collections = try lib.allCollections()
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections[0].name, Library.startingCollectionName)
        XCTAssertEqual(Set(collections[0].itemIDs), [1, 2])
        let shows = try lib.allShows()
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows[0].collectionID, collections[0].id)
        XCTAssertEqual(shows[0].slides.map(\.itemID), [1])
        XCTAssertEqual(try lib.allItems().first?.rating, 3)          // nothing else touched
    }

    func testANewLibraryStartsWithOneEmptyCollection() throws {
        let lib = try Library(root: dir.appendingPathComponent("New"))
        let c = try lib.allCollections()
        XCTAssertEqual(c.map(\.name), [Library.startingCollectionName])
        XCTAssertEqual(c[0].itemIDs, [])
    }

    func testCollectionsHoldFilesAndShows() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        let b = try lib.insertItem(relativePath: "b.jpg", hash: "b", probe: probe, sourcePath: "")
        let c = try lib.insertItem(relativePath: "c.jpg", hash: "c", probe: probe, sourcePath: "")

        let wedding = try lib.createCollection(name: "Wedding")
        try lib.addItems([a.id, b.id, a.id], toCollection: wedding.id)      // a twice: once is enough
        var show = try lib.createShow(name: "Ceremony", collectionID: wedding.id, itemIDs: [b.id, c.id])
        // The show's files joined its collection (c was new to it).
        var w = try lib.allCollections().first { $0.id == wedding.id }!
        XCTAssertEqual(w.itemIDs, [a.id, b.id, c.id])

        try lib.removeItems([a.id], fromCollection: wedding.id)
        try lib.renameCollection(id: wedding.id, to: "Wedding 2026")
        w = try lib.allCollections().first { $0.id == wedding.id }!
        XCTAssertEqual(w.name, "Wedding 2026")
        XCTAssertEqual(w.itemIDs, [b.id, c.id])

        // Saving keeps its collection; deleting the collection takes the show.
        show.name = "Ceremony (edit)"
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows().first { $0.id == show.id }?.collectionID, wedding.id)
        try lib.deleteCollection(id: wedding.id)
        XCTAssertNil(try lib.allShows().first { $0.id == show.id })
        XCTAssertEqual(try lib.allItems().count, 3)                          // files stay
    }

    /// Deleting a file removes every slide that used it (even several in
    /// the same show) and its collection memberships; restoring puts every
    /// row back with its original id, so the show's slide order — and
    /// anything else keyed on those ids — comes back exactly as it was.
    func testDeleteItemsRemovesSlidesAndRestoreItemsPutsThemBack() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        let b = try lib.insertItem(relativePath: "b.jpg", hash: "b", probe: probe, sourcePath: "")
        let wedding = try lib.createCollection(name: "Wedding")
        try lib.addItems([a.id, b.id], toCollection: wedding.id)
        let show = try lib.createShow(name: "Ceremony", collectionID: wedding.id, itemIDs: [a.id, b.id, a.id])
        let originalSlideIDs = try lib.allShows().first { $0.id == show.id }!.slides.map(\.id)

        let deleted = try lib.deleteItems([a.id])
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted[0].slides.count, 2)                            // a appeared twice
        XCTAssertEqual(deleted[0].collectionIDs, [wedding.id])
        XCTAssertNil(try lib.itemID(forHash: "a"))
        XCTAssertEqual(try lib.allShows().first { $0.id == show.id }?.slides.map(\.itemID), [b.id])
        XCTAssertEqual(try lib.allCollections().first { $0.id == wedding.id }?.itemIDs, [b.id])

        try lib.restoreItems(deleted)
        XCTAssertEqual(try lib.itemID(forHash: "a"), a.id)
        let restored = try lib.allShows().first { $0.id == show.id }!
        XCTAssertEqual(restored.slides.map(\.itemID), [a.id, b.id, a.id])     // same order as before
        XCTAssertEqual(restored.slides.map(\.id), originalSlideIDs)          // same slide identities
        XCTAssertEqual(Set(try lib.allCollections().first { $0.id == wedding.id }!.itemIDs), Set([a.id, b.id]))
    }

    /// Renaming moves the file on disk and updates its row; a name already
    /// taken is numbered rather than overwriting; renaming back (the old
    /// names `renameItems` hands back) is undo, and works whichever
    /// direction it's called.
    func testRenameItemsMovesFilesAndAvoidsCollisions() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        try Data().write(to: lib.mediaURL.appendingPathComponent("a.jpg"))
        try Data().write(to: lib.mediaURL.appendingPathComponent("b.jpg"))
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        let b = try lib.insertItem(relativePath: "b.jpg", hash: "b", probe: probe, sourcePath: "")

        // b is renamed to a name a file on disk already has (untracked,
        // just to prove the numbering looks at the real filesystem).
        try Data().write(to: lib.mediaURL.appendingPathComponent("taken.jpg"))
        let previous = try lib.renameItems([a.id: "Wedding 1.jpg", b.id: "taken.jpg"])
        XCTAssertEqual(previous, [a.id: "a.jpg", b.id: "b.jpg"])
        XCTAssertEqual(try lib.allItems().first { $0.id == a.id }?.relativePath, "Wedding 1.jpg")
        XCTAssertEqual(try lib.allItems().first { $0.id == b.id }?.relativePath, "taken 2.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.mediaURL.appendingPathComponent("Wedding 1.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lib.mediaURL.appendingPathComponent("a.jpg").path))

        // Undo: renaming back with what came back above.
        try lib.renameItems(previous)
        XCTAssertEqual(try lib.allItems().first { $0.id == a.id }?.relativePath, "a.jpg")
        XCTAssertEqual(try lib.allItems().first { $0.id == b.id }?.relativePath, "b.jpg")
    }

    /// Tags round-trip through the database, and survive a delete + undo
    /// (schema 6).
    func testTagsRoundTripAndSurviveDeleteAndRestore() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let a = try lib.insertItem(relativePath: "a.jpg", hash: "a", probe: probe, sourcePath: "")
        XCTAssertEqual(a.tags, [])                                         // untagged by default

        try lib.setTags(["Wedding", "2026"], for: a.id)
        XCTAssertEqual(try lib.allItems().first { $0.id == a.id }?.tags, ["Wedding", "2026"])

        let deleted = try lib.deleteItems([a.id])
        XCTAssertEqual(deleted[0].item.tags, ["Wedding", "2026"])
        try lib.restoreItems(deleted)
        XCTAssertEqual(try lib.allItems().first { $0.id == a.id }?.tags, ["Wedding", "2026"])
    }

    /// A file moved by hand (outside the app, so the database wasn't told)
    /// is found again by its hash and its row is pointed at the new path;
    /// one truly missing (no file anywhere with that hash) is reported,
    /// not silently dropped or matched to the wrong thing.
    func testRelinkFindsAFileMovedByHandAndReportsWhatsStillMissing() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        let bytes = Data("a real file's bytes".utf8)
        try bytes.write(to: lib.mediaURL.appendingPathComponent("a.jpg"))
        let hash = try Ingest.sha256(of: lib.mediaURL.appendingPathComponent("a.jpg"))
        let a = try lib.insertItem(relativePath: "a.jpg", hash: hash, probe: probe, sourcePath: "")
        let b = try lib.insertItem(relativePath: "gone.jpg", hash: "no-file-has-this-hash", probe: probe, sourcePath: "")

        // Rearranged in Finder, by hand: moved into a subfolder and renamed,
        // without the app's knowledge.
        try FileManager.default.createDirectory(at: lib.mediaURL.appendingPathComponent("2026"),
                                                 withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: lib.mediaURL.appendingPathComponent("a.jpg"),
                                         to: lib.mediaURL.appendingPathComponent("2026/moved.jpg"))

        let outcomes = try lib.relinkMissingItems()
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(outcomes.first { $0.itemID == a.id }?.newPath, "2026/moved.jpg")
        XCTAssertNil(outcomes.first { $0.itemID == b.id }?.newPath)

        XCTAssertEqual(try lib.allItems().first { $0.id == a.id }?.relativePath, "2026/moved.jpg")
        XCTAssertEqual(try lib.allItems().first { $0.id == b.id }?.relativePath, "gone.jpg")   // untouched

        // Nothing left to relink now that a is fixed and b has no match.
        XCTAssertEqual(try lib.relinkMissingItems().count, 1)
    }
}

// MARK: - The library itself (schema 5)

extension LibraryTests {
    func testPrivateFlagLivesInTheLibrary() throws {
        let root = dir.appendingPathComponent("Secret.noindex")
        let lib = try Library(root: root)
        XCTAssertEqual(lib.name, "Secret")
        XCTAssertFalse(lib.isPrivate)
        try lib.setPrivate(true)
        XCTAssertTrue(try Library(root: root).isPrivate)       // held in the library, wherever it opens
        try lib.setPrivate(false)
        XCTAssertFalse(try Library(root: root).isPrivate)
        XCTAssertEqual(try Library(root: dir.appendingPathComponent("Plain")).name, "Plain")
    }
}

extension LibraryTests {
    /// Opening an older library copies its database first, as it was.
    func testAnUpgradeKeepsABackupOfTheOldVersion() throws {
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
        _ = try Library(root: root)
        let backup = root.appendingPathComponent("Library.sqlite.v1.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let old = try Database(path: backup.path)
        XCTAssertEqual(old.userVersion, 1)
        XCTAssertEqual(try old.prepare("SELECT rel_path FROM items").firstText(), "a.jpg")

        // Opening it again: already current, so no new backup, and no error.
        _ = try Library(root: root)
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".bak") }
        XCTAssertEqual(backups, ["Library.sqlite.v1.bak"])
    }

    /// A brand-new library has nothing to back up, and starts current.
    func testANewLibraryNeedsNoBackup() throws {
        let root = dir.appendingPathComponent("New.noindex")
        _ = try Library(root: root)
        XCTAssertEqual(try Database(path: root.appendingPathComponent("Library.sqlite").path).userVersion,
                       Library.schemaVersion)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".bak") })
    }

    /// A launch with any SHOWTOOLS_ setting must name its scratch library.
    func testATestLaunchMustNameItsLibrary() {
        XCTAssertNil(LibraryLocation.testLaunchProblem([:]))
        XCTAssertNil(LibraryLocation.testLaunchProblem(["HOME": "/x"]))
        XCTAssertNil(LibraryLocation.testLaunchProblem(["SHOWTOOLS_LIBRARY": "/tmp/t", "SHOWTOOLS_DEV_SHOW": "1"]))
        XCTAssertNotNil(LibraryLocation.testLaunchProblem(["SHOWTOOLS_DEV_SHOW": "1"]))
        XCTAssertNotNil(LibraryLocation.testLaunchProblem(["SHOWTOOLS_LIBRARY": ""]))
        // A typo in the library's own name is caught too.
        XCTAssertNotNil(LibraryLocation.testLaunchProblem(["SHOWTOOLS_LIBARY": "/tmp/t"]))
    }
}

final class TestLaunchRecordTests: XCTestCase {
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "showtools-tests-\(UUID().uuidString)")
    }

    /// A test copy that quit properly leaves nothing behind.
    func testACleanQuitLeavesNoProblem() {
        let r = TestLaunchRecord(defaults: defaults, isAlive: { _ in false })
        r.begin(pid: 101, library: "/tmp/Scratch.noindex")
        r.end(pid: 101)
        XCTAssertNil(r.crashRelaunchProblem())
    }

    /// A test copy still running is no reason to refuse a plain launch.
    func testARunningTestCopyIsFine() {
        let r = TestLaunchRecord(defaults: defaults, isAlive: { $0 == 101 })
        r.begin(pid: 101, library: "/tmp/Scratch.noindex")
        XCTAssertNil(r.crashRelaunchProblem())
    }

    /// A test copy that crashed: the next plain launch is refused, once.
    func testACrashedTestCopyRefusesOnce() {
        let r = TestLaunchRecord(defaults: defaults, isAlive: { _ in false })
        r.begin(pid: 101, library: "/tmp/Scratch.noindex")
        let problem = r.crashRelaunchProblem()
        XCTAssertNotNil(problem)
        XCTAssertTrue(problem?.contains("/tmp/Scratch.noindex") == true)
        XCTAssertNil(r.crashRelaunchProblem(), "the next deliberate launch opens normally")
    }

    /// Only dead copies' notes are cleared; a running one's stays.
    func testOnlyDeadNotesAreCleared() {
        var alive: Set<Int32> = [102]
        let r = TestLaunchRecord(defaults: defaults, isAlive: { alive.contains($0) })
        r.begin(pid: 101, library: "/tmp/A.noindex")
        r.begin(pid: 102, library: "/tmp/B.noindex")
        XCTAssertNotNil(r.crashRelaunchProblem())
        alive = []                                           // B crashes later
        XCTAssertTrue(r.crashRelaunchProblem()?.contains("/tmp/B.noindex") == true)
    }
}

// MARK: - Undoing collection deletions (Phase 3b)

extension LibraryTests {
    private func insertItem(_ lib: Library, _ name: String) throws -> Int64 {
        let probe = MediaProbe(kind: .image, width: 10, height: 10)
        return try lib.insertItem(relativePath: "\(name).jpg", hash: name, probe: probe, sourcePath: "").id
    }

    func testRemovingFromACollectionCanBePutBackInOrder() throws {
        let lib = try Library(root: dir.appendingPathComponent("U.noindex"))
        let ids = try (1...3).map { i -> Int64 in try insertItem(lib, "\(i)") }
        let c = try lib.createCollection(name: "C")
        for id in ids { try lib.addItems([id], toCollection: c.id); usleep(2000) }
        let removed = try lib.removeItems([ids[0], ids[2]], fromCollection: c.id)
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, [ids[1]])
        try lib.restoreItems(removed.items, toCollection: c.id)
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, ids, "back in the order they were added")
    }

    func testADeletedCollectionComesBackWithItsShowsAndIds() throws {
        let lib = try Library(root: dir.appendingPathComponent("V.noindex"))
        let a = try insertItem(lib, "a"), b = try insertItem(lib, "b")
        let c = try lib.createCollection(name: "Trip")
        var show = try lib.createShow(name: "Beach", collectionID: c.id, itemIDs: [a, b])
        show.markers = [Marker(time: 3)]
        show = try lib.saveShow(show)
        let snap = try XCTUnwrap(lib.snapshotCollection(id: c.id))
        try lib.deleteCollection(id: c.id)
        XCTAssertTrue(try lib.allShows().isEmpty, "its shows went with it")
        try lib.restoreCollection(snap)
        let back = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(back.id, show.id)
        XCTAssertEqual(back.slides.map(\.id), show.slides.map(\.id), "slides keep their ids")
        XCTAssertEqual(back.markers.map(\.time), [3])
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, [a, b])
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.name, "Trip")
    }

    // MARK: - Undoing a show deletion on its own (audit D2)

    func testADeletedShowComesBackWithItsIdAndSlides() throws {
        let lib = try Library(root: dir.appendingPathComponent("W.noindex"))
        let a = try insertItem(lib, "a"), b = try insertItem(lib, "b")
        let c = try lib.createCollection(name: "Trip")
        var show = try lib.createShow(name: "Beach", collectionID: c.id, itemIDs: [a, b])
        show.markers = [Marker(time: 3)]
        show = try lib.saveShow(show)
        let snap = try XCTUnwrap(lib.snapshotShow(id: show.id))
        try lib.deleteShow(id: show.id)
        XCTAssertTrue(try lib.allShows().isEmpty)
        try lib.restoreShow(snap)
        let back = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(back.id, show.id)
        XCTAssertEqual(back.name, "Beach")
        XCTAssertEqual(back.collectionID, c.id)
        XCTAssertEqual(back.slides.map(\.id), show.slides.map(\.id), "slides keep their ids")
        XCTAssertEqual(back.markers.map(\.time), [3])
        // The collection itself, untouched by the show's own delete/restore.
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, [a, b])
    }

    func testARestoredShowLeavesOutSlidesOfFilesDeletedSince() throws {
        let lib = try Library(root: dir.appendingPathComponent("X.noindex"))
        let a = try insertItem(lib, "a"), b = try insertItem(lib, "b")
        let show = try lib.createShow(name: "Beach", itemIDs: [a, b])
        let snap = try XCTUnwrap(lib.snapshotShow(id: show.id))
        try lib.deleteShow(id: show.id)
        _ = try lib.deleteItems([b])
        try lib.restoreShow(snap)
        let back = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(back.slides.map(\.itemID), [a], "b's slide is left out; its file is gone")
    }
}

// MARK: - Groups inside collections (schema 13)

extension LibraryTests {
    func testAVersionTwelveLibraryGetsNoGroups() throws {
        let root = dir.appendingPathComponent("Twelve.noindex")
        do { _ = try Library(root: root) }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE group_items; DROP TABLE groups; PRAGMA user_version = 12;")
        }
        let lib = try Library(root: root)
        XCTAssertEqual(try lib.allGroups(), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library.sqlite.v12.bak").path))
        let c = try lib.allCollections()[0]
        let g = try lib.createGroup(name: "Favourites", collectionID: c.id)
        XCTAssertEqual(try lib.allGroups().map(\.name), ["Favourites"])
        XCTAssertEqual(g.collectionID, c.id)
    }

    /// A group's files must be in its collection (plan): a file not in the
    /// group's collection is silently left out. Groups nest, like folders.
    func testGroupsHoldFilesFromTheirCollectionAndNest() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let a = try insertItem(lib, "a"), b = try insertItem(lib, "b"), outside = try insertItem(lib, "o")
        let c = try lib.createCollection(name: "Wedding")
        try lib.addItems([a, b], toCollection: c.id)

        let cart = try lib.createGroup(name: "Book Cart", collectionID: c.id)
        try lib.addItems([a, b, outside], toGroup: cart.id)
        var g = try XCTUnwrap(lib.allGroups().first { $0.id == cart.id })
        XCTAssertEqual(g.itemIDs, [a, b], "outside was never in the collection, so it's left out of the group too")

        let inner = try lib.createGroup(name: "Best Shots", collectionID: c.id, parentID: cart.id)
        XCTAssertEqual(try lib.allGroups().first { $0.id == inner.id }?.parentID, cart.id)

        try lib.renameGroup(id: cart.id, to: "Book Cart 2026")
        g = try XCTUnwrap(lib.allGroups().first { $0.id == cart.id })
        XCTAssertEqual(g.name, "Book Cart 2026")
    }

    /// Dragging a group onto another nests it there; dragging it out again
    /// (a nil parent) un-nests it to the top.
    func testMovingAGroupNestsItAndCanUnnestIt() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let c = try lib.createCollection(name: "C")
        let a = try lib.createGroup(name: "A", collectionID: c.id)
        let b = try lib.createGroup(name: "B", collectionID: c.id)
        XCTAssertNil(try lib.allGroups().first { $0.id == b.id }?.parentID)

        try lib.moveGroup(id: b.id, toParent: a.id)
        XCTAssertEqual(try lib.allGroups().first { $0.id == b.id }?.parentID, a.id)

        try lib.moveGroup(id: b.id, toParent: nil)
        XCTAssertNil(try lib.allGroups().first { $0.id == b.id }?.parentID, "back to the top")
    }

    /// A group can't be nested inside itself, or inside one of its own
    /// descendants — that would make its own subtree unreachable.
    func testMovingAGroupRefusesACycle() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let c = try lib.createCollection(name: "C")
        let top = try lib.createGroup(name: "Top", collectionID: c.id)
        let child = try lib.createGroup(name: "Child", collectionID: c.id, parentID: top.id)
        let grandchild = try lib.createGroup(name: "Grandchild", collectionID: c.id, parentID: child.id)

        XCTAssertThrowsError(try lib.moveGroup(id: top.id, toParent: top.id), "itself")
        XCTAssertThrowsError(try lib.moveGroup(id: top.id, toParent: child.id), "its own child")
        XCTAssertThrowsError(try lib.moveGroup(id: top.id, toParent: grandchild.id), "its own grandchild")
        // Untouched by the refused moves.
        XCTAssertNil(try lib.allGroups().first { $0.id == top.id }?.parentID)
    }

    /// A group only nests inside one in the same collection — its own
    /// `collection_id` never changes.
    func testMovingAGroupRefusesADifferentCollection() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let c1 = try lib.createCollection(name: "One"), c2 = try lib.createCollection(name: "Two")
        let a = try lib.createGroup(name: "A", collectionID: c1.id)
        let b = try lib.createGroup(name: "B", collectionID: c2.id)
        XCTAssertThrowsError(try lib.moveGroup(id: a.id, toParent: b.id))
        XCTAssertEqual(try lib.allGroups().first { $0.id == a.id }?.collectionID, c1.id, "unmoved")
    }

    func testRemovingFromAGroupCanBePutBackInOrder() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let ids = try (1...3).map { i -> Int64 in try insertItem(lib, "\(i)") }
        let c = try lib.createCollection(name: "C")
        try lib.addItems(ids, toCollection: c.id)
        let g = try lib.createGroup(name: "G", collectionID: c.id)
        for id in ids { try lib.addItems([id], toGroup: g.id); usleep(2000) }

        let removed = try lib.removeItems([ids[0], ids[2]], fromGroup: g.id)
        XCTAssertEqual(try lib.allGroups().first { $0.id == g.id }?.itemIDs, [ids[1]])
        try lib.restoreItems(removed, toGroup: g.id)
        XCTAssertEqual(try lib.allGroups().first { $0.id == g.id }?.itemIDs, ids, "back in the order they were added")
        // The files were never out of the collection.
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, ids)
    }

    /// Taking a file out of a collection takes it out of that collection's
    /// groups too, in the same transaction — and undoing the removal puts
    /// both back.
    func testTakingAFileOutOfACollectionTakesItOutOfItsGroupsToo() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let a = try insertItem(lib, "a"), b = try insertItem(lib, "b")
        let c = try lib.createCollection(name: "C")
        try lib.addItems([a, b], toCollection: c.id)
        let g = try lib.createGroup(name: "G", collectionID: c.id)
        try lib.addItems([a, b], toGroup: g.id)

        let removal = try lib.removeItems([a], fromCollection: c.id)
        XCTAssertEqual(removal.groupMemberships.map(\.itemID), [a])
        XCTAssertEqual(try lib.allGroups().first { $0.id == g.id }?.itemIDs, [b], "a left the group along with the collection")

        try lib.restoreItems(removal.items, toCollection: c.id)
        try lib.restoreGroupMemberships(removal.groupMemberships)
        XCTAssertEqual(try lib.allGroups().first { $0.id == g.id }?.itemIDs, [a, b], "back in both")
    }

    /// Deleting a group that holds groups takes its sub-groups with it, as
    /// in Finder; the files stay in the collection.
    func testDeletingAGroupTakesItsSubgroupsButLeavesFiles() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let a = try insertItem(lib, "a")
        let c = try lib.createCollection(name: "C")
        try lib.addItems([a], toCollection: c.id)
        let top = try lib.createGroup(name: "Top", collectionID: c.id)
        let child = try lib.createGroup(name: "Child", collectionID: c.id, parentID: top.id)
        let grandchild = try lib.createGroup(name: "Grandchild", collectionID: c.id, parentID: child.id)
        try lib.addItems([a], toGroup: grandchild.id)

        try lib.deleteGroup(id: top.id)
        XCTAssertEqual(try lib.allGroups(), [], "the whole subtree is gone")
        XCTAssertEqual(try lib.allCollections().first { $0.id == c.id }?.itemIDs, [a], "the file stayed in the collection")
    }

    /// Undoing that deletion: the whole subtree comes back with its ids and
    /// its files, root first.
    func testADeletedGroupSubtreeComesBackWithIdsAndFiles() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let a = try insertItem(lib, "a")
        let c = try lib.createCollection(name: "C")
        try lib.addItems([a], toCollection: c.id)
        let top = try lib.createGroup(name: "Top", collectionID: c.id)
        let child = try lib.createGroup(name: "Child", collectionID: c.id, parentID: top.id)
        try lib.addItems([a], toGroup: child.id)

        let snap = try lib.snapshotGroupSubtree(id: top.id)
        XCTAssertEqual(snap.map(\.id), [top.id, child.id], "root first")
        try lib.deleteGroup(id: top.id)
        try lib.restoreGroupSubtree(snap)

        let groups = try lib.allGroups()
        XCTAssertEqual(Set(groups.map(\.id)), [top.id, child.id])
        XCTAssertEqual(groups.first { $0.id == child.id }?.parentID, top.id)
        XCTAssertEqual(groups.first { $0.id == child.id }?.itemIDs, [a])
    }

    /// Deleting a collection takes its groups with it, and undoing that
    /// brings them back too, alongside its files and shows.
    func testADeletedCollectionComesBackWithItsGroups() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let a = try insertItem(lib, "a")
        let c = try lib.createCollection(name: "Trip")
        try lib.addItems([a], toCollection: c.id)
        let g = try lib.createGroup(name: "Best Of", collectionID: c.id)
        try lib.addItems([a], toGroup: g.id)

        let snap = try XCTUnwrap(lib.snapshotCollection(id: c.id))
        try lib.deleteCollection(id: c.id)
        XCTAssertEqual(try lib.allGroups(), [], "its groups went with it")

        try lib.restoreCollection(snap)
        let back = try XCTUnwrap(lib.allGroups().first { $0.id == g.id })
        XCTAssertEqual(back.name, "Best Of")
        XCTAssertEqual(back.itemIDs, [a])
    }
}
