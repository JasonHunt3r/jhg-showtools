import XCTest
@testable import ShowToolsCore

final class RangeFillTests: XCTestCase {

    func item(_ id: Int64, kind: MediaKind = .image, duration: Double? = nil) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: kind,
                  pixelWidth: 4000, pixelHeight: 3000, duration: duration,
                  ingestedAt: Date(), sourcePath: "")
    }

    /// Three 4 s slides, ids 1…3, items 1…3 (each a still), no transitions
    /// (cut), for arithmetic that doesn't have to account for overlap.
    func show(_ lengths: [Double] = [4, 4, 4]) -> (Show, [Int64: MediaItem]) {
        var d = ShowDefaults()
        d.transition = Transition(style: .cut, duration: 0)
        let slides = lengths.enumerated().map { i, l in
            Slide(id: Int64(i + 1), itemID: Int64(i + 1), settings: SlideSettings(length: .seconds(l)))
        }
        let items = Dictionary(uniqueKeysWithValues: slides.map { ($0.itemID, item($0.itemID)) })
        return (Show(id: 1, name: "t", defaults: d, slides: slides), items)
    }

    // MARK: Boundaries and lengths

    func testEvenSplitsTheRangeExactly() {
        let (s, _) = show()
        let lengths = RangeFill.lengths(itemCount: 3, timing: .even, show: s, rhythms: [:], in: 2...11)
        XCTAssertEqual(lengths, [3, 3, 3])
    }

    func testEvenWithOneImageIsTheWholeRange() {
        let (s, _) = show()
        XCTAssertEqual(RangeFill.lengths(itemCount: 1, timing: .even, show: s, rhythms: [:], in: 2...11), [9])
    }

    func testRhythmWithNoSongFallsBackToEven() {
        // Beats/bars/seconds/pattern all need a song's rhythm to quantize
        // onto; with none under the range, nothing but the fallback split.
        let (s, _) = show()
        let lengths = RangeFill.lengths(itemCount: 4, timing: .rhythm(BeatPlan(mode: .seconds(1))),
                                        show: s, rhythms: [:], in: 0...8)
        XCTAssertEqual(lengths, [2, 2, 2, 2])
    }

    func testRhythmQuantizesOntoDetectedBeats() {
        var (s, items) = show()
        items[9] = item(9, kind: .audio, duration: 20)
        s.music = [AudioClip(itemID: 9, start: 0, length: 20)]
        // A beat every 0.5 s from 1.0: at 1, 1.5, 2, 2.5, 3, 3.5, 4...
        let r = SongRhythm(beats: stride(from: 1.0, through: 20, by: 0.5).map { $0 },
                           bars: stride(from: 1.0, through: 20, by: 2).map { $0 })
        // 4 images over 1...4: 3 interior cuts wanted, every beat lands one.
        let lengths = RangeFill.lengths(itemCount: 4, timing: .rhythm(BeatPlan(mode: .beats(2))),
                                        show: s, rhythms: [9: r], in: 1...4)
        // Every-2-beats from beat 1: 1, 2, 3, 4 — cuts at 2 and 3 (interior),
        // one more needed and there's no third real cut, so the leftover
        // (3 to 4) is split evenly for the last two images.
        XCTAssertEqual(lengths.reduce(0, +), 3, accuracy: 1e-9)
        XCTAssertEqual(lengths.count, 4)
        XCTAssertEqual(lengths[0], 1, accuracy: 1e-9)  // 1 to 2
        XCTAssertEqual(lengths[1], 1, accuracy: 1e-9)  // 2 to 3
    }

    func testSparseBeatsFillTheRestEvenly() {
        var (s, items) = show()
        items[9] = item(9, kind: .audio, duration: 20)
        s.music = [AudioClip(itemID: 9, start: 0, length: 20)]
        // One bar start in range: only one usable interior cut for 3 needed.
        let r = SongRhythm(beats: [1, 5, 9, 13], bars: [1, 9])
        let lengths = RangeFill.lengths(itemCount: 4, timing: .rhythm(BeatPlan(mode: .bars(1))),
                                        show: s, rhythms: [9: r], in: 1...13)
        XCTAssertEqual(lengths.reduce(0, +), 12, accuracy: 1e-9)
        XCTAssertEqual(lengths[0], 8, accuracy: 1e-9)   // 1 to 9: the one real bar cut
        XCTAssertEqual(lengths[1], lengths[2], accuracy: 1e-9)  // the rest split evenly
        XCTAssertEqual(lengths[2], lengths[3], accuracy: 1e-9)
    }

    // MARK: Replace

    func testReplaceInTheMiddleOfOneSlideKeepsTheShowLength() {
        let (s, items) = show([4, 4, 4])  // 0-4, 4-8, 8-12
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10, 11], timing: .even, transition: nil, mode: .replace)
        // Range 5...7 lies wholly inside slide 2 (4-8).
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 5...7)
        let ot = ShowTimeline(show: out, items: items.merging([10: item(10), 11: item(11)]) { a, _ in a })
        XCTAssertEqual(ot.duration, 12, accuracy: 1e-9)
        // Slide 1 (0-4) untouched, slide 2 trimmed to 4-5, two new 1 s
        // slides (5-6, 6-7), then a tail continuing slide 2's image 7-8,
        // then slide 3 (8-12) untouched.
        XCTAssertEqual(ot.slides.map(\.start), [0, 4, 5, 6, 7, 8])
        XCTAssertEqual(ot.slides.map(\.length), [4, 1, 1, 1, 1, 4])
        XCTAssertEqual(ot.slides.map(\.item.id), [1, 2, 10, 11, 2, 3])
    }

    func testReplaceAcrossTwoWholeSlidesRemovesWhatsBetween() {
        let (s, items) = show([4, 4, 4, 4])  // 0-4, 4-8, 8-12, 12-16
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10, 11, 12], timing: .even, transition: nil, mode: .replace)
        // Range 2...14: starts inside slide 1, slides 2 and 3 wholly
        // inside, ends inside slide 4.
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 2...14)
        var allItems = items
        for id in [10, 11, 12] as [Int64] { allItems[id] = item(id) }
        let ot = ShowTimeline(show: out, items: allItems)
        XCTAssertEqual(ot.duration, 16, accuracy: 1e-9)
        // Slide 1 trimmed to 0-2, slides 2 and 3 gone, 3 new 4 s slides
        // (2-6-10-14), slide 4 shortened at its front to start at 14.
        XCTAssertEqual(ot.slides.map(\.item.id), [1, 10, 11, 12, 4])
        XCTAssertEqual(ot.slides.map(\.length), [2, 4, 4, 4, 2])
        XCTAssertEqual(ot.slides.last?.start, 14)
    }

    func testReplaceIsUndoableInOneStepAndKeepsTrimmedSettings() {
        var (s, items) = show([6])
        s.slides[0].settings.transition = Transition(style: .push, duration: 1)
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10], timing: .even, transition: nil, mode: .replace)
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 2...4)
        // The trimmed start slide keeps its own transition (a trim, not a
        // reset) and the tail (4-6) is the same file continuing.
        XCTAssertEqual(out.slides[0].settings.transition?.style, .push)
        items[10] = item(10)
        let ot = ShowTimeline(show: out, items: items)
        XCTAssertEqual(ot.duration, 6, accuracy: 1e-9)
        XCTAssertEqual(ot.slides.map(\.item.id), [1, 10, 1])
        XCTAssertEqual(ot.slides.map(\.length), [2, 2, 2])
    }

    /// Found by hand (a range set to "the whole view" from 0, in a scratch
    /// show): the start slide's own trim rounds to nothing, but it was
    /// still being kept as a 1 ms stub.
    func testARangeStartingAtASlidesOwnStartDropsItInstead() {
        let (s, items) = show([4, 4])  // 0-4, 4-8
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10], timing: .even, transition: nil, mode: .replace)
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 0...4)
        // Slide 1 is gone outright, not a near-zero remainder.
        XCTAssertEqual(out.slides.map(\.itemID), [10, 2])
    }

    /// The mirror case at the far end: the range's end lands exactly on a
    /// slide's own end, so there's nothing left of it to keep either.
    func testARangeEndingAtASlidesOwnEndDropsItInstead() {
        let (s, items) = show([4, 4])  // 0-4, 4-8
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10], timing: .even, transition: nil, mode: .replace)
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 2...8)
        XCTAssertEqual(out.slides.map(\.itemID), [1, 10])
    }

    // MARK: Displace

    func testDisplaceKeepsEverythingAndLengthensTheShow() {
        let (s, items) = show([4, 4])  // 0-4, 4-8
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10, 11], timing: .even, transition: nil, mode: .displace)
        // Range 2...6 starts inside slide 1; nothing else is removed, so
        // slide 1's trim (like Replace's) still discards its 2-4 stretch,
        // but slide 2 is untouched — just pushed later, to start where the
        // fill ends instead of where slide 1 used to end.
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 2...6)
        var allItems = items
        allItems[10] = item(10); allItems[11] = item(11)
        let ot = ShowTimeline(show: out, items: allItems)
        XCTAssertEqual(ot.duration, 2 + 2 + 2 + 4, accuracy: 1e-9)
        XCTAssertEqual(ot.slides.map(\.item.id), [1, 10, 11, 2])
        XCTAssertEqual(ot.slides.map(\.length), [2, 2, 2, 4])
    }

    func testDisplacePastEveryExistingSlideAppendsAtTheEnd() {
        let (s, items) = show([4])
        let t = ShowTimeline(show: s, items: items)
        let plan = RangeFillPlan(itemIDs: [10], timing: .even, transition: nil, mode: .displace)
        let out = RangeFill.apply(plan, to: s, timeline: t, rhythms: [:], in: 4...6)
        XCTAssertEqual(out.slides.map(\.itemID), [1, 10])
    }

    func testEmptyPickOrEmptyRangeChangesNothing() {
        let (s, items) = show()
        let t = ShowTimeline(show: s, items: items)
        let noImages = RangeFillPlan(itemIDs: [], timing: .even, transition: nil, mode: .replace)
        XCTAssertEqual(RangeFill.apply(noImages, to: s, timeline: t, rhythms: [:], in: 1...5), s)
        let emptyRange = RangeFillPlan(itemIDs: [10], timing: .even, transition: nil, mode: .replace)
        XCTAssertEqual(RangeFill.apply(emptyRange, to: s, timeline: t, rhythms: [:], in: 3...3), s)
    }
}
