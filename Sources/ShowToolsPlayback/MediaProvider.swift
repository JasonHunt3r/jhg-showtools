import AppKit
import AVFoundation
import CoreImage
import ImageIO
import ShowToolsCore

/// Carries a value across an isolation boundary. Used for immutable
/// CoreGraphics images decoded off the main thread.
public struct Handoff<T>: @unchecked Sendable {
    public let value: T
    public init(value: T) { self.value = value }
}

/// Decoded media for the slides around the playhead.
///
/// Stills and animation frames are decoded in the background at roughly
/// screen size and kept only for the slides near the playhead, so a
/// several-hundred-slide show costs a handful of images of memory. Video
/// plays through AVPlayer, kept in step with the show clock.
@MainActor
public final class MediaProvider {
    private let urlFor: (MediaItem) -> URL?
    private let maxPixels: Int

    private struct Animation {
        let frames: [CIImage]
        /// End time of each frame, cumulative.
        let ends: [Double]
        var total: Double { ends.last ?? 0 }
    }

    private var stills: [Int64: CIImage] = [:]
    private var animations: [Int64: Animation] = [:]
    private var loading: Set<Int64> = []
    private var videos: [Int64: VideoSlot] = [:]   // keyed by slide id: each use plays on its own
    /// Called when newly decoded media arrives, so an idle view redraws.
    public var onChange: (() -> Void)?
    /// Videos play without their sound (BGTools' desktop, unless its sound
    /// switch is on). Takes effect on videos playing now, too.
    public var muteVideo = false {
        didSet { videos.values.forEach { $0.muted = muteVideo } }
    }

    public init(maxPixels: Int, urlFor: @escaping (MediaItem) -> URL?) {
        self.maxPixels = maxPixels
        self.urlFor = urlFor
    }

    public func isReady(_ slide: ResolvedSlide) -> Bool {
        switch slide.item.kind {
        case .image: stills[slide.item.id] != nil
        case .animatedImage: animations[slide.item.id] != nil
        case .video: true
        // A song is never a slide (the app keeps it out), so never waited for.
        case .audio: true
        }
    }

    public func image(for layer: Layer, playing: Bool) -> CIImage? {
        let item = layer.slide.item
        switch item.kind {
        case .image:
            if let img = stills[item.id] { return img }
            request(item)
            return nil
        case .animatedImage:
            return animationFrame(item, at: layer.slide.clipStart + layer.localTime)
        case .video:
            guard let slot = slot(for: layer.slide) else { return nil }
            // The slide's own sound follows its level line. One envelope in
            // Core, applied here for the live player; an export applies the
            // same curve to the audio it pulls out itself.
            slot.volume = Float(layer.slide.audio.level(at: layer.localTime))
            return slot.image(localTime: layer.localTime, slideLength: layer.slide.length,
                              clipStart: layer.slide.clipStart, playing: playing)
        case .audio:
            return nil
        }
    }

    /// The lane's image. Stills and animations; video in the lane isn't
    /// supported yet, so it draws nothing.
    public func image(for overlay: OverlayLayer) -> CIImage? {
        let item = overlay.overlay.item
        switch item.kind {
        case .image:
            if let img = stills[item.id] { return img }
            request(item)
            return nil
        case .animatedImage:
            return animationFrame(item, at: overlay.localTime)
        case .video, .audio:
            return nil
        }
    }

