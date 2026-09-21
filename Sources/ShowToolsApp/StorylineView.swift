import SwiftUI
import ShowToolsCore

/// The show as a Final Cut-style storyline: one block per slide, as wide as
/// the slide is long, sitting end to end.
///
/// - Magnetic: dragging a block (or a selection of them) reorders, and the
///   rest close up around it. No gaps, ever.
/// - Trim: drag a block's right edge to change its length; what follows
///   shifts along.
/// - The ruler and the playhead share the engine's clock.
struct StorylineView: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    @Binding var selection: Set<Int64>
    /// Points per second: the zoom.
    @Binding var pps: Double
    let mutate: ShowMutator
    @Environment(AppModel.self) private var model

    static let blockHeight: CGFloat = 64
    static let rulerHeight: CGFloat = 22
    static let inset: CGFloat = 12

    private struct Moving {
        var ids: Set<Int64>
        /// Where the pointer grabbed the group, from the group's left edge.
        var grab: CGFloat
        var pointerX: CGFloat
        var target: Int
    }
    @State private var moving: Moving?
    @State private var trimming: (id: Int64, length: Double)?
    @State private var magnifyBase: Double?

    // MARK: Layout

    private struct Placed: Identifiable {
        let slide: ResolvedSlide
        let x: CGFloat
        let width: CGFloat
        var id: Int64 { slide.slide.id }
    }

    /// Lengths with any trim in progress applied.
    private func length(_ r: ResolvedSlide) -> Double {
        if let t = trimming, t.id == r.slide.id { return t.length }
        return r.length
    }

    /// Blocks in the order they'd sit if the drag in progress were dropped:
    /// the moving group pulled out and reinserted at its target.
    private func layout() -> (placed: [Placed], group: [Placed]) {
        var order = timeline.slides
        var group: [ResolvedSlide] = []
        if let m = moving {
            group = order.filter { m.ids.contains($0.slide.id) }
            order.removeAll { m.ids.contains($0.slide.id) }
            order.insert(contentsOf: group, at: min(m.target, order.count))
        }
        var x = Self.inset
        var placed: [Placed] = []
        for r in order {
            let w = CGFloat(length(r) * pps)
            placed.append(Placed(slide: r, x: x, width: w))
            x += w
        }
        return (placed, placed.filter { p in group.contains { $0.slide.id == p.id } })
    }

    private var contentWidth: CGFloat {
        CGFloat(timeline.slides.reduce(0) { $0 + length($1) } * pps) + Self.inset * 2 + 200
    }

    // MARK: Body

    var body: some View {
        let (placed, group) = layout()
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    RulerView(duration: timeline.duration, pps: pps, inset: Self.inset)
                        .frame(width: contentWidth, height: Self.rulerHeight)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture)
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: contentWidth, height: Self.blockHeight + 14)
                        ForEach(placed) { p in
                            let isMoving = moving?.ids.contains(p.id) == true
                            block(p)
                                .opacity(isMoving ? 0.25 : 1)
                                .offset(x: p.x, y: 12)
                                .id(p.id)
                        }
                        transitionMarkers(placed)
                        // The group being dragged follows the pointer.
                        if let m = moving, let first = group.first {
                            let groupWidth = group.reduce(0) { $0 + $1.width }
                            HStack(spacing: 0) {
                                ForEach(group) { p in block(p).frame(width: p.width) }
                            }
                            .frame(width: groupWidth, alignment: .leading)
                            .shadow(radius: 6)
                            .offset(x: m.pointerX - m.grab, y: 6)
                            .allowsHitTesting(false)
                            .id("dragging-\(first.id)")
                        }
                    }
                    .animation(.snappy(duration: 0.18), value: moving?.target)
                }
                .overlay(alignment: .topLeading) { Playhead(engine: engine, timeline: timeline, pps: pps, inset: Self.inset) }
                .coordinateSpace(name: "storyline")
                .padding(.vertical, 6)
            }
            .onChange(of: engine.currentIndex) { _, i in
                // Keep the playing slide in view.
                guard engine.isPlaying, timeline.slides.indices.contains(i) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(timeline.slides[i].slide.id, anchor: .center) }
            }
        }
        .gesture(MagnifyGesture()
            .onChanged { v in
                if magnifyBase == nil { magnifyBase = pps }
                pps = min(max((magnifyBase ?? pps) * v.magnification, 2), 400)
            }
            .onEnded { _ in magnifyBase = nil })
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: Blocks

    private func block(_ p: Placed) -> some View {
        let selected = selection.contains(p.id)
        return StoryBlock(slide: p.slide, item: p.slide.item, url: model.url(for: p.slide.item),
                          width: p.width, height: Self.blockHeight, pps: pps,
                          length: length(p.slide), selected: selected)
            .frame(width: p.width, height: Self.blockHeight)
            .contentShape(Rectangle())
            .onTapGesture { click(p.id) }
            .gesture(moveGesture(p))
            .overlay(alignment: .trailing) { trimHandle(p) }
            .modifier(HoverInfo(slide: p.slide, length: length(p.slide)))
            .contextMenu {
                let ids = selection.contains(p.id) ? selection : [p.id]
                Button("Duplicate") { SlideActions.duplicate(ids, mutate: mutate) }
                Button("Remove from Show") { SlideActions.remove(ids, selection: $selection, mutate: mutate) }
            }
    }

    /// Finder-style: plain click selects one, ⌘ toggles, ⇧ extends. The
    /// preview jumps to the slide and pauses, as a thumbnail click does in
    /// the livery gallery.
    private func click(_ id: Int64) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if mods.contains(.shift), let anchor = timeline.slides.firstIndex(where: { selection.contains($0.slide.id) }),
                  let j = timeline.slides.firstIndex(where: { $0.slide.id == id }) {
            selection.formUnion(timeline.slides[min(anchor, j)...max(anchor, j)].map(\.slide.id))
        } else {
            selection = [id]
        }
        engine.showSlide(id: id)
    }

    private func moveGesture(_ p: Placed) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("storyline"))
            .onChanged { g in
                if moving == nil {
                    // Dragging an unselected block moves just it.
                    if !selection.contains(p.id) { selection = [p.id] }
                    let ids = selection
                    let groupStart = layout().placed.first { ids.contains($0.id) }?.x ?? p.x
                    moving = Moving(ids: ids, grab: g.startLocation.x - groupStart,
                                    pointerX: g.location.x, target: 0)
                }
                moving?.pointerX = g.location.x
                moving?.target = targetIndex()
            }
            .onEnded { _ in
                if let m = moving {
                    let before = timeline.slides.map(\.slide.id)
                    var rest = before.filter { !m.ids.contains($0) }
                    rest.insert(contentsOf: before.filter { m.ids.contains($0) }, at: min(m.target, rest.count))
                    if rest != before { SlideActions.move(m.ids, toIndexAmongOthers: m.target, mutate: mutate) }
                }
                moving = nil
            }
    }

    /// Where the dragged group's left edge falls among the other blocks:
    /// past a block's midpoint, it goes after that block.
    private func targetIndex() -> Int {
        guard let m = moving else { return 0 }
        let left = m.pointerX - m.grab
        var x = Self.inset
        var i = 0
        for r in timeline.slides where !m.ids.contains(r.slide.id) {
            let w = CGFloat(length(r) * pps)
            if left < x + w / 2 { return i }
            x += w
            i += 1
        }
        return i
    }

    private func trimHandle(_ p: Placed) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("storyline"))
                    .onChanged { g in
                        let raw = p.slide.length + Double(g.translation.width) / pps
                        trimming = (p.id, max(0.5, (raw * 10).rounded() / 10))
                    }
                    .onEnded { _ in
                        if let t = trimming, abs(t.length - p.slide.length) > 0.001 {
                            mutate("Change Length") { s in
                                if let i = s.slides.firstIndex(where: { $0.id == t.id }) {
                                    s.slides[i].settings.length = .seconds(t.length)
                                }
                            }
                        }
                        trimming = nil
                    })
            .help("Drag to change the slide's length")
    }

    /// A marker on each cut, as wide as the transition into the next slide.
    private func transitionMarkers(_ placed: [Placed]) -> some View {
        ForEach(placed) { p in
            let d = p.slide.transitionIn.duration
            // Slide 1's transition only happens when a loop wraps round; a
            // marker at 0:00 would read as a transition from nothing.
            if d > 0, p.slide.index > 0, moving == nil {
                let w = max(CGFloat(d * pps), 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.85))
                    .overlay(
                        Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                            .font(.system(size: 7))
                            .foregroundStyle(.black.opacity(0.7))
                            .opacity(w > 14 ? 1 : 0))
                    .frame(width: w, height: 10)
                    .offset(x: p.x, y: 0)
                    .help("\(p.slide.transitionIn.style.title) · \(formatSeconds(d))")
                    .onTapGesture { selection = [p.id] }
            }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                if engine.isPlaying { engine.pause() }
                let t = max(0, Double(g.location.x - Self.inset) / pps)
                engine.seek(min(t, max(timeline.duration - 0.001, 0)))
            }
    }
}

