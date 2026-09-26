import SwiftUI
import AppKit
import AVFoundation
import ShowToolsCore
import PaneKit

/// The viewer drawer's two views (`spec/plan.md`, "The viewer drawer").
enum ViewerMode: String, CaseIterable {
    /// Every selected file tiled as large as the drawer allows (Aperture's
    /// multi-up), the outlined one being the one last clicked.
    case sideBySide
    /// The outlined file big, the rest as cards behind it with a count:
    /// keeps the picture big while showing it's a group (Jason, 2026-09-26).
    case stack

    var title: String { self == .sideBySide ? "Side by Side" : "Stack" }
    var symbol: String { self == .sideBySide ? "square.grid.2x2" : "square.stack" }
    var other: ViewerMode { self == .sideBySide ? .stack : .sideBySide }
}

/// The selected files, big: the drawer's content over the Library grids and
/// Edit Show's browser. It follows the selection and takes no clicks of its
/// own (v1), apart from the Side by Side / Stack switch in its corner; the
/// grid keeps the keyboard.
struct SelectionViewer: View {
    /// The selection, in the grid's own order.
    let items: [MediaItem]
    /// The outlined one (the one last clicked, or stepped to with ← / →).
    let primary: Int64?
    @Binding var mode: ViewerMode
    let model: AppModel

    static let spacing: CGFloat = 8
    static let inset: CGFloat = 12