    private func animationFrame(_ item: MediaItem, at time: Double) -> CIImage? {
        guard let a = animations[item.id], a.total > 0 else { request(item); return nil }
        let t = time.truncatingRemainder(dividingBy: a.total)
        var lo = 0, hi = a.ends.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if a.ends[mid] > t { hi = mid } else { lo = mid + 1 }
        }
        return a.frames[lo]
    }

    /// Loads what's about to be needed and drops what's far away. `alsoKeep`
    /// is the lane's images near the playhead.
    public func prepare(around index: Int, in timeline: ShowTimeline, visible: [Layer], alsoKeep: [MediaItem] = []) {
        guard !timeline.slides.isEmpty else { return }
        let n = timeline.slides.count
        let window = (-1...2).map { (index + $0 + n) % n }
        let wanted = Set(window.map { timeline.slides[$0].item.id } + alsoKeep.map(\.id))
        for i in window { request(timeline.slides[i].item) }
        for item in alsoKeep { request(item) }

        stills = stills.filter { wanted.contains($0.key) }
        animations = animations.filter { wanted.contains($0.key) }

        // Video: keep the visible ones and pre-roll the next.
        var keepVideo = Set(visible.map(\.slide.slide.id))
        let next = timeline.slides[(index + 1) % n]
        if next.item.kind == .video {
            keepVideo.insert(next.slide.id)
            _ = slot(for: next)
        }
        for (id, v) in videos where !keepVideo.contains(id) {
            v.stop()
            videos[id] = nil
        }
    }

    public func pauseAllVideo() { videos.values.forEach { $0.pause() } }

    public func stopAll() {
        videos.values.forEach { $0.stop() }
        videos = [:]
    }

    private func slot(for slide: ResolvedSlide) -> VideoSlot? {
        if let v = videos[slide.slide.id] { return v }
        guard let url = urlFor(slide.item) else { return nil }
        let v = VideoSlot(url: url, duration: slide.item.duration ?? 0)
        v.muted = muteVideo
        // Never start at full volume: a slide is silent until its line says
        // otherwise, and a frame's worth of original audio would be heard.
        v.volume = Float(slide.audio.level(at: 0))
        videos[slide.slide.id] = v
        return v
    }

    private func request(_ item: MediaItem) {
        guard item.kind != .video, !loading.contains(item.id),
              stills[item.id] == nil, animations[item.id] == nil,
              let url = urlFor(item) else { return }
        loading.insert(item.id)
        let maxPixels = maxPixels, kind = item.kind, id = item.id
        Task.detached(priority: .userInitiated) {
            let decoded = Self.decode(url, animated: kind == .animatedImage, maxPixels: maxPixels)
            await MainActor.run {
                self.loading.remove(id)
                guard let (frames, delays) = decoded?.value, !frames.isEmpty else { return }
                let images = frames.map { CIImage(cgImage: $0) }
                if kind == .animatedImage {
                    var t = 0.0
                    let ends = delays.map { t += $0; return t }
                    self.animations[id] = Animation(frames: images, ends: ends)
                } else {
                    self.stills[id] = images[0]
                }
                self.onChange?()
            }
        }
    }

    nonisolated private static func decode(_ url: URL, animated: Bool,
                                           maxPixels: Int) -> Handoff<([CGImage], [Double])>? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        let count = animated ? CGImageSourceGetCount(src) : 1
        var frames: [CGImage] = [], delays: [Double] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateThumbnailAtIndex(src, i, opts as CFDictionary) else { continue }
            frames.append(img)
            delays.append(AnimatedFrames.delay(src, i))
        }
        return Handoff(value: (frames, delays))
    }
}

/// One video slide's player, slaved to the show clock.
///
/// The show clock is the authority. The player is left to run on its own
/// while it keeps up, and is re-seeked only when it drifts, so playback
/// stays smooth rather than stuttering through constant corrections.
@MainActor
public final class VideoSlot {
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let duration: Double
    private var transform: CGAffineTransform = .identity
    private var last: CIImage?
    private var seeking = false
    public var muted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }
    /// The slide's own level at this moment (spec/video-audio.md). Set each
    /// frame from the slide's curve; `muted` is separate, and BGTools still
    /// uses it to silence the lot.
    public var volume: Float {
        get { player.volume }
        set { if player.volume != newValue { player.volume = newValue } }
    }

    public init(url: URL, duration: Double) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.duration = duration

        Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let t = try? await track.load(.preferredTransform) else { return }
            self?.transform = t
        }
    }

    /// A video plays once from its clip start and holds its last frame —
    /// through the transition out of it, too. It loops (back to the clip
    /// start) only when its slide is longer than what's left of the clip.
    public func image(localTime: Double, slideLength: Double, clipStart: Double, playing: Bool) -> CIImage? {
        let lastFrame = max(duration - 0.04, 0)
        let span = max(duration - clipStart, 0.04)
        let loops = slideLength > span + 0.1
        let target = duration <= 0 ? localTime
            : loops && localTime < slideLength ? clipStart + localTime.truncatingRemainder(dividingBy: span)
            : min(clipStart + localTime, lastFrame)
        let holding = localTime >= (loops ? slideLength : span - 0.04)
        let current = player.currentTime().seconds

        if !seeking {
            if playing && !holding {
                if player.rate == 0 || abs(current - target) > 0.25 {
                    seek(to: target, exact: false) { $0.player.play() }
                }
            } else {
                if player.rate != 0 { player.pause() }
                if abs(current - target) > 0.04 { seek(to: target, exact: true) { _ in } }
            }
        }

        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            last = oriented(CIImage(cvPixelBuffer: pb))
        } else if !playing || last == nil {
            // Paused or just seeked: take whatever frame is current.
            let now = player.currentTime()
            if let pb = output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) {
                last = oriented(CIImage(cvPixelBuffer: pb))
            }
        }
        return last
    }

    private func seek(to t: Double, exact: Bool, then: @escaping @MainActor (VideoSlot) -> Void) {
        seeking = true
        let tol: CMTime = exact ? .zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                    toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seeking = false
                then(self)
            }
        }
    }

    /// Applies the track's rotation and puts the result back at the origin.
    private func oriented(_ img: CIImage) -> CIImage {
        guard transform != .identity else { return img }
        let t = img.transformed(by: transform)
        return t.transformed(by: .init(translationX: -t.extent.minX, y: -t.extent.minY))
    }

    public func pause() { player.pause() }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
