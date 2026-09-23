import XCTest
import AVFoundation
import CoreImage
@testable import ShowToolsCore

/// Video export E2: the picture track (spec/video-export.md). Every test
/// here writes a real movie and reads it back with `AVAssetReader` — the
/// by-eye check `stcli render` does, automated.
final class MoviePictureTrackTests: XCTestCase {

    // MARK: - A show made of flat colours

    let red = CIColor(red: 0.9, green: 0.1, blue: 0.1)
    let blue = CIColor(red: 0.1, green: 0.2, blue: 0.9)

    func item(_ id: Int64) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: .image,
                  pixelWidth: 1000, pixelHeight: 1000, duration: nil,
                  ingestedAt: Date(), sourcePath: "")
    }

    /// Two one-second slides, cut between so each frame is one flat colour.
    /// `.fill` so the colour covers the frame whatever its shape.
    func flatShow(seconds: Double = 1) -> ShowTimeline {
        var d = ShowDefaults()
        d.transition = Transition(style: .cut, duration: 0)
        let slides = [Int64(1), Int64(2)].map {
            Slide(id: $0, itemID: $0, settings: SlideSettings(length: .seconds(seconds), fit: .fill))
        }
        let items = Dictionary(uniqueKeysWithValues: slides.map { ($0.itemID, item($0.itemID)) })
        return ShowTimeline(show: Show(id: 1, name: "flat", defaults: d, slides: slides), items: items)
    }

    /// Each slide's "file": a flat square of its colour.
    func flatSource(_ layer: Layer) -> CIImage? {
        let c = layer.slide.item.id == 1 ? red : blue
        return CIImage(color: c).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    func scratch(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoviePictureTrackTests-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Reading a movie back

    struct ReadFrame {
        var time: Double
        var buffer: CVPixelBuffer
    }

    /// Every frame of a movie, as pixel buffers.
    func readFrames(_ url: URL) throws -> [ReadFrame] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        guard let track = asset.tracks(withMediaType: .video).first else {
            XCTFail("no video track in \(url.lastPathComponent)")
            return []
        }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        out.alwaysCopiesSampleData = true
        reader.add(out)
        reader.startReading()
        var frames: [ReadFrame] = []
        while let sample = out.copyNextSampleBuffer() {
            if let b = CMSampleBufferGetImageBuffer(sample) {
                frames.append(ReadFrame(time: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)),
                                        buffer: b))
            }
        }
        return frames
    }

    /// One pixel, as red/green/blue in 0…1. The buffer is 32BGRA.
    func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (-1, -1, -1) }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.advanced(by: y * row + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Double(p[2]) / 255, Double(p[1]) / 255, Double(p[0]) / 255)
    }

    func assertColour(_ got: (r: Double, g: Double, b: Double), _ want: CIColor,
                      tolerance: Double = 0.02, _ what: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.r, Double(want.red), accuracy: tolerance, "\(what) red", file: file, line: line)
        XCTAssertEqual(got.g, Double(want.green), accuracy: tolerance, "\(what) green", file: file, line: line)
        XCTAssertEqual(got.b, Double(want.blue), accuracy: tolerance, "\(what) blue", file: file, line: line)
    }

    // MARK: - How many frames a show comes to

    func testAShowsLengthBecomesAWholeNumberOfFrames() {
        // 2 s at 30 fps is 60 frames, at times 0 … 59/30 — the last frame is
        // the one that starts before the show ends.
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 2, fps: 30), 60)
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 2, fps: 24), 48)
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 2, fps: 60), 120)
        // A length between frames rounds up, so nothing is cut off the end.
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 2.01, fps: 30), 61)
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 1.99, fps: 30), 60)
        // Degenerate shows.
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 0, fps: 30), 0)
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 5, fps: 0), 0)
        XCTAssertEqual(MoviePictureTrack.frameCount(duration: 0.001, fps: 30), 1)
    }

    func testAShowWithNoLengthIsRefusedRatherThanWrittenEmpty() {
        let empty = ShowTimeline(show: Show(id: 1, name: "none", defaults: ShowDefaults(), slides: []),
                                 items: [:])
        XCTAssertThrowsError(try MoviePictureTrack.write(
            timeline: empty, to: scratch("mp4"),
            settings: MovieExportSettings(size: CGSize(width: 320, height: 180)),
            showAspect: 16.0 / 9.0, source: flatSource)) { error in
            guard case MovieExportError.emptyShow = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: - The movie that comes out

    func testAShortShowWritesEveryFrameAtTheAskedForSize() throws {
        let url = scratch("mp4")
        let settings = MovieExportSettings(size: CGSize(width: 640, height: 360), frameRate: .fps30)
        let result = try MoviePictureTrack.write(timeline: flatShow(), to: url,
                                                 settings: settings, showAspect: 16.0 / 9.0,
                                                 source: flatSource)
        XCTAssertEqual(result.frameCount, 60)            // 2 s at 30 fps
        XCTAssertEqual(result.duration, 2, accuracy: 1e-9)
        XCTAssertEqual(result.size, CGSize(width: 640, height: 360))

        let frames = try readFrames(url)
        XCTAssertEqual(frames.count, 60)
        XCTAssertEqual(CVPixelBufferGetWidth(frames[0].buffer), 640)
        XCTAssertEqual(CVPixelBufferGetHeight(frames[0].buffer), 360)
        // Frames land on the clock: the nth at n/30.
        XCTAssertEqual(frames[0].time, 0, accuracy: 1e-6)
        XCTAssertEqual(frames[30].time, 1, accuracy: 1e-6)
        XCTAssertEqual(frames[59].time, 59.0 / 30.0, accuracy: 1e-6)
    }

    /// The point of the whole step: what comes out of the file is what the
    /// Compositor drew at that time.
    func testAFrameHoldsWhatTheCompositorDrawsAtThatTime() throws {
        let url = scratch("mp4")
        let settings = MovieExportSettings(size: CGSize(width: 640, height: 360), frameRate: .fps30)
        try MoviePictureTrack.write(timeline: flatShow(), to: url, settings: settings,
                                    showAspect: 16.0 / 9.0, source: flatSource)
        let frames = try readFrames(url)
        XCTAssertEqual(frames.count, 60)
        // Halfway through slide 1, and halfway through slide 2.
        assertColour(pixel(frames[15].buffer, x: 320, y: 180), red, "slide 1 at t=0.5")
        assertColour(pixel(frames[45].buffer, x: 320, y: 180), blue, "slide 2 at t=1.5")
        // And the cut is where the timeline says it is, not a frame either side.
        assertColour(pixel(frames[29].buffer, x: 320, y: 180), red, "the frame before the cut")
        assertColour(pixel(frames[30].buffer, x: 320, y: 180), blue, "the frame after the cut")
    }

    func testEachCodecWritesAFileItsContainerCanCarry() throws {
        for codec in MovieCodec.allCases {
            let url = scratch(codec.fileExtension)
            var settings = MovieExportSettings(size: CGSize(width: 320, height: 180), frameRate: .fps24)
            settings.codec = codec
            let result = try MoviePictureTrack.write(timeline: flatShow(seconds: 0.5), to: url,
                                                     settings: settings, showAspect: 16.0 / 9.0,
                                                     source: flatSource)
            XCTAssertEqual(result.frameCount, 24, codec.name)          // 1 s at 24 fps
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), codec.name)
            let frames = try readFrames(url)
            XCTAssertEqual(frames.count, 24, codec.name)
            assertColour(pixel(frames[5].buffer, x: 160, y: 90), red, "\(codec.name) slide 1")
        }
    }

    // MARK: - Letterboxing

    /// A 16:10 show exported at 16:9 keeps its whole picture and gets black
    /// bars down the sides — it is never cropped.
    func testALetterboxedExportFillsTheCanvasAndBarsThePicture() throws {
        let url = scratch("mp4")
        let settings = MovieExportSettings(size: CGSize(width: 640, height: 360), frameRate: .fps30)
        let plan = settings.plan(showAspect: 16.0 / 10.0)
        XCTAssertTrue(plan.isLetterboxed)
        let result = try MoviePictureTrack.write(timeline: flatShow(seconds: 0.5), to: url,
                                                 settings: settings, showAspect: 16.0 / 10.0,
                                                 source: flatSource)
        // The movie is the full canvas, bars and all.
        XCTAssertEqual(result.size, CGSize(width: 640, height: 360))
        let frames = try readFrames(url)
        XCTAssertEqual(CVPixelBufferGetWidth(frames[0].buffer), 640)
        // The middle is the show; the far edges are the bars.
        assertColour(pixel(frames[5].buffer, x: 320, y: 180), red, "the picture")
        assertColour(pixel(frames[5].buffer, x: 2, y: 180), CIColor(red: 0, green: 0, blue: 0),
                     tolerance: 0.02, "the left bar")
        assertColour(pixel(frames[5].buffer, x: 637, y: 180), CIColor(red: 0, green: 0, blue: 0),
                     tolerance: 0.02, "the right bar")
    }

    // MARK: - Progress and cancelling

    func testProgressRunsFromTheFirstFrameToOne() throws {
        var seen: [Double] = []
        try MoviePictureTrack.write(timeline: flatShow(seconds: 0.5), to: scratch("mp4"),
                                    settings: MovieExportSettings(size: CGSize(width: 320, height: 180)),
                                    showAspect: 16.0 / 9.0,
                                    progress: { seen.append($0) }, source: flatSource)
        XCTAssertEqual(seen.count, 30)
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertGreaterThan(seen.first ?? 0, 0)
    }

    /// A cancelled export leaves no half-written movie behind.
    func testCancellingStopsAndLeavesNoFile() throws {
        let url = scratch("mp4")
        var frames = 0
        XCTAssertThrowsError(try MoviePictureTrack.write(
            timeline: flatShow(), to: url,
            settings: MovieExportSettings(size: CGSize(width: 320, height: 180)),
            showAspect: 16.0 / 9.0,
            isCancelled: { frames += 1; return frames > 5 },
            source: flatSource)) { error in
            guard case MovieExportError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "a part-written file was left")
    }
}
