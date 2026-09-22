import SwiftUI
import ImageIO
import AVFoundation
import ShowToolsCore
import ShowToolsPlayback

/// Small previews for the grid and slide list, made on demand and kept in
/// memory. Several hundred items at 320px is a few tens of megabytes.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSNumber, NSImage>()

    func cached(_ id: Int64) -> NSImage? { cache.object(forKey: NSNumber(value: id)) }

    /// Bumped by `clear()`. A load that was under way when the library
    /// changed finishes against an id the new library uses for another
    /// file, so it checks this and is thrown away.
    private var generation = 0

    /// On switching libraries: ids only mean anything within one.
    func clear() {
        generation += 1
        cache.removeAllObjects()
        strips.removeAll()
        stripLoading.removeAll()
    }

    func load(_ item: MediaItem, url: URL) async -> NSImage? {
        if let hit = cached(item.id) { return hit }
        let kind = item.kind, started = generation
        let cg: CGImage?
        if kind == .audio {
            // A song's tile is its waveform.
            guard let w = await Waveforms.shared.load(item, url: url) else { return nil }
            cg = await Task.detached(priority: .userInitiated) { Waveforms.thumbnail(w) }.value
        } else {
            cg = await Task.detached(priority: .userInitiated) {
                kind == .video ? await Self.videoFrame(url) : Self.imageThumb(url)
            }.value
        }
        guard let cg, generation == started else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: NSNumber(value: item.id))
        return img
    }

    // MARK: Video filmstrip

    static let stripFrames = 12
    private var strips: [Int64: [NSImage]] = [:]
    private var stripLoading: Set<Int64> = []

    /// Evenly spaced frames across a video, for its storyline block. Nil
    /// until they're ready; `onReady` runs when they arrive.
    func strip(_ item: MediaItem, url: URL, onReady: @escaping @MainActor () -> Void) -> [NSImage]? {
        if let s = strips[item.id] { return s }
        guard !stripLoading.contains(item.id) else { return nil }
        stripLoading.insert(item.id)
        let duration = item.duration ?? 0, started = generation
        Task {
            let frames = await Task.detached(priority: .utility) {
                Handoff(value: await Self.videoFrames(url, duration: duration, count: Self.stripFrames))
            }.value.value
            guard generation == started else { return }
            strips[item.id] = frames.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            stripLoading.remove(item.id)
            onReady()
        }
        return nil
    }

    nonisolated static func videoFrames(_ url: URL, duration: Double, count: Int) async -> [CGImage] {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 160)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        var out: [CGImage] = []
        for i in 0..<count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            if let img = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image {
                out.append(img)
            } else if let last = out.last {
                out.append(last)
            }
        }
        return out
    }

    nonisolated static func imageThumb(_ url: URL, maxPixels: Int = 320) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    nonisolated static func videoFrame(_ url: URL) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 320)
        return try? await gen.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
    }
}

struct ThumbnailView: View {
    let item: MediaItem
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .overlay(alignment: .bottomTrailing) { KindBadge(item: item).padding(4) }
        // Keyed on the URL, not just the item's id: a failed load (the
        // file was missing) otherwise never retries after a relink points
        // the same id at a new file, since the id itself never changed.
        .task(id: url) {
            image = Thumbnails.shared.cached(item.id)
            if image == nil, let url { image = await Thumbnails.shared.load(item, url: url) }
        }
    }
}

struct KindBadge: View {
    let item: MediaItem

    var body: some View {
        switch item.kind {
        case .image:
            EmptyView()
        case .animatedImage:
            badge("GIF")
        case .video:
            badge(item.duration.map(formatDuration) ?? "Video", symbol: "video.fill")
        case .audio:
            badge(item.duration.map(formatDuration) ?? "Song", symbol: "music.note")
        }
    }

    private func badge(_ text: String, symbol: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
        .foregroundStyle(.white)
    }
}

func formatDuration(_ s: Double) -> String {
    let total = Int(s.rounded())
    let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

func formatSeconds(_ s: Double) -> String {
    s == s.rounded() ? String(format: "%.0fs", s) : String(format: "%.1fs", s)
}
