import SwiftUI
import ShowToolsCore

/// Edit Show: the show large in the middle, a transport and a Final
/// Cut-style storyline under it, and the order list down the right.
struct EditShowView: View {
    let show: Show
    let timeline: ShowTimeline
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator
    @Binding var inspectorShown: Bool
    @Environment(AppModel.self) private var model
    @State private var engine: PlaybackEngine?
    @AppStorage("storylineZoom") private var pps: Double = 24

    var body: some View {
        // A ZStack, not a Group: modifiers on a Group apply to each child, so
        // the placeholder's onDisappear would shut down the engine it made way for.
        ZStack {
            if let engine, engine.showID == show.id {
                // The columns sit on top; the transport and storyline run the
                // full width underneath them.
                VSplitView {
                    ShowColumns(
                        inspectorShown: $inspectorShown, model: model,
                        preview: PreviewStage(engine: engine, title: show.name,
                                              selection: $selection, mutate: mutate),
                        list: OrderList(show: show, timeline: timeline, engine: engine,
                                        selection: $selection, mutate: mutate,
                                        toggleInspector: { inspectorShown.toggle() }),
                        inspector: SlideInspector(show: show, timeline: timeline, selection: selection,
                                                  mutate: mutate))
                        .frame(minHeight: 220)
                    VStack(spacing: 0) {
                        TransportRow(engine: engine, pps: $pps, fit: fitStoryline)
                        Divider()
                        StorylineView(show: show, timeline: timeline, engine: engine,
                                      selection: $selection, pps: $pps, mutate: mutate,
                                      openInspector: { inspectorShown = true })
                    }
                    .frame(minHeight: StorylineView.blockHeight + StorylineView.rulerHeight + 80,
                           idealHeight: StorylineView.blockHeight + StorylineView.rulerHeight + 90)
                }
                .onDeleteCommand { SlideActions.remove(selection, selection: $selection, mutate: mutate) }
                .background(shortcuts(engine))
            } else {
                Color.black
            }
        }
        .task(id: show.id) {
            // One engine per show on screen; the old one is let go properly.
            if let old = engine, old.showID != show.id {
                Player.closeWindows(for: old)
                old.shutdown()
            }
            if engine?.showID != show.id {
                let e = PlaybackEngine(showID: show.id, model: model)
                if let first = show.slides.firstIndex(where: { selection.contains($0.id) }) { e.go(to: first) }
                engine = e
            }
        }
        .onDisappear {
            if let engine {
                Player.closeWindows(for: engine)
                engine.shutdown()
            }
            engine = nil
        }
    }

    @State private var visibleWidth: CGFloat = 800

    private func fitStoryline() {
        guard timeline.duration > 0 else { return }
        pps = min(max(Double(visibleWidth - StorylineView.inset * 2 - 40) / timeline.duration, 2), 400)
    }

    /// Keyboard shortcuts with no visible button: Final Cut's J/K/L and zoom.
    private func shortcuts(_ engine: PlaybackEngine) -> some View {
        ZStack {
            Button("") { engine.shuttle(-1) }.keyboardShortcut("j", modifiers: [])
            Button("") { engine.shuttle(0) }.keyboardShortcut("k", modifiers: [])
            Button("") { engine.shuttle(1) }.keyboardShortcut("l", modifiers: [])
            Button("") { pps = min(pps * 1.5, 400) }.keyboardShortcut("=", modifiers: .command)
            Button("") { pps = max(pps / 1.5, 2) }.keyboardShortcut("-", modifiers: .command)
            Button("") { fitStoryline() }.keyboardShortcut("z", modifiers: .shift)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .background(GeometryReader { g in
            Color.clear.onAppear { visibleWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in visibleWidth = w }
        })
    }
}

// MARK: - Preview

/// The show, large, with a livery-style play toggle in the frame and a
/// progress line that drains across each slide.
struct PreviewStage: View {
    let engine: PlaybackEngine
    let title: String
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator
    @State private var hovering = false
    /// The slide whose image is selected in the picture, for its handles.
    @State private var imageSlideID: Int64?
    /// The work area's zoom: 1 fits the picture; below 1 leaves room round
    /// it to see and grab an image that hangs past the frame.
    @AppStorage("workZoom") private var workZoom: Double = 1
    @State private var pinchStart: Double?
    /// The previous slide's last frame over the selected image.
    @AppStorage("onionSkin") private var onionOn = true
    @AppStorage("onionOpacity") private var onionOpacity: Double = 0.5
    /// What the handles edit, when the slide has Rotation on.
    @State private var editTarget: TransformOverlay.Target = .transform

