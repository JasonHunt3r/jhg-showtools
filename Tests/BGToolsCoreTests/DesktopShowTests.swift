import XCTest
import ShowToolsCore
@testable import BGToolsCore

/// A seeded generator, so shuffles are repeatable.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class DesktopShowTests: XCTestCase {
    func item(_ id: Int64, _ kind: MediaKind) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id)", hash: "\(id)", kind: kind, pixelWidth: 10, pixelHeight: 10,
                  duration: kind == .video || kind == .audio ? 3 : nil, ingestedAt: Date(), sourcePath: "")
    }

    /// 1–3 stills, 4 a video, 5 a GIF, 6 a song. Show 10 uses 1–5 with
    /// music; collection 20 holds 2, 4 and 6.
    lazy var lib: DesktopShow.Library = {
        let items = [item(1, .image), item(2, .image), item(3, .image), item(4, .video),
                     item(5, .animatedImage), item(6, .audio)]
        var show = Show(id: 10, name: "Beach", slides: (1...5).map { Slide(id: 100 + $0, itemID: $0) })
        show.defaults.loop = false
        show.defaults.length = 3
        show.music = [AudioClip(itemID: 6, start: 0, length: 3)]
        show.editor.loopPlayback = true
        let other = Show(id: 11, name: "Empty")
        return DesktopShow.Library(shows: [show, other],
                                   collections: [MediaCollection(id: 20, name: "Picks", itemIDs: [2, 4, 6])],
                                   items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
    }()

    func build(_ mode: PlayMode, stills: Bool = false, sound: Bool = false, seed: UInt64 = 1) -> DesktopShow.Built? {
        var rng = Seeded(state: seed)
        return DesktopShow.build(ScreenSetting(library: "/l", mode: mode, stillsOnly: stills, sound: sound),
                                 from: lib, randomDefaults: DesktopSettings.startingRandomDefaults, rng: &rng)
    }

    func testAShowPlaysInOrderLoopingAndSilent() throws {
        let b = try XCTUnwrap(build(.show(10)))
        XCTAssertEqual(b.show.id, DesktopShow.id)
        XCTAssertEqual(b.sourceShowID, 10)
        XCTAssertEqual(b.show.slides.map(\.itemID), [1, 2, 3, 4, 5])
        XCTAssertTrue(b.show.defaults.loop)
        XCTAssertEqual(b.show.defaults.length, 3, "a show keeps its own defaults")
        XCTAssertTrue(b.show.music.isEmpty)
        XCTAssertFalse(b.show.editor.loopPlayback)
        XCTAssertEqual(build(.show(10), sound: true)?.show.music.count, 1)
    }

    func testStillsOnlySkipsVideoAndGIFs() {
        XCTAssertEqual(build(.show(10), stills: true)?.show.slides.map(\.itemID), [1, 2, 3])
        XCTAssertEqual(build(.collection(20), stills: true)?.show.slides.map(\.itemID), [2])
    }

    func testShuffledKeepsEachSlideAndItsSettings() throws {
        let b = try XCTUnwrap(build(.shuffled(10), seed: 7))
        XCTAssertEqual(Set(b.show.slides.map(\.id)), Set(101...105))
        XCTAssertNotEqual(b.show.slides.map(\.itemID), [1, 2, 3, 4, 5], "seed 7 reorders")
    }

    func testRandomModesUseTheDesktopDefaultsAndNeverSongs() throws {
        let c = try XCTUnwrap(build(.collection(20)))
        XCTAssertEqual(Set(c.show.slides.map(\.itemID)), [2, 4])
        XCTAssertNil(c.sourceShowID)
        XCTAssertEqual(c.show.defaults.length, 8)
        XCTAssertEqual(c.show.defaults.panAndZoom, .off)
        XCTAssertEqual(c.show.slides.map(\.id), c.show.slides.map(\.itemID), "slide id = item id: steady Pan and Zoom")
        let all = try XCTUnwrap(build(.allFiles))
        XCTAssertEqual(Set(all.show.slides.map(\.itemID)), [1, 2, 3, 4, 5])
    }

    func testRandomShowSkipsShowsWithNothingToPlay() {
        for seed in 1...20 { XCTAssertEqual(build(.randomShow, seed: UInt64(seed))?.sourceShowID, 10) }
    }

    func testNothingToPlayIsNil() {
        XCTAssertNil(build(.show(99)))
        XCTAssertNil(build(.show(11)))
        XCTAssertNil(build(.collection(99)))
    }

    func testRefreshKeepsAShuffledOrderAndTakesNewSettings() throws {
        let setting = ScreenSetting(library: "/l", mode: .shuffled(10))
        var rng = Seeded(state: 7)
        let first = try XCTUnwrap(DesktopShow.build(setting, from: lib, randomDefaults: ShowDefaults(), rng: &rng))
        var edited = lib
        edited.shows[0].slides.remove(at: 0)                                   // slide 101 deleted
        edited.shows[0].slides[0].settings.length = .seconds(9)               // 102 lengthened
        edited.shows[0].slides.append(Slide(id: 106, itemID: 1))              // a new one
        let after = try XCTUnwrap(DesktopShow.refresh(first, setting, from: edited))
        let kept = first.show.slides.map(\.id).filter { $0 != 101 }
        XCTAssertEqual(after.show.slides.map(\.id), kept + [106])
        XCTAssertEqual(after.show.slides.first { $0.id == 102 }?.settings.length, .seconds(9))
    }

    func testRefreshOfRandomPicturesDropsOnlyWhatsGone() throws {
        let setting = ScreenSetting(library: "/l", mode: .allFiles)
        let first = try XCTUnwrap(build(.allFiles))
        var edited = lib
        edited.items[3] = nil
        let after = try XCTUnwrap(DesktopShow.refresh(first, setting, from: edited))
        XCTAssertEqual(after.show.slides.map(\.itemID), first.show.slides.map(\.itemID).filter { $0 != 3 })
    }
}

