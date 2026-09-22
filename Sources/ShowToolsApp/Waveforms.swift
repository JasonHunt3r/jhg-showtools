import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// Songs' waveforms, read once per file and kept: on disk beside the
/// library (by content hash), and in memory while the app runs.
@MainActor
final class Waveforms {
    static let shared = Waveforms()

    /// `<library>/Cache/Waveforms`, set when a library opens.
    var cacheDir: URL?
    private var byHash: [String: Waveform] = [:]
    private var loading: [String: Task<Waveform?, Never>] = [:]

    func cached(_ item: MediaItem) -> Waveform? { byHash[item.hash] }

    func load(_ item: MediaItem, url: URL) async -> Waveform? {
        if let w = byHash[item.hash] { return w }
        if let t = loading[item.hash] { return await t.value }
        guard let dir = cacheDir else { return nil }
        let hash = item.hash
        let task = Task.detached(priority: .userInitiated) { () -> Waveform? in
            try? Waveform.load(url, hash: hash, cacheDir: dir)
        }
        loading[hash] = task
        let w = await task.value
        loading[hash] = nil
        if let w { byHash[hash] = w }
        return w
    }

    /// A tile for the library grid and the collection list.
    nonisolated static func thumbnail(_ w: Waveform) -> CGImage? {
        let width = 320, height = 180
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.16, green: 0.30, blue: 0.46, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.62, green: 0.82, blue: 1, alpha: 0.9))
        let mid = CGFloat(height) / 2, span = w.duration
        for x in stride(from: 0, to: width, by: 2) {
            let p = w.peak(from: span * Double(x) / Double(width), to: span * Double(x + 2) / Double(width))
            let h = max(1, CGFloat(p) * CGFloat(height) * 0.42)
            ctx.fill(CGRect(x: CGFloat(x), y: mid - h, width: 1.5, height: h * 2))
        }
        return ctx.makeImage()
    }
}

/// A song's waveform across a clip, drawn at the timeline's zoom: one bar
/// per couple of points, each the loudest moment it covers.
struct WaveformView: View {
    let waveform: Waveform
    /// The part of the song the clip plays.
    let inPoint: Double
    let length: Double
    let colour: Color

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, length > 0 else { return }
            let mid = size.height / 2
            let step: CGFloat = 2
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                let t0 = inPoint + length * Double(x / size.width)
                let t1 = inPoint + length * Double((x + step) / size.width)
                let h = max(0.5, CGFloat(waveform.peak(from: t0, to: t1)) * (size.height / 2 - 2))
                path.addRect(CGRect(x: x, y: mid - h, width: step * 0.7, height: h * 2))
                x += step
            }
            ctx.fill(path, with: .color(colour))
        }
    }
}
