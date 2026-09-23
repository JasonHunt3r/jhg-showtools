import XCTest
import AVFoundation
import CoreImage
@testable import ShowToolsCore

/// Video export E5: a video slide's own frames (spec/video-export.md),
/// and the timing rule the player and the exporter share.
final class VideoSlideTests: XCTestCase {

    // MARK: - VideoSlideTiming

    func testASlideShorterThanItsVideoJustPlaysForward() {
        // A 10 s file, held 4 s: straight through, no looping.
        for (local, want) in [(0.0, 0.0), (1.0, 1.0), (3.9, 3.9)] {
            let p = VideoSlideTiming.position(localTime: local, slideLength: 4,
                                              clipStart: 0, duration: 10)
            XCTAssertEqual(p.time, want, accuracy: 1e-9, "at \(local)")
            XCTAssertFalse(p.loops)
        }
    }

    func testClipStartOffsetsIntoTheFile() {
        let p = VideoSlideTiming.position(localTime: 2, slideLength: 4, clipStart: 3, duration: 10)
        XCTAssertEqual(p.time, 5, accuracy: 1e-9)
    }

    /// The rule that's easy to miss: a slide held longer than the video's
    /// remaining length plays it **again** from `clipStart`, rather than
    /// freezing on the last frame.
    func testASlideLongerThanItsVideoLoops() {
        // A 4 s file from 0, held 10 s: it loops every 4 s.
        let long = VideoSlideTiming.position(localTime: 0, slideLength: 10, clipStart: 0, duration: 4)
        XCTAssertTrue(long.loops)
        for (local, want) in [(0.0, 0.0), (3.9, 3.9), (4.5, 0.5), (9.0, 1.0)] {
            let p = VideoSlideTiming.position(localTime: local, slideLength: 10,
                                              clipStart: 0, duration: 4)
            XCTAssertEqual(p.time, want, accuracy: 1e-9, "at \(local)")
        }
    }

    /// Looping is judged on what's left after `clipStart`, not the whole file.
    func testLoopingCountsFromTheClipStart() {
        // 10 s file, starting 8 s in: only 2 s left, so a 5 s slide loops.
        let p = VideoSlideTiming.position(localTime: 2.5, slideLength: 5,
                                          clipStart: 8, duration: 10)
        XCTAssertTrue(p.loops)
        XCTAssertEqual(p.time, 8.5, accuracy: 1e-9)   // 2.5 mod 2 = 0.5, from 8
    }

    /// Held only a shade longer than the video, it holds the last frame
    /// rather than starting again. The line between this and looping is
    /// 0.1 s: held 4.5 s a 4 s video *does* loop.
    func testASlideThatRunsAShadePastItsVideoHoldsTheLastFrame() {
        let p = VideoSlideTiming.position(localTime: 4.02, slideLength: 4.05,
                                          clipStart: 0, duration: 4)
        XCTAssertFalse(p.loops)
        XCTAssertEqual(p.time, 3.96, accuracy: 1e-9)  // the last frame's slack
        XCTAssertTrue(p.holding)

        // Just over the line, it loops instead.
        XCTAssertTrue(VideoSlideTiming.position(localTime: 4.4, slideLength: 4.5,
                                                clipStart: 0, duration: 4).loops)
    }

    func testAFileWithNoLengthFallsBackToTheSlidesOwnClock() {
        let p = VideoSlideTiming.position(localTime: 2, slideLength: 5, clipStart: 1, duration: 0)
        XCTAssertEqual(p.time, 2, accuracy: 1e-9)
    }

    // MARK: - Reading a video's frames

    /// A short test movie whose colour changes every second, so the frame
    /// that comes back says what time it is.
    func makeVideo(seconds: Int = 4, size: CGSize = CGSize(width: 160, height: 120)) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoSlideTests-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        var show = Show(id: 1, name: "v", defaults: ShowDefaults(), slides: [])
        show.defaults.transition = Transition(style: .cut, duration: 0)
        let items = (0..<seconds).map {
            MediaItem(id: Int64($0 + 1), relativePath: "\($0)", hash: "h\($0)", kind: .image,
                      pixelWidth: 100, pixelHeight: 100, duration: nil,
                      ingestedAt: Date(), sourcePath: "")
        }
        show.slides = items.map {
            Slide(id: $0.id, itemID: $0.id, settings: SlideSettings(length: .seconds(1), fit: .fill))
        }
        let timeline = ShowTimeline(show: show,
                                    items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
        // Second n is a flat colour with red = n/10, so a frame's red
        // channel says which second it came from.
        try MoviePictureTrack.write(
            timeline: timeline, to: url,
            settings: MovieExportSettings(size: size, frameRate: .fps30),
            showAspect: size.width / size.height) { layer in
                let n = Double(layer.slide.index)
                return CIImage(color: CIColor(red: n / 10, green: 0.5, blue: 0.5))
                    .cropped(to: CGRect(origin: .zero, size: CGSize(width: 100, height: 100)))
            }
        return url
    }

    /// The red channel of a frame's middle pixel, which says which second
    /// of the test video it is.
    func second(of image: CIImage?) -> Double? {
        guard let image else { return nil }
        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        let mid = CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: mid,
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (Double(pixel[0]) / 255 * 10).rounded()
    }

    func testFramesComeBackInOrderAsTheClockMovesForward() throws {
        let url = try makeVideo(seconds: 4)
        let frames = try XCTUnwrap(MovieVideoFrames(url: url))
        XCTAssertEqual(frames.duration, 4, accuracy: 0.1)

        // Ask across the whole video, forward, as an export does.
        for want in 0...3 {
            let got = second(of: frames.frame(at: Double(want) + 0.5))
            XCTAssertEqual(got, Double(want), "at \(want).5s")
        }
        // Read straight through: one start, no seeking about.
        XCTAssertEqual(frames.seeks, 1, "reading forward shouldn't seek")
    }

