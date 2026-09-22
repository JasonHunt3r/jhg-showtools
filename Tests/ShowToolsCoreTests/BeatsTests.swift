import XCTest
@testable import ShowToolsCore

final class BeatsTests: XCTestCase {
    /// 120 BPM, 4/4: a beat every 0.5 s from 1.0, a bar every 2 s.
    let r = SongRhythm(beats: stride(from: 1.0, through: 20, by: 0.5).map { $0 },
                       bars: stride(from: 1.0, through: 20, by: 2).map { $0 }, beatsPerMinute: 120,
                       sections: [.init(start: 1, end: 9), .init(start: 9, end: 20)])

    func testEveryNBeatsCountsFromTheFirstBarStart() {
        // From 1.6: the first beat is 2.0, but the first bar start is 3.0.
        XCTAssertEqual(BeatPlan(mode: .beats(2)).markers(r, from: 1.6, to: 6), [3, 4, 5, 6])
        XCTAssertEqual(BeatPlan(mode: .beats(4)).markers(r, from: 0, to: 9), [1, 3, 5, 7, 9])
    }

    func testEveryNBarsAndBarStartsHere() {
        XCTAssertEqual(BeatPlan(mode: .bars(2)).markers(r, from: 0, to: 12), [1, 5, 9])
        // Beat 1 moved one beat later.
        XCTAssertEqual(BeatPlan(mode: .bars(1), barShift: 1).markers(r, from: 0, to: 6), [1.5, 3.5, 5.5])
    }

    func testTempoCorrections() {
        XCTAssertEqual(r.beats(.double).prefix(3), [1, 1.25, 1.5])
        // Every other beat, keeping the bar starts.
        XCTAssertEqual(r.beats(.half).prefix(3), [1, 2, 3])
        XCTAssertEqual(BeatPlan(mode: .beats(1), tempo: .half).markers(r, from: 0, to: 4), [1, 2, 3, 4])
    }

    func testTempoCorrectionsMoveTheBarsToo() {
        // Heard at half speed: each detected bar was two, so ×2 halves them.
        XCTAssertEqual(BeatPlan(mode: .bars(1), tempo: .double).markers(r, from: 0, to: 6), [1, 2, 3, 4, 5, 6])
        // Heard at double speed: every other bar start, from the first.
        XCTAssertEqual(BeatPlan(mode: .bars(1), tempo: .half).markers(r, from: 0, to: 12), [1, 5, 9])
        // "Bar starts here" counts corrected beats: one ÷2 beat is 1 s.
        XCTAssertEqual(BeatPlan(mode: .bars(1), tempo: .half, barShift: 1).markers(r, from: 0, to: 12), [2, 6, 10])
    }

    func testAboutEverySecondsLandsOnBeats() {
        // Every 1.3 s from the first beat: 1, 2.3→2.5, 3.6→3.5, 4.9→5.
        XCTAssertEqual(BeatPlan(mode: .seconds(1.3)).markers(r, from: 0, to: 5), [1, 2.5, 3.5, 5])
    }

    func testRhythmDecodesFieldByField() throws {
        let back = try JSONDecoder().decode(SongRhythm.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        let partial = try JSONDecoder().decode(SongRhythm.self, from: Data(#"{"beats":[2,1],"bars":"x"}"#.utf8))
        XCTAssertEqual(partial.beats, [1, 2])
        XCTAssertEqual(partial.bars, [])
    }

    // MARK: Applying

    func show(_ lengths: [Double]) -> (Show, [Int64: MediaItem]) {
        var items: [Int64: MediaItem] = [:]
        let slides = lengths.enumerated().map { i, l -> Slide in
            items[Int64(i + 1)] = MediaItem(id: Int64(i + 1), relativePath: "\(i).jpg", hash: "h\(i)", kind: .image,
                                            pixelWidth: 10, pixelHeight: 10, duration: nil, ingestedAt: Date(), sourcePath: "")
            return Slide(id: Int64(i + 1), itemID: Int64(i + 1), settings: SlideSettings(length: .seconds(l)))
        }
        items[99] = MediaItem(id: 99, relativePath: "s.m4a", hash: "s", kind: .audio, pixelWidth: 0, pixelHeight: 0,
                              duration: 30, ingestedAt: Date(), sourcePath: "")
        var d = ShowDefaults(); d.loop = false
        return (Show(id: 1, name: "t", defaults: d, slides: slides), items)
    }

    func testApplyingMarksTheSongInItsOwnTimeAndReplacesOnlyItsDetectedMarkers() {
        var (s, items) = show([5, 5, 5])
        // The song sits at show time 2, starting 1 s into the file.
        var clip = AudioClip(itemID: 99, start: 2, length: 20)
        clip.inPoint = 1
        clip.markers = [Marker(time: 4), Marker(time: 18)]           // old detected ones
        s.music = [clip]
        s.markers = [Marker(time: 3.3)]                              // a hand marker
        let t = ShowTimeline(show: s, items: items)
        let out = BeatDetection.apply(BeatPlan(mode: .bars(1)), to: s, timeline: t, rhythms: [99: r],
                                      in: 2...8, fitSlides: false)
        // Show 2…8 is song 1…7: bars at 1, 3, 5, 7 → show 2, 4, 6, 8.
        XCTAssertEqual(out.detectedMarkers.map(\.time), [2, 4, 6, 8, 19])
        XCTAssertEqual(out.music[0].markers.map(\.time), [1, 3, 5, 7, 18], "song time; the one outside the range stays")
        XCTAssertEqual(out.markers, s.markers, "hand markers untouched")
    }

    func testFittingSlidesPutsEachCutOnTheNextMarker() {
        let (s, items) = show([5, 5, 5, 5])                          // cuts at 5, 10, 15
        let t = ShowTimeline(show: s, items: items)
        // The range starts inside slide 0 (0…5), so it's the first re-cut.
        let out = SlideFitting.fit(s, timeline: t, markers: [2, 2.2, 4, 6, 9], in: 1...9)
        let lengths: [Double] = out.slides.map { s in
            if case .seconds(let x) = s.settings.length { return x }
            return -1
        }
        // 2 (from 0), 2.2 is too close (0.2 < 0.5) and skipped, then 2, 2, 3; the last slide keeps 5.
        XCTAssertEqual(lengths, [2, 2, 2, 3])
        XCTAssertEqual(ShowTimeline(show: out, items: items).slides.map(\.start), [0, 2, 4, 6])
    }

    func testDetectedMarkersHideWhenTrimmedPastAndSurviveARoundTrip() throws {
        var clip = AudioClip(itemID: 1, start: 10, length: 5)
        clip.inPoint = 2
        clip.markers = [Marker(time: 1), Marker(time: 3), Marker(time: 8)]
        XCTAssertEqual(clip.visibleMarkers.map(\.time), [11], "only song 3 is inside song 2…7")
        let back = try JSONDecoder().decode(AudioClip.self, from: JSONEncoder().encode(clip))
        XCTAssertEqual(back.markers, clip.markers)
        let json = #"{"itemID":1,"start":0,"length":5,"markers":[{"time":1},{"bad":true},{"time":2}]}"#
        XCTAssertEqual(try JSONDecoder().decode(AudioClip.self, from: Data(json.utf8)).markers.map(\.time), [1, 2])
    }
}
