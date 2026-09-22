import XCTest
import AVFoundation
@testable import ShowToolsCore

final class MusicTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("showtools-music-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Two seconds, stereo: a loud tone for the first second, silence after.
    func writeSong(_ name: String = "song.wav") throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for c in 0..<2 {
            for i in 0..<88_200 {
                buffer.floatChannelData![c][i] = i < 44_100 ? 0.8 * sin(Float(i) * 0.05) : 0
            }
        }
        try file.write(from: buffer)
        return url
    }

    func testASongProbesAsAudioWithItsLength() async throws {
        let url = try writeSong()
        XCTAssertTrue(Ingest.isMedia(url))
        let read = await MediaProbe.read(url)
        let probe = try XCTUnwrap(read)
        XCTAssertEqual(probe.kind, .audio)
        XCTAssertFalse(probe.kind.isPicture)
        XCTAssertEqual(probe.duration ?? 0, 2, accuracy: 0.01)
    }

    func testWaveformIsLoudThenSilentAndCaches() throws {
        let url = try writeSong()
        let cache = dir.appendingPathComponent("Cache")
        let w = try Waveform.load(url, hash: "abc", cacheDir: cache)
        XCTAssertEqual(w.duration, 2, accuracy: 0.02)
        XCTAssertGreaterThan(w.peak(from: 0.2, to: 0.8), 0.7)
        XCTAssertEqual(w.peak(from: 1.2, to: 1.8), 0)
        // Read back from the cache, not the file.
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try Waveform.load(url, hash: "abc", cacheDir: cache), w)
    }

    func testSegmentsPlayWhatsLeftOfAClip() throws {
        var clip = AudioClip(itemID: 1, start: 10, length: 30)
        clip.inPoint = 5
        // Before it: starts later, from its in point.
        let a = try XCTUnwrap(clip.segment(from: 4, until: 100))
        XCTAssertEqual(a.delay, 6, accuracy: 1e-9)
        XCTAssertEqual(a.fileStart, 5, accuracy: 1e-9)
        XCTAssertEqual(a.duration, 30, accuracy: 1e-9)
        // Partway in: now, from further into the file, cut at the show's end.
        let b = try XCTUnwrap(clip.segment(from: 20, until: 25))
        XCTAssertEqual(b.delay, 0, accuracy: 1e-9)
        XCTAssertEqual(b.fileStart, 15, accuracy: 1e-9)
        XCTAssertEqual(b.duration, 5, accuracy: 1e-9)
        // Over, or past the show's end.
        XCTAssertNil(clip.segment(from: 40, until: 100))
        XCTAssertNil(clip.segment(from: 0, until: 10))
    }

    func testEnvelopeRampsOverItsFades() {
        var c = AudioClip(itemID: 1, start: 10, length: 10)
        c.volume = 0.8; c.fadeIn = 2; c.fadeOut = 4
        XCTAssertEqual(c.envelope(at: 9.99), 0)
        XCTAssertEqual(c.envelope(at: 11), 0.4, accuracy: 1e-9)      // halfway in
        XCTAssertEqual(c.envelope(at: 14), 0.8, accuracy: 1e-9)
        XCTAssertEqual(c.envelope(at: 19), 0.2, accuracy: 1e-9)      // a quarter of the way out
        XCTAssertEqual(c.envelope(at: 20), 0)
    }

    func testOverlappingSongsCrossfadeAtEqualPower() {
        let a = AudioClip(itemID: 1, start: 0, length: 10)
        let b = AudioClip(itemID: 2, start: 8, length: 10)
        let all = [a, b]
        XCTAssertEqual(AudioClip.crossfade(earlier: a, later: b), 8...10)
        XCTAssertNil(AudioClip.crossfade(earlier: b, later: a))
        // Before and after the overlap, each is at its own level.
        XCTAssertEqual(AudioClip.gain(of: a, at: 7, among: all), 1, accuracy: 1e-9)
        XCTAssertEqual(AudioClip.gain(of: b, at: 11, among: all), 1, accuracy: 1e-9)
        // Halfway through, both at √½: the power adds back to one.
        let ga = AudioClip.gain(of: a, at: 9, among: all), gb = AudioClip.gain(of: b, at: 9, among: all)
        XCTAssertEqual(ga, sqrt(0.5), accuracy: 1e-9)
        XCTAssertEqual(ga * ga + gb * gb, 1, accuracy: 1e-9)
        // A song wholly inside another doesn't crossfade; both overlaps draw.
        let inner = AudioClip(itemID: 3, start: 2, length: 3)
        XCTAssertEqual(AudioClip.gain(of: a, at: 3, among: [a, inner]), 1, accuracy: 1e-9)
        XCTAssertEqual(AudioClip.overlaps([a, b, inner]), [8...10, 2...5])
    }

    func testSongsRoundTripAndOneBadClipDoesNotCostTheOthers() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        let song = try lib.insertItem(relativePath: "s.wav", hash: "s",
                                      probe: MediaProbe(kind: .audio, width: 0, height: 0, duration: 200),
                                      sourcePath: "")
        XCTAssertEqual(try lib.allItems()[0].kind, .audio)
        var show = try lib.createShow(name: "Music")
        XCTAssertEqual(show.music, [])
        var clip = AudioClip(itemID: song.id, start: 3, length: 120)
        clip.volume = 0.5; clip.inPoint = 12
        show.music = [clip]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].music, [clip])

        let json = #"[{"itemID":1,"start":0,"length":5},{"itemID":"x"},{"itemID":2,"start":5,"length":3,"volume":0.25}]"#
        let clips = AudioClip.decodeList(json)
        XCTAssertEqual(clips.map(\.itemID), [1, 2])
        XCTAssertEqual(clips[1].volume, 0.25)
    }

    func testMarkersRoundTripAndSnapToTheNearestWithinReach() throws {
        let lib = try Library(root: dir.appendingPathComponent("Lib"))
        var show = try lib.createShow(name: "Marks")
        XCTAssertEqual(show.markers, [])
        show.markers = [Marker(time: 1.5), Marker(time: 4)]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].markers, show.markers)
        XCTAssertEqual(Marker.decodeList(#"[{"time":2},{"id":"x"},{"time":3}]"#).map(\.time), [2, 3])

        XCTAssertEqual(Snap.nearest(4.08, in: [1.5, 4, 4.2], within: 0.1), 4)
        XCTAssertEqual(Snap.nearest(4.15, in: [1.5, 4, 4.2], within: 0.1), 4.2)
        XCTAssertNil(Snap.nearest(3, in: [1.5, 4], within: 0.1))
    }

    func testEditorStateRoundTripsAndAVersionNineLibraryGetsTheDefaults() throws {
        let root = dir.appendingPathComponent("Nine.noindex")
        do { _ = try Library(root: root).createShow(name: "Old") }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE rhythm_patterns; ALTER TABLE shows DROP COLUMN editor; PRAGMA user_version = 9;")
        }
        let lib = try Library(root: root)
        var show = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(show.editor, ShowEditorState())
        show.editor.rangeIn = 2; show.editor.rangeOut = 5; show.editor.loopPlayback = true
        show.editor.markerLines = false; show.editor.rangeOutLine = false
        var m = Marker(time: 3); m.showsLine = false
        show.markers = [m]
        try lib.saveShow(show)
        let back = try lib.allShows()[0]
        XCTAssertEqual(back.editor, show.editor)
        XCTAssertEqual(back.markers, [m])
        // One bad field falls back alone.
        let e = try JSONDecoder().decode(ShowEditorState.self, from: Data(#"{"rangeIn":1,"loopPlayback":"x"}"#.utf8))
        XCTAssertEqual(e.rangeIn, 1)
        XCTAssertFalse(e.loopPlayback)
    }

    func testAVersionEightLibraryGetsNoMarkers() throws {
        let root = dir.appendingPathComponent("Eight.noindex")
        do { _ = try Library(root: root).createShow(name: "Old") }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE rhythm_patterns; ALTER TABLE shows DROP COLUMN editor; ALTER TABLE shows DROP COLUMN markers; PRAGMA user_version = 8;")
        }
        let lib = try Library(root: root)
        var show = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(show.markers, [])
        show.markers = [Marker(time: 2)]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].markers.map(\.time), [2])
    }

    func testAVersionSevenLibraryGetsNoMusic() throws {
        let root = dir.appendingPathComponent("Seven.noindex")
        do { _ = try Library(root: root).createShow(name: "Old") }
        do {
            let db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
            try db.exec("DROP TABLE rhythm_patterns; ALTER TABLE shows DROP COLUMN editor; ALTER TABLE shows DROP COLUMN markers; ALTER TABLE shows DROP COLUMN music; PRAGMA user_version = 7;")
        }
        let lib = try Library(root: root)
        var show = try XCTUnwrap(lib.allShows().first)
        XCTAssertEqual(show.music, [])
        show.music = [AudioClip(itemID: 1, start: 0, length: 5)]
        try lib.saveShow(show)
        XCTAssertEqual(try lib.allShows()[0].music.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library.sqlite.v7.bak").path))
    }
}