    func testTheFrameHeldIsTheOneCoveringThatMoment() throws {
        let url = try makeVideo(seconds: 3)
        let frames = try XCTUnwrap(MovieVideoFrames(url: url))
        // Just inside each second, and just before the next one begins.
        XCTAssertEqual(second(of: frames.frame(at: 0.01)), 0)
        XCTAssertEqual(second(of: frames.frame(at: 0.99)), 0)
        XCTAssertEqual(second(of: frames.frame(at: 1.01)), 1)
        XCTAssertEqual(second(of: frames.frame(at: 1.99)), 1)
        XCTAssertEqual(second(of: frames.frame(at: 2.01)), 2)
    }

    /// Going backwards is what a looping slide does, and it must work —
    /// it just costs a start.
    func testAskingBackwardsStartsAgainRatherThanFailing() throws {
        let url = try makeVideo(seconds: 4)
        let frames = try XCTUnwrap(MovieVideoFrames(url: url))
        XCTAssertEqual(second(of: frames.frame(at: 3.5)), 3)
        XCTAssertEqual(second(of: frames.frame(at: 0.5)), 0, "after going back to the start")
        XCTAssertEqual(second(of: frames.frame(at: 1.5)), 1)
        XCTAssertEqual(frames.seeks, 2, "one start, then one more for the jump back")
    }

    func testPastTheEndTheLastFrameIsHeld() throws {
        let url = try makeVideo(seconds: 2)
        let frames = try XCTUnwrap(MovieVideoFrames(url: url))
        XCTAssertEqual(second(of: frames.frame(at: 1.5)), 1)
        XCTAssertNotNil(frames.frame(at: 5), "past the end should hold, not go blank")
        XCTAssertEqual(second(of: frames.frame(at: 5)), 1)
    }

    func testAFileWithNoVideoTrackIsRefused() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoSlideTests-\(UUID().uuidString).caf")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        try file.write(from: buffer)
        XCTAssertNil(MovieVideoFrames(url: url))
    }

    // MARK: - Through MovieMedia, as an export sees it

    func videoShow(length: Double, clipStart: Double = 0, duration: Double = 4)
    -> (ShowTimeline, MediaItem) {
        let item = MediaItem(id: 1, relativePath: "v.mp4", hash: "hv", kind: .video,
                             pixelWidth: 160, pixelHeight: 120, duration: duration,
                             ingestedAt: Date(), sourcePath: "")
        var settings = SlideSettings(length: .seconds(length), fit: .fill)
        settings.clipStart = clipStart
        var show = Show(id: 1, name: "v", defaults: ShowDefaults(), slides: [])
        show.defaults.transition = Transition(style: .cut, duration: 0)
        show.slides = [Slide(id: 1, itemID: 1, settings: settings)]
        return (ShowTimeline(show: show, items: [1: item]), item)
    }

    func testAVideoSlideExportsItsOwnFramesNotOneHeldFrame() throws {
        let url = try makeVideo(seconds: 4)
        let (timeline, _) = videoShow(length: 4)
        let media = MovieMedia { _ in url }

        var seen: [Double?] = []
        for t in [0.5, 1.5, 2.5, 3.5] {
            guard case .still(let layer) = timeline.frame(at: t) else {
                XCTFail("expected a still at \(t)"); continue
            }
            seen.append(second(of: media.image(for: layer)))
        }
        XCTAssertEqual(seen, [0, 1, 2, 3], "the slide should play, not hold one frame")
        XCTAssertTrue(media.videoSlidesHeld.isEmpty, "nothing should have been held")
    }

    /// The pre-E5 behaviour is still reachable, and still says so.
    func testHoldFirstFrameKeepsTheOldBehaviour() throws {
        let url = try makeVideo(seconds: 4)
        let (timeline, _) = videoShow(length: 4)
        let media = MovieMedia { _ in url }
        media.holdFirstFrame = true

        var seen: [Double?] = []
        for t in [0.5, 2.5] {
            guard case .still(let layer) = timeline.frame(at: t) else { continue }
            seen.append(second(of: media.image(for: layer)))
        }
        XCTAssertEqual(seen, [0, 0], "held means the first frame throughout")
        XCTAssertEqual(media.videoSlidesHeld, [1])
    }

    /// A slide held longer than its video loops, in the export as in the
    /// player.
    func testALongSlideLoopsItsVideoInTheExport() throws {
        let url = try makeVideo(seconds: 4)
        let (timeline, _) = videoShow(length: 10)
        let media = MovieMedia { _ in url }

        var seen: [Double?] = []
        for t in [0.5, 3.5, 4.5, 7.5] {
            guard case .still(let layer) = timeline.frame(at: t) else { continue }
            seen.append(second(of: media.image(for: layer)))
        }
        // 4.5 s in it is half a second into the second pass, and 7.5 s in
        // it is 3.5 s into it.
        XCTAssertEqual(seen, [0, 3, 0, 3])
    }

    /// A video that can't be read falls back to a held frame and is
    /// counted, so the panel can still say so.
    func testAnUnreadableVideoIsHeldAndCounted() throws {
        let (timeline, _) = videoShow(length: 2)
        let media = MovieMedia { _ in URL(fileURLWithPath: "/nowhere/missing.mp4") }
        guard case .still(let layer) = timeline.frame(at: 1) else { return XCTFail("no still") }
        XCTAssertNil(media.image(for: layer))
        XCTAssertEqual(media.videoSlidesHeld, [1])
    }
}
