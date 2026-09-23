import Foundation
import AVFoundation
import CoreImage
import ImageIO

// Video export (plan, `spec/video-export.md`). The media an export draws
// from, loaded synchronously.
//
// The live `MediaProvider` decodes in the background and draws nothing
// until a picture arrives, which is right for a player — a dropped frame
// is better than a stall. An export is the opposite: every frame must be
// the real one, however long it takes. So this loads on the spot and
// caches, and the export loop never sees a nil it should have waited for.

/// Loads a show's pictures for an export. One instance per export: it
/// holds every decoded file until it goes away.
///
/// **Off the main thread**, with the rest of the export.
public final class MovieMedia {
    private let urlFor: (MediaItem) -> URL?
    private let maxPixels: Int

    private struct Animation {
        var frames: [CIImage]
        /// The end time of each frame, cumulative.
        var ends: [Double]
        var total: Double { ends.last ?? 0 }
    }

    private var stills: [Int64: CIImage] = [:]
    private var animations: [Int64: Animation] = [:]
    /// Files that wouldn't decode, so they aren't retried every frame.
    private var failed: Set<Int64> = []

    /// How many video slides were drawn as a held first frame.
    public private(set) var videoSlidesHeld: Set<Int64> = []

    public init(maxPixels: Int = 4096, urlFor: @escaping (MediaItem) -> URL?) {
        self.maxPixels = maxPixels
        self.urlFor = urlFor
    }

    /// A slide's picture at its own local time.
    public func image(for layer: Layer) -> CIImage? {
        let item = layer.slide.item
        switch item.kind {
        case .image:
            return still(item)
        case .animatedImage:
            // As they play: the frame the show's clock is standing on.
            return frame(of: item, at: layer.slide.clipStart + layer.localTime)
        case .video:
            // A v1 export holds a video slide's first frame (settled with
            // Jason, 2026-09-22). E5 gives it its own frames.
            videoSlidesHeld.insert(layer.slide.slide.id)
            return still(item)
        case .audio:
            return nil
        }
    }

    /// The lane's image. Video in the lane isn't supported yet, as in the
    /// live player, so it draws nothing.
    public func image(for overlay: OverlayLayer) -> CIImage? {
        let item = overlay.overlay.item
        switch item.kind {
        case .image: return still(item)
        case .animatedImage: return frame(of: item, at: overlay.localTime)
        case .video, .audio: return nil
        }
    }

    // MARK: - Decoding

    private func still(_ item: MediaItem) -> CIImage? {
        if let hit = stills[item.id] { return hit }
        guard !failed.contains(item.id), let url = urlFor(item) else { return nil }
        let image: CIImage? = item.kind == .video ? Self.firstVideoFrame(url)
                                                  : Self.decodeStill(url, maxPixels: maxPixels)
        guard let image else { failed.insert(item.id); return nil }
        stills[item.id] = image
        return image
    }

    private func frame(of item: MediaItem, at time: Double) -> CIImage? {
        if animations[item.id] == nil {
            guard !failed.contains(item.id), let url = urlFor(item),
                  let a = Self.decodeAnimation(url, maxPixels: maxPixels), !a.frames.isEmpty else {
                failed.insert(item.id)
                return nil
            }
            animations[item.id] = a
        }
        guard let a = animations[item.id], a.total > 0 else { return animations[item.id]?.frames.first }
        // It loops, the way the player runs it.
        let t = time.truncatingRemainder(dividingBy: a.total)
        let i = a.ends.firstIndex { t < $0 } ?? a.frames.count - 1
        return a.frames[min(i, a.frames.count - 1)]
    }

    private static func options(_ maxPixels: Int) -> CFDictionary {
        [kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceCreateThumbnailWithTransform: true,
         kCGImageSourceShouldCacheImmediately: true,
         kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary
    }

    static func decodeStill(_ url: URL, maxPixels: Int) -> CIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options(maxPixels)) else { return nil }
        return CIImage(cgImage: cg)
    }

    /// Every frame and its delay, through `AnimatedFrames.delay` — the same
    /// timing the player and ingest read, so an exported animation runs at
    /// the speed it runs on screen.
    private static func decodeAnimation(_ url: URL, maxPixels: Int) -> Animation? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        var frames: [CIImage] = [], ends: [Double] = []
        var t = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, options(maxPixels)) else { continue }
            frames.append(CIImage(cgImage: cg))
            t += AnimatedFrames.delay(src, i)
            ends.append(t)
        }
        return frames.isEmpty ? nil : Animation(frames: frames, ends: ends)
    }

    static func firstVideoFrame(_ url: URL) -> CIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return CIImage(cgImage: cg)
    }
}
