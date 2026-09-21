import XCTest
import CoreImage
@testable import ShowToolsCore

final class TimelineTests: XCTestCase {

    func item(_ id: Int64, kind: MediaKind = .image, duration: Double? = nil) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: kind,
                    pixelWidth: 4000, pixelHeight: 3000, duration: duration,
                    ingestedAt: Date(), sourcePath: "")
    }

    func show(_ lengths: [Double?], loop: Bool = false) -> (Show, [Int64: MediaItem]) {
        var d = ShowDefaults()
        d.loop = loop
        // These tests were written against a 1 s dissolve from the join (the
        // default before 2c); pinned so they keep testing the same thing.
        d.transition = Transition(style: .dissolve, duration: 1)
        let slides = lengths.enumerated().map { i, l in
            Slide(id: Int64(i + 1), itemID: Int64(i + 1),
                  settings: SlideSettings(length: l.map { .seconds($0) }))
        }
        let items = Dictionary(uniqueKeysWithValues: slides.map { ($0.itemID, item($0.itemID)) })
        return (Show(id: 1, name: "t", defaults: d, slides: slides), items)
    }

    func testStartsFollowLengthsAndDefaults() {
        let (s, items) = show([nil, 3, nil])
        let t = ShowTimeline(show: s, items: items)
        XCTAssertEqual(t.slides.map(\.start), [0, 5, 8])
        XCTAssertEqual(t.duration, 13)
    }

    func testTransitionOverlapsStartOfIncomingSlide() {
        let (s, items) = show([4, 4])
        let t = ShowTimeline(show: s, items: items)
        // Default dissolve is 1s. At 4.5 we're halfway from slide 0 to slide 1.
        guard case .transition(let a, let b, _, let p) = t.frame(at: 4.5) else {
            return XCTFail("expected a transition")
        }
        XCTAssertEqual(a.slide.index, 0)
        XCTAssertEqual(b.slide.index, 1)
        XCTAssertEqual(p, 0.5, accuracy: 1e-9)
        XCTAssertEqual(a.localTime, 4.5, accuracy: 1e-9)
        guard case .still(let l) = t.frame(at: 5.5) else { return XCTFail("expected still") }
        XCTAssertEqual(l.slide.index, 1)
    }

    func testFirstSlideHasNoTransitionUntilTheShowWraps() {
        let (s, items) = show([4, 4], loop: true)
        let t = ShowTimeline(show: s, items: items)
        guard case .still = t.frame(at: 0.5) else { return XCTFail("first pass: no transition in") }
        guard case .transition(let a, let b, _, _) = t.frame(at: 8.5) else {
            return XCTFail("second pass: last → first")
        }
        XCTAssertEqual(a.slide.index, 1)
        XCTAssertEqual(b.slide.index, 0)
        XCTAssertEqual(a.localTime, 4.5, accuracy: 1e-9)
    }

    func testTransitionClampedToShortSlide() {
        var (s, items) = show([4, 0.5])
        s.defaults.transition.duration = 2
        let t = ShowTimeline(show: s, items: items)
        XCTAssertEqual(t.slides[1].transitionIn.duration, 0.5)
    }

    func testVideoUsesClipLengthByDefault() {
        let s = Show(id: 1, name: "v", slides: [Slide(id: 1, itemID: 1)])
        let t = ShowTimeline(show: s, items: [1: item(1, kind: .video, duration: 12.5)])
        XCTAssertEqual(t.slides[0].length, 12.5)
    }

    func testSameItemTwiceKeepsSeparateSettings() {
        let s = Show(id: 1, name: "d", slides: [
            Slide(id: 1, itemID: 7, settings: SlideSettings(length: .seconds(2))),
            Slide(id: 2, itemID: 7, settings: SlideSettings(length: .seconds(9))),
        ])
        let t = ShowTimeline(show: s, items: [7: item(7)])
        XCTAssertEqual(t.slides.map(\.length), [2, 9])
    }

    func testAutoKenBurnsIsStablePerSlide() {
        XCTAssertEqual(ShowTimeline.autoKenBurns(seed: 42), ShowTimeline.autoKenBurns(seed: 42))
        XCTAssertNotEqual(ShowTimeline.autoKenBurns(seed: 42), ShowTimeline.autoKenBurns(seed: 43))
    }

    func testIndexAtTime() {
        let (s, items) = show([2, 2, 2], loop: true)
        let t = ShowTimeline(show: s, items: items)
        XCTAssertEqual(t.index(at: 0), 0)
        XCTAssertEqual(t.index(at: 3.9), 1)
        XCTAssertEqual(t.index(at: 4), 2)
        XCTAssertEqual(t.index(at: 6.1), 0)
    }

    // MARK: Framing

    func testFillCoversOutputWithoutShowingPastEdges() {
        let img = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let out = Compositor.placed(img, fit: .fill, kb: KenBurnsFrame(x: 0, y: 0, zoom: 1),
                                    in: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(out.extent, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testFitLetterboxesTallImage() {
        let img = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 2000))
        let out = Compositor.placed(img, fit: .fit, kb: .centred, in: CGSize(width: 1920, height: 1080))
        // Rendered area of the image: 540 wide, centred.
        let ctx = CIContext()
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(out.composited(over: CIImage(color: .black)), toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 100, y: 540, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        XCTAssertEqual(px[0], 0, "left bar should be empty")
        ctx.render(out, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 960, y: 540, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        XCTAssertEqual(px[0], 255, "centre should be image")
    }
}

final class ClipStartTests: XCTestCase {
    func testClipLengthIsWhatRemainsAfterTheTrimmedFront() {
        let item = MediaItem(id: 1, relativePath: "v.mov", hash: "v", kind: .video, pixelWidth: 1280,
                             pixelHeight: 720, duration: 10, ingestedAt: Date(), sourcePath: "")
        let s = Show(id: 1, name: "v", slides: [Slide(id: 1, itemID: 1, settings: SlideSettings(clipStart: 3))])
        let t = ShowTimeline(show: s, items: [1: item])
        XCTAssertEqual(t.slides[0].length, 7)
        XCTAssertEqual(t.slides[0].clipStart, 3)
    }
}