// MARK: - One block

struct StoryBlock: View {
    let slide: ResolvedSlide
    let item: MediaItem
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let pps: Double
    let length: Double
    let selected: Bool

    private var tint: Color {
        switch item.kind {
        case .image: Color(red: 0.30, green: 0.34, blue: 0.62)
        case .animatedImage: Color(red: 0.20, green: 0.52, blue: 0.52)
        case .video: Color(red: 0.22, green: 0.42, blue: 0.70)
        }
    }

    var body: some View {
        let thumbH = height - 8
        let aspect = CGFloat(item.pixelWidth) / CGFloat(max(item.pixelHeight, 1))
        let thumbW = thumbH * aspect
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.55))
            if item.kind == .video, let url {
                VideoStrip(item: item, url: url, height: thumbH, tileWidth: thumbW, width: width - 8,
                           pps: pps, length: length)
                    .padding(.leading, 4)
            } else {
                HStack(spacing: 6) {
                    // True proportions: portrait is tall and narrow, landscape wide.
                    ThumbnailView(item: item, url: url)
                        .frame(width: thumbW, height: thumbH)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(width: min(thumbW, max(width - 8, 0)), alignment: .leading)
                        .clipped()
                    if width - thumbW > 50 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName).lineLimit(1).truncationMode(.middle)
                            Text(formatSeconds(length)).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .frame(width: max(width, 1), height: height, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : .black.opacity(0.45), lineWidth: selected ? 3 : 1))
    }
}

