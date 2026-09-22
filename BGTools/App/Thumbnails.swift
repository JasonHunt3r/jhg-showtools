import AppKit
import ImageIO
import AVFoundation
import ShowToolsCore
import ShowToolsPlayback

/// Small pictures for the window's pickers, made off the main thread and
/// kept by file path.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private var cache: [String: NSImage] = [:]
    /// Everyone waiting on a thumbnail being made: all are told when it's ready.
    private var waiting: [String: [@MainActor () -> Void]] = [:]

    /// The thumbnail if it's ready; otherwise starts it and calls `ready`.
    func image(for url: URL, kind: MediaKind, ready: @escaping @MainActor () -> Void) -> NSImage? {
        let key = url.path
        if let img = cache[key] { return img }
        guard waiting[key] == nil else {
            waiting[key]?.append(ready)
            return nil
        }
        waiting[key] = [ready]
        // `make` is nonisolated, so the decoding happens off the main thread.
        Task { @MainActor in
            let made = await Self.make(url, kind: kind)
            if let cg = made?.value { cache[key] = NSImage(cgImage: cg, size: .zero) }
            let told = waiting.removeValue(forKey: key) ?? []
            told.forEach { $0() }
        }
        return nil
    }

    @concurrent nonisolated private static func make(_ url: URL, kind: MediaKind) async -> Handoff<CGImage>? {
        if kind == .video {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 320, height: 320)
            return (try? await gen.image(at: .zero).image).map { Handoff(value: $0) }
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 320]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary).map { Handoff(value: $0) }
    }
}
