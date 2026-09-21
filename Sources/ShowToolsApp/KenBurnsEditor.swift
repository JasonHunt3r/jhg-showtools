import SwiftUI
import ShowToolsCore

/// The shape shows are framed for: the main screen's. (Each monitor gets
/// its own in Phase 5; until then the main screen stands in for all.)
@MainActor
var outputAspect: CGFloat {
    let f = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 9)
    return f.height > 0 ? f.width / f.height : 16 / 9
}

/// Drag the start (green) and end (red) frames on the picture. Drag inside
/// a frame to move it; drag its corner to zoom. Framing uses the same
/// calculation as the renderer, so what's drawn here is what plays.
struct KenBurnsEditor: View {
    let item: MediaItem
    let url: URL?
    let fit: Fit
    let kb: KenBurns
    let commit: (KenBurns) -> Void

    /// The move while a drag is under way; committed (one undo step) on release.
    @State private var live: KenBurns?
    @State private var dragStart: KenBurnsFrame?

    private enum End { case start, end }

    private var imageSize: CGSize { CGSize(width: item.pixelWidth, height: item.pixelHeight) }
    private var outputSize: CGSize { CGSize(width: outputAspect * 1000, height: 1000) }

    var body: some View {
        let current = live ?? kb
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let scale = geo.size.width / imageSize.width
                ZStack(alignment: .topLeading) {
                    ThumbnailView(item: item, url: url)
                        .frame(width: geo.size.width, height: geo.size.height)
                    // Outside both frames is dimmed a little, so the frames read.
                    Color.black.opacity(0.25)
                    frame(.end, current.end, colour: .red, scale: scale)
                    frame(.start, current.start, colour: .green, scale: scale)
                }
                .clipped()
            }
            .aspectRatio(imageSize.width / max(imageSize.height, 1), contentMode: .fit)
            .frame(maxHeight: 260)

            HStack(spacing: 8) {
                Label("Start", systemImage: "square").foregroundStyle(.green)
                Label("End", systemImage: "square").foregroundStyle(.red)
                Spacer()
                Picker("", selection: Binding(get: { current.easing },
                                              set: { var k = current; k.easing = $0; commit(k) })) {
                    Text("Ease").tag(Easing.easeInOut)
                    Text("Linear").tag(Easing.linear)
                }
                .labelsHidden()
                .fixedSize()
            }
            .font(.caption)

            HStack {
                Button("Swap") { commit(KenBurns(start: current.end, end: current.start, easing: current.easing)) }
                    .help("Play the move backwards")
                Button("Reset") {
                    commit(KenBurns(start: .centred, end: KenBurnsFrame(x: 0.5, y: 0.5, zoom: 1.25),
                                    easing: current.easing))
                }
                Spacer()
                Text("zoom \(current.start.zoom, specifier: "%.2f") → \(current.end.zoom, specifier: "%.2f")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
    }

    private func frame(_ end: End, _ f: KenBurnsFrame, colour: Color, scale: CGFloat) -> some View {
        let r = Compositor.viewRegion(imageSize: imageSize, fit: fit, kb: f, outputSize: outputSize)
        let rect = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(colour.opacity(0.08))
                .overlay(Rectangle().strokeBorder(colour, lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    Text(end == .start ? "Start" : "End")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .background(colour)
                        .foregroundStyle(.black)
                }
                .contentShape(Rectangle())
                .gesture(moveGesture(end, scale: scale))
            // Corner handle: zoom.
            Rectangle()
                .fill(colour)
                .frame(width: 10, height: 10)
                .offset(x: rect.width - 10, y: rect.height - 10)
                .gesture(zoomGesture(end, scale: scale))
                .onHover { inside in
                    if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func value(_ end: End) -> KenBurnsFrame {
        let k = live ?? kb
        return end == .start ? k.start : k.end
    }

    private func set(_ end: End, _ f: KenBurnsFrame) {
        var k = live ?? kb
        if end == .start { k.start = f } else { k.end = f }
        live = k
    }

    private func moveGesture(_ end: End, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let origin = dragStart ?? value(end)
                if dragStart == nil { dragStart = origin }
                var f = origin
                f.x = clampCentre(origin.x + g.translation.width / scale / imageSize.width, f, axis: \.width)
                f.y = clampCentre(origin.y + g.translation.height / scale / imageSize.height, f, axis: \.height)
                set(end, f)
            }
            .onEnded { _ in finish() }
    }

    private func zoomGesture(_ end: End, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                let origin = dragStart ?? value(end)
                if dragStart == nil { dragStart = origin }
                // Width of the frame at zoom 1, then the width the drag asks for.
                let base = Compositor.viewRegion(imageSize: imageSize, fit: fit,
                                                 kb: KenBurnsFrame(x: 0.5, y: 0.5, zoom: 1),
                                                 outputSize: outputSize).width
                let startWidth = base / origin.zoom
                let wanted = max(startWidth + g.translation.width / scale, base / 6)
                var f = origin
                f.zoom = min(max(base / wanted, 1), 6)
                f.x = clampCentre(f.x, f, axis: \.width)
                f.y = clampCentre(f.y, f, axis: \.height)
                set(end, f)
            }
            .onEnded { _ in finish() }
    }

    /// Keeps a centre where it actually moves the frame: past the point where
    /// the frame meets the image edge, further dragging would do nothing.
    private func clampCentre(_ v: Double, _ f: KenBurnsFrame, axis: KeyPath<CGSize, CGFloat>) -> Double {
        let region = Compositor.viewRegion(imageSize: imageSize, fit: fit,
                                           kb: KenBurnsFrame(x: 0.5, y: 0.5, zoom: f.zoom),
                                           outputSize: outputSize)
        let half = Double((axis == \CGSize.width ? region.width : region.height) / 2)
        let span = Double(imageSize[keyPath: axis])
        guard half * 2 < span else { return 0.5 }
        return min(max(v, half / span), 1 - half / span)
    }

    private func finish() {
        if let live { commit(live) }
        live = nil
        dragStart = nil
    }
}
