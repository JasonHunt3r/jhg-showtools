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
    /// Sound samples written, 0 for a silent movie.
    public var soundFrames: AVAudioFramePosition = 0
    /// How many songs went into the mix.
    public var songsMixed: Int = 0
    /// How many video slides put their own sound in the mix (E5b).
    public var videoSlidesMixed: Int = 0

    /// The movie's length in seconds: `frameCount / frameRate`.
    public var duration: Double { frameRate > 0 ? Double(frameCount) / Double(frameRate) : 0 }
    public var hasSound: Bool { soundFrames > 0 }
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

    /// Writes a show's picture track, and nothing else. A silent movie.
    ///
    /// This is `MovieExport.write` with no songs: one place builds the
    /// writer, so the picture-only and the muxed paths can't drift apart.
    /// See it for what the arguments mean and for the threading rule —
    /// **call this off the main thread**.
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
        try MovieExport.write(timeline: timeline, songs: [], to: url, settings: settings,
                              showAspect: showAspect, context: context,
                              overlaySource: overlaySource, progress: progress,
                              isCancelled: isCancelled, source: source)
    }
}
