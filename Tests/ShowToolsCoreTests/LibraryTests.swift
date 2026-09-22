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

    /// The small value types inside the settings fall back field by field
    /// too, so a field added later can't cost a saved Ken Burns move, pivot
    /// or background.
    func testSmallValueTypesDecodeFieldByField() throws {
        let kb = try JSONDecoder().decode(KenBurns.self, from: Data(
            #"{"start":{"x":0.2,"y":0.3,"zoom":1.5},"end":{"x":0.7,"zoom":"bad"}}"#.utf8))
        XCTAssertEqual(kb.start, KenBurnsFrame(x: 0.2, y: 0.3, zoom: 1.5))
        XCTAssertEqual(kb.end, KenBurnsFrame(x: 0.7, y: 0.5, zoom: 1))

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