final class DesktopSettingsTests: XCTestCase {
    func testWhatAScreenPlays() {
        var s = DesktopSettings()
        let a = ScreenSetting(library: "/a", mode: .allFiles)
        let b = ScreenSetting(library: "/b", mode: .show(1))
        let n = ScreenSetting(library: "/n", mode: .randomShow)
        XCTAssertNil(s.setting(for: "x"))
        s.newScreens = n
        s.screens["x"] = a
        XCTAssertEqual(s.setting(for: "x"), a)
        XCTAssertEqual(s.setting(for: "never seen"), n)
        s.allSame = true
        s.allSameSetting = b
        XCTAssertEqual(s.setting(for: "x"), b)
        s.allSame = false
        XCTAssertEqual(s.setting(for: "x"), a, "a screen's own setting is kept under Synchronize")
    }

    func testScreenIDsNameTheFirstDesktop() {
        XCTAssertEqual(DesktopSettings.screenID(display: "D", space: ""), "D/desktop1")
        XCTAssertEqual(DesktopSettings.screenID(display: "D", space: "U"), "D/U")
    }

    func testRoundTripAndLenientReading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bg-\(UUID().uuidString)/s.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DesktopSettingsStore(url: url)
        XCTAssertEqual(store.load(), DesktopSettings(), "missing file: empty settings")
        var s = DesktopSettings()
        s.screens["D/desktop1"] = ScreenSetting(library: "/l", mode: .collection(3), stillsOnly: true)
        s.allSame = true
        try store.save(s)
        XCTAssertEqual(store.load(), s)
        // A value this version can't read loses only itself.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["randomDefaults"] = "nonsense"
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let back = store.load()
        XCTAssertEqual(back.screens, s.screens)
        XCTAssertTrue(back.allSame)
        XCTAssertEqual(back.randomDefaults, DesktopSettings.startingRandomDefaults)
    }

    func testTestsCanPointAtTheirOwnFile() {
        XCTAssertEqual(DesktopSettingsStore.standard(environment: ["BGTOOLS_SETTINGS": "/tmp/x.json"]).url.path, "/tmp/x.json")
    }

    /// Naming screens (bgtools.md): a display's and a Space's own names
    /// round-trip, and a settings file from before they existed (the
    /// older-version trap) reads as no names at all, not a decode failure.
    func testDisplayAndSpaceNamesRoundTripAndDefaultEmpty() throws {
        var s = DesktopSettings()
        s.displayNames["D"] = "Work Monitor"
        s.spaceNames["D/desktop1"] = "Rhythm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bg-\(UUID().uuidString)/s.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DesktopSettingsStore(url: url)
        try store.save(s)
        XCTAssertEqual(store.load(), s)

        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["displayNames"] = nil
        json["spaceNames"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let older = store.load()
        XCTAssertEqual(older.displayNames, [:])
        XCTAssertEqual(older.spaceNames, [:])
        XCTAssertTrue(older.allSame == s.allSame, "the rest of the file still reads fine")
    }
}
