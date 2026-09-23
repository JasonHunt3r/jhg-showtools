import Foundation
import AVFoundation
import CoreImage
import CoreVideo

// Video export (plan, `spec/video-export.md`). E2: the picture track.
//
// The inner loop is `stcli render`'s, which has been writing frames through
// the real Compositor since Phase 1 — walk `t` by 1/fps, `frame(at:)` →
// `Compositor.compose` → render. The only new parts are where the pixels
// go (a pixel buffer from the writer's pool, not a PNG) and the letterbox
// the settings' `plan` describes.

public enum MovieExportError: Error, Sendable {
    /// `isCancelled` returned true. The part-written file is removed.
    case cancelled
    /// The show has no length to walk.
    case emptyShow
    /// `AVAssetWriter` refused to start, or failed partway.
    case writerFailed(String)
    /// The writer gave no pixel buffer pool, or it gave out.
    case noPixelBuffer
}

public struct MovieExportResult: Hashable, Sendable {
    public var url: URL
    /// The movie's frame size — the whole canvas, letterbox included.
    public var size: CGSize
    public var frameCount: Int
    public var frameRate: Int
    /// The movie's length in seconds: `frameCount / frameRate`.
    public var duration: Double { frameRate > 0 ? Double(frameCount) / Double(frameRate) : 0 }
}

public enum MoviePictureTrack {

    /// How many frames a show of this length comes to. The last frame is
    /// the one that starts before the show ends, so a 2 s show at 30 fps is
    /// 60 frames, at times 0 … 59/30.
    public static func frameCount(duration: Double, fps: Int) -> Int {
        guard duration > 0, fps > 0 else { return 0 }
        let n = Int((duration * Double(fps)).rounded(.up))
        // A duration that lands exactly on a frame boundary shouldn't get an
        // extra frame past the end.
        let exact = Int((duration * Double(fps)).rounded())
        return abs(duration * Double(fps) - Double(exact)) < 1e-9 ? max(exact, 1) : max(n, 1)
    }

    /// Writes a show's picture track.
    ///
    /// **Call this off the main thread.** It blocks: it waits on the
    /// encoder, and finishing the file waits on a callback. Core doesn't
    /// dispatch for the caller — the app does that around `ExportStatus`.
    ///
    /// Like `Compositor.compose`, media comes in through closures, so Core
    /// reaches for no files and `stcli` can drive this too. A video slide's
    /// `source` hands back its first frame (settled with Jason, 2026-09-22);
    /// real video is E5.
    ///
    /// - Parameters:
    ///   - showAspect: the shape the show is composed for. The picture is
    ///     fitted inside `settings.size` at this shape and letterboxed,
    ///     never cropped.
    ///   - progress: called with 0…1 as frames go by, on this thread.
    ///   - isCancelled: checked once a frame. True stops and removes the file.
    @discardableResult
    public static func write(timeline: ShowTimeline,
                             to url: URL,
                             settings: MovieExportSettings,
                             showAspect: CGFloat,
                             context: CIContext = CIContext(),
                             overlaySource: ((OverlayLayer) -> CIImage?)? = nil,
                             progress: ((Double) -> Void)? = nil,
                             isCancelled: (() -> Bool)? = nil,
                             source: (Layer) -> CIImage?) throws -> MovieExportResult {

        let fps = settings.frameRate.fps
        let total = frameCount(duration: timeline.duration, fps: fps)
        guard total > 0 else { throw MovieExportError.emptyShow }

        let plan = settings.plan(showAspect: showAspect)
        let canvas = CGRect(origin: .zero, size: plan.canvas)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: settings.codec.container.fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.codec.avCodec,
            AVVideoWidthKey: Int(plan.canvas.width),
            AVVideoHeightKey: Int(plan.canvas.height),
            // Say what the colours are. Untagged, an encoder writes YCbCr by
            // one matrix and a player reads it by another: measured here as a
            // green channel coming back at 0.016 where 0.1 went in, on every
            // codec including ProRes. Frames are rendered sRGB, and Rec. 709
            // is the tag every player reads that way.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        // Not a live capture: let the encoder set the pace and never drop.
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(plan.canvas.width),
                kCVPixelBufferHeightKey as String: Int(plan.canvas.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        guard writer.canAdd(input) else {
            throw MovieExportError.writerFailed("the writer wouldn't take a \(settings.codec.name) track")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw MovieExportError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        func fail(_ e: MovieExportError) -> MovieExportError {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return e
        }

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let black = CIImage(color: .black).cropped(to: canvas)
        let offset = CGAffineTransform(translationX: plan.picture.minX, y: plan.picture.minY)

        for n in 0..<total {
            if isCancelled?() == true { throw fail(.cancelled) }

            // Back-pressure: the encoder says when it wants the next frame.
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw fail(.writerFailed(writer.error?.localizedDescription ?? "the encoder failed"))
                }
                Thread.sleep(forTimeInterval: 0.002)
            }

            let t = Double(n) / Double(fps)
            let state = timeline.frame(at: t)
            var picture = Compositor.compose(state, size: plan.picture.size,
                                             overlay: timeline.overlay(at: t),
                                             overlaySource: overlaySource, source: source)
            if plan.isLetterboxed {
                picture = picture.transformed(by: offset).composited(over: black)
            }

            guard let pool = adaptor.pixelBufferPool else { throw fail(.noPixelBuffer) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw fail(.noPixelBuffer) }

            context.render(picture.cropped(to: canvas), to: buffer,
                           bounds: canvas, colorSpace: srgb)

            let time = CMTime(value: CMTimeValue(n), timescale: CMTimeScale(fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw fail(.writerFailed(writer.error?.localizedDescription ?? "a frame wouldn't append"))
            }
            progress?(Double(n + 1) / Double(total))
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed {
            try? FileManager.default.removeItem(at: url)
            throw MovieExportError.writerFailed(writer.error?.localizedDescription ?? "the file wouldn't finish")
        }
        return MovieExportResult(url: url, size: plan.canvas, frameCount: total, frameRate: fps)
    }
}