    /// Rotation mode is only offered for a slide with Rotation on.
    private var rotationAvailable: Bool {
        guard let id = imageSlideID else { return false }
        return engine.show.slides.first(where: { $0.id == id })?.settings.rotation?.enabled == true
    }

    private var stage: ShowCanvas.Stage {
        ShowCanvas.Stage(zoom: CGFloat(workZoom), onionSlideID: onionOn ? imageSlideID : nil,
                         onionOpacity: onionOpacity)
    }

    var body: some View {
        ZStack {
            Color.black
            // The canvas fills the stage: it draws the pasteboard round the
            // picture itself (see PlaybackEngine.stageImage).
            ShowCanvasView(engine: engine, stage: stage)
            // Over the whole stage, so handles past the picture's edge show.
            GeometryReader { g in
                TransformOverlay(engine: engine, frame: Self.pictureRect(in: g.size, zoom: CGFloat(workZoom)),
                                 target: rotationAvailable ? editTarget : .transform,
                                 imageSlideID: $imageSlideID, selection: $selection, mutate: mutate)
            }
            // The buttons sit above the handles so they stay clickable.
            Color.clear
                .aspectRatio(outputAspect, contentMode: .fit)
                .overlay(alignment: .bottom) { SlideProgress(engine: engine) }
                .overlay(alignment: .bottomLeading) {
                    Button { engine.togglePlay() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            Text(engine.isPlaying ? "Playing" : "Paused")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .opacity(hovering || !engine.isPlaying ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: hovering)
                }
                .overlay(alignment: .topTrailing) {
                    Button { Player.popOut(engine, title: title) } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .padding(6)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .opacity(hovering ? 1 : 0)
                    .help("Pop out the preview into its own window, e.g. for another screen")
                }
                .overlay(alignment: .topLeading) {
                    workControls
                        .padding(10)
                        .opacity(hovering || imageSlideID != nil || workZoom < 1 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: hovering)
                }
        }
        .onHover { hovering = $0 }
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                let start = pinchStart ?? workZoom
                pinchStart = start
                workZoom = min(max(start * v.magnification, 0.2), 1)
            }
            .onEnded { _ in pinchStart = nil })
        .task {
            // Dev hook: SHOWTOOLS_DEV_IMAGE=1 selects the selected slide's
            // image at launch, so its handles can be screenshotted.
            guard ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_IMAGE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            imageSlideID = selection.first
            // SHOWTOOLS_DEV_IMAGE=rotation opens it in Rotation mode.
            if ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_IMAGE"] == "rotation" { editTarget = .rotation }
        }
    }

