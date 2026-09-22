import XCTest
@testable import ShowToolsCore

final class RhythmTests: XCTestCase {
    typealias P = RhythmPattern

    // MARK: Letters

    func testReadsValuesDotsTripletsAndRests() {
        let (p, bad) = P.parse("w h. q rq 3e 3e 3e s r3e")
        XCTAssertEqual(bad, [])
        XCTAssertEqual(p.notes, [
            .init(.whole), .init(.half, dotted: true), .init(.quarter), .init(.quarter, rest: true),
            .init(.eighth, triplet: true), .init(.eighth, triplet: true), .init(.eighth, triplet: true),
            .init(.sixteenth), .init(.eighth, triplet: true, rest: true),
        ])
        XCTAssertEqual(p.text, "w h. q rq 3e 3e 3e s r3e")
    }

    func testSpacesAreOptionalAndCaseDoesntMatter() {
        XCTAssertEqual(P(text: "QQh.rE"), P(text: "q q h. re"))
        XCTAssertEqual(P(text: "qqh.re").text, "q q h. re")
    }

    func testLengths() {
        XCTAssertEqual(P(text: "h.").quarters, 3)
        XCTAssertEqual(P(text: "3e 3e 3e").quarters, 1, accuracy: 1e-9)   // a triplet fills a quarter
        XCTAssertEqual(P(text: "w h q e s").quarters, 7.75)
        XCTAssertEqual(P(text: "rq q").quarters, 2, "a rest takes its time")
    }

    func testUnreadableLettersAreSkippedAndReported() {
        let (p, bad) = P.parse("q x h 3 r")
        XCTAssertEqual(p.text, "q h")
        XCTAssertEqual(bad, [2, 6, 8], "x, the lone 3, and the lone r")
    }

