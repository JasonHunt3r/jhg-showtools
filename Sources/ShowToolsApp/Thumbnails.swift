import SwiftUI
import ImageIO
import AVFoundation
import ShowToolsCore

/// Small previews for the grid and slide list, made on demand and kept in
/// memory. Several hundred items at 320px is a few tens of megabytes.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSNumber, NSImage>()

    func cached(_ id: Int64) -> NSImage? { cache.object(forKey: NSNumber(value: id)) }

    func load(_ item: MediaItem, url: URL) async -> NSImage? {
        if let hit = cached(item.id) { return hit }
        let kind = item.kind
        let cg = await Task.detached(priority: .userInitiated) {
            kind == .video ? await Self.videoFrame(url) : Self.imageThumb(url)
        }.value
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: NSNumber(value: item.id))
        return img
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
        .task(id: item.id) {
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