/// Frames across a video block, each at the moment it sits over.
struct VideoStrip: View {
    let item: MediaItem
    let url: URL
    let height: CGFloat
    let tileWidth: CGFloat
    let width: CGFloat
    let pps: Double
    let length: Double
    @State private var frames: [NSImage]?

    var body: some View {
        HStack(spacing: 0) {
            if let frames, !frames.isEmpty, tileWidth > 0 {
                let count = max(1, Int((width / tileWidth).rounded(.up)))
                let duration = max(item.duration ?? length, 0.01)
                ForEach(0..<count, id: \.self) { i in
                    let t = Double(CGFloat(i) * tileWidth) / pps
                    // Past the clip's end the video holds its last frame.
                    let f = min(Int(min(t, duration) / duration * Double(frames.count)), frames.count - 1)
                    Image(nsImage: frames[f]).resizable()
                        .frame(width: tileWidth, height: height)
                }
            }
        }
        .frame(width: max(width, 0), height: height, alignment: .leading)
        .clipped()
        .onAppear {
            frames = Thumbnails.shared.strip(item, url: url) {
                frames = Thumbnails.shared.strip(item, url: url) {}
            }
        }
    }
}

/// Slide info after the pointer rests on a block for two seconds.
struct HoverInfo: ViewModifier {
    let slide: ResolvedSlide
    let length: Double
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    pending = Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .popover(isPresented: $shown, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(slide.index + 1). \(slide.item.fileName)").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        GridRow { Text("Starts").foregroundStyle(.secondary); Text(formatDuration(slide.start)) }
                        GridRow { Text("Length").foregroundStyle(.secondary); Text(formatSeconds(length)) }
                        GridRow {
                            Text("Transition in").foregroundStyle(.secondary)
                            Text(slide.transitionIn.style == .cut ? "Cut"
                                 : "\(slide.transitionIn.style.title), \(formatSeconds(slide.transitionIn.duration))")
                        }
                        GridRow {
                            Text("Ken Burns").foregroundStyle(.secondary)
                            Text(slide.kenBurns == nil ? "Off"
                                 : String(format: "zoom %.2f → %.2f", slide.kenBurns!.start.zoom, slide.kenBurns!.end.zoom))
                        }
                        GridRow { Text("Fit").foregroundStyle(.secondary); Text(slide.fit.title) }
                        GridRow {
                            Text("Image").foregroundStyle(.secondary)
                            Text("\(slide.item.pixelWidth) × \(slide.item.pixelHeight) · \(orientation)")
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
            }
    }

    private var orientation: String {
        let w = slide.item.pixelWidth, h = slide.item.pixelHeight
        return w > h ? "landscape" : w < h ? "portrait" : "square"
    }
}

// MARK: - Ruler and playhead

struct RulerView: View {
    let duration: Double
    let pps: Double
    let inset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            // A labelled tick at least ~80pt apart, on a round number of seconds.
            let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]
            let major = steps.first { $0 * pps >= 80 } ?? 1200
            let minor = major / 5
            var t = 0.0
            while t <= duration + major {
                let x = inset + CGFloat(t * pps)
                let isMajor = abs((t / major).rounded() * major - t) < 1e-6
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x, y: size.height - (isMajor ? 10 : 4)))
                ctx.stroke(p, with: .color(.secondary), lineWidth: 1)
                if isMajor {
                    ctx.draw(Text(formatDuration(t)).font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                }
                t += minor
            }
        }
    }
}

struct Playhead: View {
    let engine: PlaybackEngine
    let timeline: ShowTimeline
    let pps: Double
    let inset: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !engine.isPlaying)) { _ in
            let _ = engine.seekCount
            let x = inset + CGFloat(timeline.wrap(engine.now) * pps)
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Rectangle().fill(.red).frame(width: 2)
            }
            .frame(width: 12)
            .offset(x: x - 6)
            .allowsHitTesting(false)
        }
    }
}
