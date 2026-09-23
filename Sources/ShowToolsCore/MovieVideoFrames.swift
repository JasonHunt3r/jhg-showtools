import Foundation
import AVFoundation
import CoreImage

// Video export (plan, `spec/video-export.md`). E5: a video slide's own
// frames.
//
// An `AVAssetImageGenerator` call per exported frame is far too slow (it
// seeks and decodes from the nearest keyframe every time). A video slide
// is instead read straight through with an `AVAssetReader`, pulled forward
// in step with the writer's clock — the export asks for times that only go
// forward, so the decoder never has to seek.
//
// It seeks exactly twice over a slide's life: once at the start, and again
// each time the slide loops (`VideoSlideTiming` decides that, not this).

/// One video slide's frames, read in order.
///
/// **One per slide**, not per file: the same video used twice in a show is
/// at two different moments at once, and during a transition both are
/// wanted in the same exported frame.
///
/// **Not thread-safe** — it belongs to the export that made it.
public final class MovieVideoFrames {
    private let asset: AVURLAsset
    private let track: AVAssetTrack?
    private let orientation: CGAffineTransform

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// The frame last decoded, and the time it starts at.
    private var current: (image: CIImage, time: Double)?
    /// Where the reader was started, so a backwards ask can be spotted.
    private var readerStart: Double = 0
    private var ended = false

    public let duration: Double
    /// How many times the reader had to start again: once at the beginning,
    /// then once per loop. A jump backwards that isn't a loop would show up
    /// here as well.
    public private(set) var seeks = 0

    public init?(url: URL) {
        asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        self.track = track
        duration = asset.duration.seconds.isFinite ? asset.duration.seconds : 0
        // The track's own rotation, put back at the origin — the same thing
        // `VideoSlot.oriented` does for the player.
        orientation = track.preferredTransform
    }

    /// The frame showing at `time` seconds into the file, or nil if the
    /// file has nothing there.
    ///
    /// Asking for times that go forward is cheap; asking for one that goes
    /// backwards starts the reader again, which is what a looping slide
    /// needs and what everything else should avoid.
    public func frame(at time: Double) -> CIImage? {
        let wanted = max(time, 0)

        // Backwards, or nothing started yet: begin again from there.
        if reader == nil || wanted < readerStart - 0.001
            || (current.map { wanted < $0.time - 0.001 } ?? false) {
            start(at: wanted)
        }

        // Forward: take frames until the next one is past the moment asked
        // for, so what's left is the frame that covers it.
        while !ended {
            // A frame decoded on an earlier call comes first. Pulling a new
            // sample while one is held would throw that one away — which
            // lost every frame that began just before the moment asked for.
            if let p = pending {
                guard p.time <= wanted else { break }
                current = p
                pending = nil
                continue
            }
            guard let sample = output?.copyNextSampleBuffer() else {
                ended = true
                break
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let at = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let image = oriented(CIImage(cvPixelBuffer: buffer))
            // Past the moment wanted: keep it for next time rather than
            // throwing it away, but don't show it yet. With nothing to show
            // at all, the first frame that arrives is the best there is.
            if at > wanted, current != nil {
                pending = (image, at)
                break
            }
            current = (image, at)
        }
        return current?.image
    }

    /// A frame decoded before its moment came.
    private var pending: (image: CIImage, time: Double)?

    private func start(at time: Double) {
        reader?.cancelReading()
        current = nil
        pending = nil
        ended = false
        seeks += 1
        readerStart = time
        guard let track, let r = try? AVAssetReader(asset: asset) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else { return }
        r.add(out)
        // From a shade before the moment wanted, because reading starts at
        // the keyframe at or before `start` and the first sample handed
        // back may already be past it.
        r.timeRange = CMTimeRange(start: CMTime(seconds: max(time - 0.001, 0), preferredTimescale: 600),
                                  duration: .positiveInfinity)
        guard r.startReading() else { return }
        reader = r
        output = out
    }

    private func oriented(_ image: CIImage) -> CIImage {
        guard orientation != .identity else { return image }
        let t = image.transformed(by: orientation)
        return t.transformed(by: .init(translationX: -t.extent.minX, y: -t.extent.minY))
    }

    deinit { reader?.cancelReading() }
}