    func testSavedAsItsText() throws {
        let p = P(text: "h q q rq")
        let data = try JSONEncoder().encode(["p": p])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"p":"h q q rq"}"#)
        XCTAssertEqual(try JSONDecoder().decode([String: P].self, from: data)["p"], p)
        XCTAssertEqual(try JSONDecoder().decode([String: P].self, from: Data(#"{"p":7}"#.utf8))["p"], P(),
                       "an unreadable save is an empty pattern, not an error")
    }

    // MARK: Placing

    func testEvenPulseRepeatsAndStopsAtTheEnd() {
        // 120 BPM, a quarter = 1 beat (0.5 s): h q q is 1 s, 0.5 s, 0.5 s.
        let m = RhythmPlacement.markers(P(text: "h q q"), beatsPerQuarter: 1, pulse: .even(beatsPerMinute: 120),
                                        from: 10, to: 14)
        XCTAssertEqual(m, [10, 11, 11.5, 12, 13, 13.5, 14])
    }

    func testRestsTakeTimeButPlaceNothing() {
        let m = RhythmPlacement.markers(P(text: "q rq"), beatsPerQuarter: 1, pulse: .even(beatsPerMinute: 60),
                                        from: 0, to: 5)
        XCTAssertEqual(m, [0, 2, 4])
    }

    func testNoteLengthSetting() {
        // A quarter = one 4-beat bar: at 120 BPM, a change every 2 s.
        let m = RhythmPlacement.markers(P(text: "q"), beatsPerQuarter: 4, pulse: .even(beatsPerMinute: 120),
                                        from: 0, to: 7)
        XCTAssertEqual(m, [0, 2, 4, 6])
    }

    func testTripletsLandInThirds() {
        let m = RhythmPlacement.markers(P(text: "3e 3e 3e"), beatsPerQuarter: 3, pulse: .even(beatsPerMinute: 60),
                                        from: 0, to: 3)
        XCTAssertEqual(m, [0, 1, 2, 3])
    }

    func testDetectedBeatsAreFollowedEvenWhenTheyDrift() {
        // Beats slowing down: gaps of 0.5, 0.6, 0.7, 0.8.
        let beats: [Double] = [1, 1.5, 2.1, 2.8, 3.6]
        // Starts on the first beat at or after the start (1.2 → 1.5).
        let q = RhythmPlacement.markers(P(text: "q"), beatsPerQuarter: 1, pulse: .beats(beats), from: 1.2, to: 10)
        XCTAssertEqual(q, [1.5, 2.1, 2.8, 3.6], "stops where the beats do")
        // An eighth on beat 2.5 of 1.5…: halfway between 2.1 and 2.8.
        let e = RhythmPlacement.markers(P(text: "q q e"), beatsPerQuarter: 1, pulse: .beats(beats), from: 1.5, to: 10)
        XCTAssertEqual(e, [1.5, 2.1, 2.8, 3.2])
    }

    func testASongsBeatsInShowTime() {
        let r = SongRhythm(beats: stride(from: 0.0, through: 20, by: 0.5).map { $0 }, bars: [0, 2, 4])
        var clip = AudioClip(itemID: 1, start: 10, length: 4)
        clip.inPoint = 1
        guard case .beats(let b) = RhythmPulse.song(clip, r) else { return XCTFail() }
        XCTAssertEqual(b.first, 10)
        XCTAssertEqual(b.last, 14, "only the beats inside the clip (song 1…5)")
        guard case .beats(let d) = RhythmPulse.song(clip, r, tempo: .double) else { return XCTFail() }
        XCTAssertEqual(d.count, 17)
    }

    func testNothingToPlace() {
        let even = RhythmPulse.even(beatsPerMinute: 120)
        XCTAssertEqual(RhythmPlacement.markers(P(), beatsPerQuarter: 1, pulse: even, from: 0, to: 9), [])
        XCTAssertEqual(RhythmPlacement.markers(P(text: "rq rh"), beatsPerQuarter: 1, pulse: even, from: 0, to: 9), [],
                       "all rests")
        XCTAssertEqual(RhythmPlacement.markers(P(text: "q"), beatsPerQuarter: 0, pulse: even, from: 0, to: 9), [])
        XCTAssertEqual(RhythmPlacement.markers(P(text: "q"), beatsPerQuarter: 1, pulse: .beats([]), from: 0, to: 9), [])
    }

    // MARK: Applying

    func testApplyAddsHandMarkersOnceAndFitsSlides() {
        var items: [Int64: MediaItem] = [:]
        let slides = (0..<4).map { i -> Slide in
            items[Int64(i + 1)] = MediaItem(id: Int64(i + 1), relativePath: "\(i).jpg", hash: "h\(i)", kind: .image,
                                            pixelWidth: 10, pixelHeight: 10, duration: nil, ingestedAt: Date(), sourcePath: "")
            return Slide(id: Int64(i + 1), itemID: Int64(i + 1), settings: SlideSettings(length: .seconds(5)))
        }
        var d = ShowDefaults(); d.loop = false
        var s = Show(id: 1, name: "t", defaults: d, slides: slides)
        s.markers = [Marker(time: 4)]
        let t = ShowTimeline(show: s, items: items)
        let times = RhythmPlacement.markers(P(text: "h q q"), beatsPerQuarter: 1, pulse: .even(beatsPerMinute: 60),
                                            from: 0, to: 8)
        XCTAssertEqual(times, [0, 2, 3, 4, 6, 7, 8])
        let out = RhythmApply.apply(times, to: s, timeline: t, in: 0...8, fitSlides: true)
        XCTAssertEqual(out.markers.map(\.time), [0, 2, 3, 4, 6, 7, 8], "the one already at 4 isn't doubled")
        // Slide 0 starts at 0, so the marker at 0 can't be a cut; then 2, 3, 4, 6.
        XCTAssertEqual(ShowTimeline(show: out, items: items).slides.map(\.start), [0, 2, 3, 4])
        XCTAssertEqual(RhythmApply.apply(times, to: s, timeline: t, in: 0...8, fitSlides: false).slides, s.slides)
    }
}
