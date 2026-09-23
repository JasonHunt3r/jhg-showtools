import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import ShowToolsCore
import ShowToolsPlayback

/// A strip of rendered frames of the finished picture (slides, transitions
/// and lane images together) above the play bar (Jason, 2026-09-21). The
/// storyline shows the parts; this shows the result.
///
/// It follows the storyline (frames sit over their moments and scroll with
/// the blocks) or shows the whole show across its width. It sits under the
/// picture in the main viewer's column only, so the browser and inspector
/// keep their height (Jason); the divider between picture and strip sizes
/// it: bigger frames each cover more time, so there are fewer. Click a
/// frame to go there. View ▸ Show Frame Strip (⌥⌘F) turns it on and off.
struct FrameStrip: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    /// The storyline's zoom and scroll, to follow it.
    let pps: Double
    let scrollOffset: CGFloat
    let inset: CGFloat
    @Environment(AppModel.self) private var model

    enum Span: String, CaseIterable {
        case storyline, wholeShow
        var title: String { self == .storyline ? "Follow Storyline" : "Whole Show" }
        var icon: String { self == .storyline ? "link" : "arrow.left.and.right" }
    }
    @AppStorage("frameStripSpan") private var span: Span = .storyline
    @State private var frames = FrameCache()

    /// The smallest it gets: the divider can't squeeze it below this. Small:
    /// a thumbnail-sized frame (Jason wanted it to shrink further).
    static let minHeight: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            strip(width: g.size.width, height: g.size.height)
        }
        .frame(minHeight: Self.minHeight, maxHeight: .infinity)
        .clipped()
        .background(Color.black)
    }

    // MARK: Which frames

    struct Slot: Hashable {
        /// The show time the frame shows (the middle of its slot).
        let time: Double
        let x: CGFloat
    }

    /// Frames sit on a grid of fixed times, so scrolling moves them with the
    /// storyline and reuses them, rather than resampling every step.
    private func slots(width: CGFloat, frameW: CGFloat) -> [Slot] {
        let duration = timeline.duration
        guard duration > 0, frameW > 1, width > 1 else { return [] }
        switch span {
        case .storyline:
            let per = Double(frameW) / pps                   // seconds a frame covers
            let firstK = max(0, Int(floor(Double(scrollOffset - inset) / Double(frameW))))
            var out: [Slot] = []
            var k = firstK
            while true {
                let x = inset + CGFloat(k) * frameW - scrollOffset
                let t = (Double(k) + 0.5) * per
                if x >= width || Double(k) * per >= duration { break }
                out.append(Slot(time: min(t, duration - 0.001), x: x))
                k += 1
            }
            return out
        case .wholeShow:
            let track = wholeTrack(width: width)
            let count = max(Int(track.width / frameW), 1)
            let w = track.width / CGFloat(count)
            return (0..<count).map { k in
                Slot(time: (Double(k) + 0.5) * duration / Double(count), x: track.minX + CGFloat(k) * w)
            }
        }
    }

    /// Whole Show's span: the strip's own width. (It lined up with the play
    /// bar while the strip ran the window's width; under the picture it's
    /// narrower than the play bar.)
    private func wholeTrack(width: CGFloat) -> (minX: CGFloat, width: CGFloat) {
        (0, width)
    }

    private func strip(width: CGFloat, height: CGFloat) -> some View {
        let frameW = (height * outputAspect).rounded()
        let track = wholeTrack(width: width)
        let wholeW = span == .wholeShow ? track.width / CGFloat(max(Int(track.width / frameW), 1)) : frameW
        let list = slots(width: width, frameW: frameW)
        let pixels = CGSize(width: frameW * 2, height: height * 2)
        return ZStack(alignment: .topLeading) {
            ForEach(list, id: \.self) { slot in
                Group {
                    if let img = frames.image(at: slot.time, size: pixels) {
                        Image(decorative: img, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(Color.white.opacity(0.06))
                    }
                }
                .frame(width: wholeW - 1, height: height)
                .offset(x: slot.x)
                .onTapGesture {
                    engine.pause()
                    engine.seek(slot.time)
                }
            }
            playheadLine(width: width, frameW: frameW)
            spanMenu
                .padding(4)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .task(id: RenderRequest(show: show, times: list.map(\.time), size: pixels)) {
            try? await Task.sleep(for: .milliseconds(120))    // let a scroll or drag settle
            guard !Task.isCancelled else { return }
            await frames.render(timeline: timeline, show: show, times: list.map(\.time), size: pixels,
                                urls: urls)
        }
    }

    private struct RenderRequest: Equatable {
        let show: Show
        let times: [Double]
        let size: CGSize
    }

    private var urls: [Int64: URL] {
        var out: [Int64: URL] = [:]
        for item in timeline.slides.map(\.item) + timeline.overlays.map(\.item) {
            out[item.id] = model.url(for: item)
        }
        return out
    }

    private func playheadLine(width: CGFloat, frameW: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !engine.isPlaying)) { _ in
            let _ = engine.seekCount
            let t = timeline.wrap(engine.now)
            let track = wholeTrack(width: width)
            let x: CGFloat = span == .storyline
                ? inset + CGFloat(t * pps) - scrollOffset
                : track.minX + CGFloat(t / max(timeline.duration, 0.001)) * track.width
            Rectangle().fill(Color.red).frame(width: 2)
                .offset(x: x - 1)
                .opacity(x >= 0 && x <= width ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private var spanMenu: some View {
        Menu {
            Picker("Frames", selection: $span) {
                ForEach(Span.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: span.icon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
        .help(span == .storyline ? "Frames follow the storyline's zoom and scroll" : "Frames show the whole show")
    }
}

// MARK: - Rendering

/// Rendered frames, cached by time and size, cleared when the show changes.
/// The drawing happens off the main thread, through the same Compositor as
/// the player, from small copies of the photos.
@MainActor
@Observable
final class FrameCache {
    private struct Key: Hashable {
        let time: Int          // milliseconds
        let w: Int, h: Int
    }
    private var images: [Key: CGImage] = [:]
    @ObservationIgnored private var forShow: Show?
    @ObservationIgnored private let renderer = FrameRenderer()

    private func key(_ t: Double, _ size: CGSize) -> Key {
        Key(time: Int((t * 1000).rounded()), w: Int(size.width), h: Int(size.height))
    }

    func image(at t: Double, size: CGSize) -> CGImage? { images[key(t, size)] }

    func render(timeline: ShowTimeline, show: Show, times: [Double], size: CGSize, urls: [Int64: URL]) async {
        if forShow != show {
            images = [:]
            forShow = show
        }
        let missing = times.filter { images[key($0, size)] == nil }
        guard !missing.isEmpty else { return }
        let done = await renderer.render(timeline, times: missing, size: size, urls: urls)
        guard forShow == show else { return }              // edited meanwhile: stale
        for (t, img) in done { images[key(t, size)] = img }
        // Keep it bounded: a few hundred small frames at most.
        if images.count > 600 { images = images.filter { k, _ in times.contains { key($0, size) == k } } }
    }
}

/// Draws frames. An actor, so it runs off the main thread, one batch at a time.
actor FrameRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// Small decoded copies, by file, at the size last asked for.
    private var sources: [Int64: CIImage] = [:]
    private var sourceSize = 0

    func render(_ timeline: ShowTimeline, times: [Double], size: CGSize,
                urls: [Int64: URL]) async -> [(Double, CGImage)] {
        // Twice the frame, for Pan and Zoom and zoom headroom.
        let wanted = Int(max(size.width, size.height) * 2)
        if wanted != sourceSize {
            sources = [:]
            sourceSize = wanted
        }
        var out: [(Double, CGImage)] = []
        for t in times {
            if Task.isCancelled { break }
            let state = timeline.frame(at: t)
            let overlay = timeline.overlay(at: t)
            for item in state.layers.map(\.slide.item) + [overlay?.overlay.item].compactMap({ $0 }) {
                if sources[item.id] == nil, let url = urls[item.id] {
                    sources[item.id] = await Self.decode(url, kind: item.kind, maxPixels: wanted)
                }
            }
            let image = Compositor.compose(state, size: size, overlay: overlay,
                                           overlaySource: { [sources] in sources[$0.overlay.item.id] },
                                           source: { [sources] in sources[$0.slide.item.id] })
            if let cg = context.createCGImage(image, from: CGRect(origin: .zero, size: size)) {
                out.append((t, cg))
            }
        }
        return out
    }

    /// A small copy: photos and animations by ImageIO (an animation's first
    /// frame), video by its first frame.
    private static func decode(_ url: URL, kind: MediaKind, maxPixels: Int) async -> CIImage? {
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
            guard let cg = try? await generator.image(at: .zero).image else { return nil }
            return CIImage(cgImage: cg)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary)
        else { return nil }
        return CIImage(cgImage: cg)
    }
}