    /// Zoom (Fit, or smaller to see past the frame) and the onion skin.
    private var workControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Fit") { workZoom = 1 }
                ForEach([0.75, 0.5, 0.33, 0.25], id: \.self) { z in
                    Button("\(Int(z * 100))%") { workZoom = z }
                }
            } label: {
                Text(workZoom >= 1 ? "Fit" : "\(Int((workZoom * 100).rounded()))%")
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom out to see and grab an image past the frame's edge (or pinch)")

            if rotationAvailable {
                Picker("", selection: $editTarget) {
                    Text("Transform").tag(TransformOverlay.Target.transform)
                    Text("Rotation").tag(TransformOverlay.Target.rotation)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("What the handles on the image edit: its place, or its Rotation (green start, red end)")
            }

            Toggle(isOn: $onionOn) { Image(systemName: "square.on.square.dashed") }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(onionOn ? .white : .white.opacity(0.45))
                .help("Onion skin: with an image selected, show the previous slide's last frame over it")
            if onionOn {
                Slider(value: $onionOpacity, in: 0.1...0.9)
                    .frame(width: 80)
                    .help("Onion skin opacity")
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .foregroundStyle(.white)
        .onChange(of: workZoom) { engine.touch() }
    }

    /// The picture's rect in a stage of `size`: fitted to it, then scaled
    /// by the work area's zoom about the centre. The engine draws with the
    /// same rect (in pixels), so the handles line up with the picture.
    static func pictureRect(in size: CGSize, zoom: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let z = min(max(zoom, 0.05), 1)
        let w = min(size.width, size.height * outputAspect) * z
        let h = w / outputAspect
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

/// A thin line along the bottom of the picture: full at the start of each
/// slide, draining to nothing at its end, bright then dimming — the livery
/// gallery's progress bar.
struct SlideProgress: View {
    let engine: PlaybackEngine

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !engine.isPlaying)) { _ in
            let _ = engine.seekCount
            let tl = engine.timeline
            let t = tl.wrap(engine.now)
            let i = tl.index(at: engine.now)
            let remaining: Double = tl.slides.indices.contains(i)
                ? 1 - min(max((t - tl.slides[i].start) / tl.slides[i].length, 0), 1) : 0
            GeometryReader { g in
                Rectangle()
                    .fill(.white.opacity(engine.isPlaying ? 0.35 + 0.5 * remaining : 0.25))
                    .frame(width: g.size.width * remaining, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Transport

/// CutSim's transport: play, a scrubber across the whole show, the time.
struct TransportRow: View {
    let engine: PlaybackEngine
    @Binding var pps: Double
    let fit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { engine.step(-1) } label: { Image(systemName: "backward.end.fill") }
                .help("Previous slide")
            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").frame(width: 14)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(engine.isPlaying ? "Pause (space)" : "Play (space)")
            Button { engine.step(1) } label: { Image(systemName: "forward.end.fill") }
                .help("Next slide")

            TimelineView(.animation(minimumInterval: 1 / 20, paused: !engine.isPlaying)) { _ in
                let _ = engine.seekCount
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { engine.timeline.wrap(engine.now) },
                        set: { t in
                            if engine.isPlaying { engine.pause() }
                            engine.seek(t)
                        }), in: 0...max(engine.duration, 0.1))
                    Text("\(formatClock(engine.timeline.wrap(engine.now))) / \(formatDuration(engine.duration))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 110, alignment: .trailing)
                }
            }

            if engine.isPlaying && engine.rate != 1 {
                Text(engine.rate > 0 ? "\(Int(engine.rate))×" : "◀\(Int(-engine.rate))×")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Divider().frame(height: 16)
            Button { pps = max(pps / 1.5, 2) } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Zoom out (⌘−)")
            Button { pps = min(pps * 1.5, 400) } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Zoom in (⌘+)")
            Button { fit() } label: { Image(systemName: "arrow.left.and.right.square") }
                .help("Fit the whole show (⇧Z)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

/// m:ss.t — tenths, for scrubbing.
func formatClock(_ s: Double) -> String {
    let t = max(s, 0)
    let m = Int(t) / 60
    return String(format: "%d:%04.1f", m, t - Double(m * 60))
}

// MARK: - Order list

/// The same order as the storyline, as a list of names: drag to reorder.
struct OrderList: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator
    let toggleInspector: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let resolved = Dictionary(timeline.slides.map { ($0.slide.id, $0) }, uniquingKeysWith: { a, _ in a })
        let screen = outputPixelSize
        List(selection: $selection) {
            ForEach(Array(show.slides.enumerated()), id: \.element.id) { i, slide in
                if let item = model.itemsByID[slide.itemID] {
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                        // True proportions here too, in a fixed box.
                        let aspect = CGFloat(item.pixelWidth) / CGFloat(max(item.pixelHeight, 1))
                        ThumbnailView(item: item, url: model.url(for: item))
                            .frame(width: aspect >= 1 ? 40 : 30 * aspect, height: aspect >= 1 ? 40 / aspect : 30)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .frame(width: 40, height: 30)
                            // On the thumbnail, so it costs the name no width.
                            .overlay(alignment: .topTrailing) {
                                if let m = resolved[slide.id]?.peakMagnification(outputSize: screen),
                                   m > ResolvedSlide.softAbove {
                                    SoftBadge(magnification: m)
                                        .font(.system(size: 9))
                                        .shadow(color: .black.opacity(0.7), radius: 1)
                                        .offset(x: 3, y: -3)
                                }
                            }
                        Text(item.fileName)
                            .lineLimit(1).truncationMode(.middle)
                            .fontWeight(i == engine.currentIndex ? .semibold : .regular)
                    }
                    .tag(slide.id)
                }
            }
            .onMove { from, to in
                mutate("Move Slides") { $0.slides.move(fromOffsets: from, toOffset: to) }
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            Button("Duplicate") { SlideActions.duplicate(ids, mutate: mutate) }
            Button("Remove from Show") { SlideActions.remove(ids, selection: $selection, mutate: mutate) }
        } primaryAction: { ids in
            // Double-click: show it, and open the inspector — or close it
            // if it's already open.
            if let id = ids.first { engine.showSlide(id: id) }
            toggleInspector()
        }
        .onChange(of: selection) { _, ids in
            // Picking one slide in the list shows it in the preview.
            if ids.count == 1, let id = ids.first, !engine.isPlaying { engine.showSlide(id: id) }
        }
    }
}