    private var outlined: MediaItem? {
        items.first { $0.id == primary } ?? items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Its own strip, so no picture ever sits under the switch.
            HStack {
                Spacer()
                Picker("View", selection: $mode) {
                    ForEach(ViewerMode.allCases, id: \.self) { m in
                        Image(systemName: m.symbol).help(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Side by Side or Stack (⇧Y)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            GeometryReader { geo in
                let box = CGSize(width: max(0, geo.size.width - 2 * Self.inset),
                                 height: max(0, geo.size.height - 2 * Self.inset))
                ZStack {
                    if items.isEmpty {
                        Text("No selection")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else if mode == .stack || items.count == 1 {
                        stack(in: box)
                    } else {
                        sideBySide(in: box)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipped()
    }

    // MARK: Side by Side

    private func sideBySide(in box: CGSize) -> some View {
        let (ids, more) = Viewer.shown(items.map(\.id), primary: outlined?.id)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = ids.compactMap { byID[$0] }
        let frames = Viewer.sideBySide(aspects: shown.map(Self.aspect), in: box, spacing: Self.spacing)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(shown, frames)), id: \.0.id) { item, frame in
                ViewerTile(item: item, url: model.url(for: item), size: frame.size)
                    .frame(width: frame.width, height: frame.height)
                    .overlay {
                        if item.id == outlined?.id {
                            Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                        }
                    }
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if more > 0 { note("+\(more) more") }
        }
    }

    // MARK: Stack

    /// How far each card behind shows past the one in front, and how many
    /// are drawn (the count says how many there really are).
    static let cardStep: CGFloat = 10
    static let cardsDrawn = 3

    private func stack(in box: CGSize) -> some View {
        let top = outlined!
        let behind = min(items.count - 1, Self.cardsDrawn)
        let room = CGFloat(behind) * Self.cardStep
        let frame = Viewer.sideBySide(aspects: [Self.aspect(top)],
                                      in: CGSize(width: max(0, box.width - room), height: max(0, box.height - room)))
            .first ?? .zero
        return ZStack {
            // The cards are the next files in the selection (after the top
            // one, wrapping), dimmed, each with a light edge: real pictures
            // peeking out read as a group; plain grey cards didn't (measured
            // by screenshot, 2026-09-26: invisible on the dark backdrop).
            let order = items.map(\.id)
            let start = order.firstIndex(of: top.id) ?? 0
            ForEach((0..<behind).reversed(), id: \.self) { k in
                let step = CGFloat(k + 1) * Self.cardStep
                let card = items[(start + k + 1) % items.count]
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.5))
                    if let thumb = Thumbnails.shared.cached(card.id) {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .brightness(-0.25 - 0.1 * Double(k))
                .overlay(Rectangle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .offset(x: step, y: -step)
            }
            ViewerTile(item: top, url: model.url(for: top), size: frame.size)
                .frame(width: frame.width, height: frame.height)
                .overlay(alignment: .topLeading) {
                    if items.count > 1 { note("\(items.count)").padding(6) }
                }
                .shadow(radius: items.count > 1 ? 3 : 0)
        }
        .offset(x: -room / 2, y: room / 2)
        .frame(width: box.width, height: box.height)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
    }

    /// Width ÷ height; audio (no picture) is 0, which the layout treats as square.
    static func aspect(_ item: MediaItem) -> CGFloat {
        item.pixelHeight > 0 ? CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight) : 0
    }
}

/// The viewer drawer's grip: the edge handles' pill. Drawn in the middle
/// of the dark strip under a grid's bar, which is the drawer's only handle
/// (Jason, 2026-09-26: the bar above has controls to click).
struct GripPill: View {
    var body: some View {
        Capsule()
            .fill(Color(nsColor: .secondaryLabelColor).opacity(0.7))
            .frame(width: 40, height: 3)
            .allowsHitTesting(false)
    }
}

/// A slim dark strip with the pill, as the drawer's handle where there's
/// no sort strip to be it (Edit Show's browser).
struct DrawerGripStrip: View {
    let controller: PaneController
    let split: String

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 12)   // PaneKit's edge handles' thickness
            .overlay { GripPill() }
            .paneHandle(controller, split: split)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// One file in the viewer: a still decoded at about the size it's drawn,
/// an animated GIF animating, a video playing (muted, looping — Jason:
/// as it'll move in a show, no sound surprises), or an audio file's name.
struct ViewerTile: View {
    let item: MediaItem
    let url: URL?
    let size: CGSize

    var body: some View {
        switch item.kind {
        case .image:
            ViewerStill(item: item, url: url, size: size)
        case .animatedImage:
            if let url { AnimatedImageView(url: url) } else { missing }
        case .video:
            if let url { LoopingVideoView(url: url) } else { missing }
        case .audio:
            VStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 36))
                Text(item.fileName).font(.callout).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
        }
    }

    private var missing: some View {
        Rectangle().fill(.quaternary)
    }
}

/// A still, sharp at its drawn size: the grid's small thumbnail at once,
/// then a decode at the drawn size in pixels (rounded up to a step, so a
/// drawer being dragged doesn't decode at every size in between).
struct ViewerStill: View {
    let item: MediaItem
    let url: URL?
    let size: CGSize
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    private var pixels: Int { ViewerImages.step(Int(max(size.width, size.height) * scale)) }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: "\(url?.path ?? "")|\(pixels)") {
            if image == nil { image = Thumbnails.shared.cached(item.id) }
            guard let url, pixels > 0 else { return }
            if let big = await ViewerImages.shared.load(item.id, url: url, pixels: pixels) { image = big }
        }
    }
}

/// Stills decoded for the viewer, by file and size step. A few at drawer
/// size is a few tens of megabytes; NSCache lets them go under pressure.
@MainActor
final class ViewerImages {
    static let shared = ViewerImages()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 48 }

    /// Sizes go up in steps of 512 px, so resizing reuses a decode.
    nonisolated static func step(_ pixels: Int) -> Int { max(512, (pixels + 511) / 512 * 512) }

    func load(_ id: Int64, url: URL, pixels: Int) async -> NSImage? {
        let key = "\(url.path)|\(pixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let cg = await Task.detached(priority: .userInitiated) {
            Thumbnails.imageThumb(url, maxPixels: pixels)
        }.value
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }
}

/// An animated GIF, animating (AppKit's own image view plays it).
struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = NSImage(contentsOf: url)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            v.image = NSImage(contentsOf: url)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator { var url: URL; init(url: URL) { self.url = url } }
}

/// A video, muted and looping, fitted to its frame.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.play(url)
        return v
    }

    func updateNSView(_ v: PlayerView, context: Context) {
        if v.url != url { v.play(url) }
    }

    static func dismantleNSView(_ v: PlayerView, coordinator: ()) { v.stop() }

    final class PlayerView: NSView {
        private(set) var url: URL?
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            player.isMuted = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("made in code") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func play(_ url: URL) {
            self.url = url
            looper?.disableLooping()
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        func stop() {
            looper?.disableLooping()
            looper = nil
            player.pause()
            player.removeAllItems()
        }
    }
}
