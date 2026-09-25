import SwiftUI
import PaneKit
import ShowToolsCore
import ShowToolsPlayback

/// Edit Show: the show large in the middle, a transport and a Final
/// Cut-style storyline under it, and the order list down the right.
struct EditShowView: View {
    let show: Show
    let timeline: ShowTimeline
    /// The show's editing state (`spec/windows.md`, `ShowSession`): the
    /// slide selection (shared with Edit Slides, via `ShowView`), the
    /// engine and the lane's own selections — `@Bindable` below so
    /// `$session.selection` and the rest read exactly as the old
    /// `@State`/`@Binding` properties did.
    let session: ShowSession
    let mutate: ShowMutator
    @Binding var inspectorShown: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @AppStorage("storylineZoom") private var pps: Double = 24

    var body: some View {
        @Bindable var session = session
        // A ZStack, not a Group: modifiers on a Group apply to each child, so
        // the placeholder's onDisappear would shut down the engine it made way for.
        ZStack {
            if let engine = session.engine, engine.showID == show.id {
                // The three columns: PaneKit's job now, in place of
                // ColumnsSplitView (spec/panekit.md, step 3). The timeline
                // pane — the transport and storyline — isn't part of this
                // tree any more: it moved to `model.mainPanes`, full width
                // under the Library pane too, not just these columns
                // (`EditShowTimelinePane`, `spec/panekit.md`, step 5's
                // follow-up, 2026-09-25); `MainView` renders it.
                PaneLayoutView(controller: model.editShowColumns, content: [
                    "preview": AnyView(PreviewStage(engine: engine, title: show.name,
                                                    selection: $session.selection,
                                                    selectedTransition: $session.selectedTransition,
                                                    selectedOverlay: $session.selectedOverlay, mutate: mutate,
                                                    show: show, timeline: timeline, pps: pps,
                                                    storylineOffset: session.storylineOffset,
                                                    inspectorShown: $inspectorShown).environment(model)),
                    "list": AnyView(CollectionBrowser(show: show, timeline: timeline, engine: engine,
                                                      mutate: mutate, inspectorShown: $inspectorShown,
                                                      selection: $session.selection,
                                                      selectedOverlay: $session.selectedOverlay,
                                                      selectedSong: $session.selectedSong)
                        .environment(model)),
                    "inspector": AnyView(SlideInspector(show: show, timeline: timeline, selection: session.selection,
                                                        mutate: mutate, close: { inspectorShown = false },
                                                        engine: engine).environment(model)),
                ])
                .onAppear { model.editShowColumns.setOpen("columns.near", inspectorShown) }
                .onChange(of: inspectorShown) { _, shown in model.editShowColumns.setOpen("columns.near", shown) }
                .onChange(of: model.editShowColumns.isOpen("columns.near")) { _, shown in
                    if shown != inspectorShown { inspectorShown = shown }
                }
                .onChange(of: session.selection) { _, s in
                    if !s.isEmpty {
                        session.selectedTransition = nil; session.selectedOverlay = nil
                        session.selectedSong = nil; session.selectedMarkers = []
                    }
                }
                .onChange(of: session.selectedOverlay) { _, o in
                    if o != nil { session.selectedTransition = nil; session.selectedSong = nil; session.selectedMarkers = [] }
                }
                .onChange(of: session.selectedSong) { _, o in if o != nil { session.selectedMarkers = [] } }
                .onChange(of: session.selectedTransition) { _, o in if o != nil { session.selectedMarkers = [] } }
                .onChange(of: session.selectedMarkers) { _, m in
                    // Markers are selected on their own, so Delete knows what it's for.
                    if !m.isEmpty {
                        session.selection = []; session.selectedTransition = nil
                        session.selectedOverlay = nil; session.selectedSong = nil
                    }
                }
                .task {
                    // Dev hook: SHOWTOOLS_DEV_TRANSITION=<slideIndex> selects the
                    // transition into that slide, so its controls can be screenshotted.
                    // SHOWTOOLS_DEV_OVERLAY=<n> selects the lane's nth image.
                    if let v = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_OVERLAY"], let n = Int(v),
                       show.overlays.indices.contains(n) {
                        try? await Task.sleep(for: .seconds(1.2))
                        let c = show.overlays[n]
                        session.selection = []
                        session.selectedOverlay = c.id
                        engine.pause()
                        engine.seek(c.start + min(c.fadeIn, c.length / 2) + 0.5)
                        return
                    }
                    guard let v = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_TRANSITION"],
                          let i = Int(v), show.slides.indices.contains(i) else { return }
                    try? await Task.sleep(for: .seconds(1.2))
                    session.selection = []
                    session.selectedTransition = show.slides[i].id
                    if let r = timeline.slides.first(where: { $0.slide.id == show.slides[i].id }) {
                        engine.pause()
                        engine.seek(r.start)
                    }
                }
            } else {
                Color.black
            }
        }
        .task(id: show.id) {
            // One engine per show on screen; the old one is let go properly.
            if let old = session.engine, old.showID != show.id {
                Player.closeWindows(for: old)
                old.shutdown()
            }
            if session.engine?.showID != show.id {
                let e = PlaybackEngine(showID: show.id, model: model)
                if let first = show.slides.firstIndex(where: { session.selection.contains($0.id) }) { e.go(to: first) }
                session.engine = e
            }
        }
        .onDisappear {
            if let engine = session.engine {
                Player.closeWindows(for: engine)
                engine.shutdown()
            }
            session.engine = nil
        }
    }
}

// MARK: - Preview

/// The show, large, with a livery-style play toggle in the frame and a
/// progress line that drains across each slide.
struct PreviewStage: View {
    let engine: PlaybackEngine
    let title: String
    @Binding var selection: Set<Int64>
    @Binding var selectedTransition: Int64?
    @Binding var selectedOverlay: UUID?
    let mutate: ShowMutator
    /// For the frame strip under the picture: the show, and the storyline's
    /// zoom and scroll to follow.
    let show: Show
    let timeline: ShowTimeline
    let pps: Double
    let storylineOffset: CGFloat
    /// So the quick-settings menu's Custom… can open it (`spec/conventions.md`
    /// §3, item 4): "Custom… opens the inspector on that setting."
    @Binding var inspectorShown: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @AppStorage("frameStripShown") private var frameStripShown = true
    @AppStorage("frameStripHeight") private var stripHeight: Double = 90
    @State private var stripDragStart: Double?
    /// The drag's own live value, drawn but not saved until release —
    /// matches PaneKit's own dividers, which only draw live and commit
    /// once, on release, rather than writing `stripHeight` (`@AppStorage`,
    /// straight to UserDefaults) on every pixel of the drag.
    @State private var liveStripHeight: Double?
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
    /// Shared with `SlideProgress` and the Settings window: one key.
    @AppStorage("showSlideProgress") private var showSlideProgress = true

    /// Rotation mode is only offered for a slide with Rotation on.
    private var rotationAvailable: Bool {
        guard let id = imageSlideID else { return false }
        return engine.show.slides.first(where: { $0.id == id })?.settings.rotation?.enabled == true
    }

    private var stage: ShowCanvas.Stage {
        ShowCanvas.Stage(zoom: CGFloat(workZoom), onionSlideID: onionOn ? imageSlideID : nil,
                         onionOpacity: onionOpacity, aspect: outputAspect)
    }

    /// The picture, with the frame strip below it in this column only (not
    /// under the browser and inspector), split by one bar that sizes it.
    var body: some View {
        if frameStripShown {
            GeometryReader { g in
                // The picture keeps at least 120 points; the strip at least 20.
                let most = max(Double(g.size.height) - 120 - Double(Self.barHeight), Double(FrameStrip.minHeight))
                let h = CGFloat(min(max(liveStripHeight ?? stripHeight, Double(FrameStrip.minHeight)), most))
                VStack(spacing: 0) {
                    picture
                    stripBar(most: most)
                    FrameStrip(show: show, timeline: timeline, engine: engine, pps: pps,
                               scrollOffset: storylineOffset, inset: StorylineView.inset)
                        .frame(height: h)
                }
                // Item 8's real cause: the bar sits between two views whose
                // sizes the drag itself changes, so the bar's own on-screen
                // position moves mid-drag. A plain (`.local`) DragGesture's
                // translation is measured against the bar's own frame, so
                // each `onChanged` partly "catches up" to the cursor before
                // the next one reads its delta — a feedback loop, measured
                // to converge on roughly half the real distance (a probe
                // showed the gesture's own final translation topping out at
                // half the actual mouse travel, confirmed at two different
                // drag lengths). Anchoring to this column, which doesn't
                // move, fixes it — the same reason `StorylineView`'s own
                // drags (range ends, markers, row handles) are all named
                // coordinate spaces, never `.local`.
                .coordinateSpace(name: "previewColumn")
            }
        } else {
            picture
        }
    }

    /// The bar between picture and strip: a slim line to look at, in a
    /// taller band to grab (the system split line was too fiddly, Jason).
    static let barHeight: CGFloat = 12

    private func stripBar(most: Double) -> some View {
        ZStack {
            Color.black
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 5)
            Capsule()
                .fill(Color.secondary.opacity(0.7))
                .frame(width: 40, height: 3)
        }
        .frame(height: Self.barHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            // Set, not pushed: a push without its pop leaves the cursor stuck.
            if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("previewColumn"))
            .onChanged { g in
                let start = stripDragStart ?? stripHeight
                stripDragStart = start
                liveStripHeight = min(max(start - Double(g.translation.height), Double(FrameStrip.minHeight)), most)
            }
            .onEnded { g in
                stripDragStart = nil
                if let live = liveStripHeight { stripHeight = live }
                liveStripHeight = nil
            })
        .help("Drag to size the frame strip")
    }

    private var picture: some View {
        ZStack {
            Color.black
            // The canvas fills the stage: it draws the pasteboard round the
            // picture itself (see PlaybackEngine.stageImage).
            ShowCanvasView(engine: engine, stage: stage)
            // Over the whole stage, so handles past the picture's edge show.
            GeometryReader { g in
                TransformOverlay(engine: engine, frame: Self.pictureRect(in: g.size, zoom: CGFloat(workZoom)),
                                 target: rotationAvailable ? editTarget : .transform,
                                 imageSlideID: $imageSlideID, selectedOverlay: $selectedOverlay,
                                 selection: $selection, mutate: mutate)
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
                .overlay(alignment: .top) {
                    // The saved show, which SwiftUI observes (the engine's copy
                    // isn't), so the bar follows edits made elsewhere: the lane's
                    // level line, undo.
                    if let id = selectedOverlay, let clip = show.overlays.first(where: { $0.id == id }) {
                        overlayControls(clip)
                            .padding(.top, 48)
                    } else if let id = selectedTransition,
                       let r = engine.timeline.slides.first(where: { $0.slide.id == id }) {
                        transitionControls(r)
                            .padding(.top, 48)
                    }
                }
                .overlay(alignment: .topLeading) {
                    workControls
                        .padding(10)
                        .opacity(hovering || imageSlideID != nil || workZoom < 1 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: hovering)
                }
        }
        // Which menu depends on `imageSlideID`, set only by clicking the
        // image itself (`TransformOverlay`) — an approximation of "where
        // you right-clicked" rather than the real thing (settled,
        // 2026-09-24: right-clicking empty space right after selecting an
        // image can still show the image's menu; real click-location
        // plumbing is a later pass if this bites in practice).
        .contextMenu {
            if let id = imageSlideID { slideImageMenu(id) } else { pasteboardMenu }
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

    // MARK: - Right-click menus (spec/conventions.md §3, item 4)

    /// "A slide's image," settled 2026-09-24: Open in Slide Editor, Show in
    /// Library, the quick-settings submenus, Reset Transform, Rotation
    /// Handles on/off, Slide Progress on/off.
    @ViewBuilder private func slideImageMenu(_ id: Int64) -> some View {
        Button("Open in Slide Editor") {
            SlideEditorWindow.show(slideID: id, show: show, model: model, mutate: mutate, undoManager: undoManager)
        }
        Button("Show in Library") {
            guard let itemID = show.slides.first(where: { $0.id == id })?.itemID else { return }
            showInLibrary(itemID, model: model, undoManager: undoManager)
        }
        Divider()
        QuickSettingsMenu.length([id], mutate: mutate) { selection = [id]; inspectorShown = true }
        QuickSettingsMenu.transition([id], mutate: mutate)
        QuickSettingsMenu.panAndZoom([id], mutate: mutate)
        Divider()
        Button("Reset Transform") {
            mutate("Reset Transform") { s in
                guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return }
                s.slides[i].settings.transform = nil
            }
        }
        Button(rotationEnabled(id) ? "Rotation Handles Off" : "Rotation Handles On") { toggleRotation(id) }
        Divider()
        Toggle("Slide Progress", isOn: $showSlideProgress)
    }

    /// "The pasteboard (the grey round the picture)," settled 2026-09-24.
    @ViewBuilder private var pasteboardMenu: some View {
        Menu("Work Zoom") {
            Button("Fit") { workZoom = 1 }
            Button("75%") { workZoom = 0.75 }
            Button("50%") { workZoom = 0.5 }
        }
        Toggle("Onion Skin", isOn: $onionOn)
        Divider()
        Button("Pop Out Viewer") { Player.popOut(engine, title: title) }
    }

    private func rotationEnabled(_ id: Int64) -> Bool {
        show.slides.first(where: { $0.id == id })?.settings.rotation?.enabled == true
    }

    private func toggleRotation(_ id: Int64) {
        mutate(rotationEnabled(id) ? "Turn Off Rotation" : "Turn On Rotation") { s in
            guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return }
            var r = s.slides[i].settings.rotation ?? Rotation()
            r.enabled.toggle()
            s.slides[i].settings.rotation = r
        }
    }


    /// The selected transition's settings, over the picture. Its timing is
    /// set by dragging it in the lane; this sets the rest.
    private func transitionControls(_ r: ResolvedSlide) -> some View {
        let id = r.slide.id
        let t = r.transitionIn
        let own = r.slide.settings.transition != nil
        func set(_ action: String, _ new: ShowToolsCore.Transition?) {
            mutate(action) { s in
                guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return }
                s.slides[i].settings.transition = new
            }
        }
        return HStack(spacing: 10) {
            TransitionPicker(transition: t) { new in
                // A new duration keeps the window where it was relative to
                // the join: centred stays centred.
                var new = new
                if new.duration != t.duration, t.duration > 0 { new.lead = t.lead * new.duration / t.duration }
                set("Change Transition", new)
            }
            Text(t.lead == 0 ? "starts at the join"
                 : t.lead >= t.duration ? "ends at the join"
                 : "\(formatSeconds(t.lead)) before the join")
                .foregroundStyle(.white.opacity(0.7))
            if own {
                Button("Use Show Default") { set("Use Default Transition", nil) }
                    .help("Go back to the show's default transition")
            }
            Button("Remove") {
                set("Remove Transition", ShowToolsCore.Transition(style: .cut, duration: 0))
                selectedTransition = nil
            }
            .help("Make this join a cut (Delete)")
            Button { selectedTransition = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Done")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.7), in: Capsule())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    /// The selected lane image's settings, over the picture. Its place and
    /// size are the handles' (and the arrow keys'); its time is the lane's.
    private func overlayControls(_ clip: OverlayClip) -> some View {
        let id = clip.id
        func set(_ action: String, _ change: @escaping (inout OverlayClip) -> Void) {
            mutate(action) { s in
                guard let i = s.overlays.firstIndex(where: { $0.id == id }) else { return }
                change(&s.overlays[i])
            }
        }
        return HStack(spacing: 10) {
            BarSlider(title: "Opacity", value: clip.opacity) { v in set("Change Opacity") { $0.opacity = v } }
            Picker("", selection: Binding(get: { clip.blend }, set: { b in set("Change Blend Mode") { $0.blend = b } })) {
                ForEach(BlendMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            .help("Blend mode")
            Picker("", selection: Binding(get: { clip.fit }, set: { f in set("Change Fit") { $0.fit = f } })) {
                ForEach(Fit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            .help("Fit")
            HStack(spacing: 3) {
                Text("Fade")
                SecondsField(value: clip.fadeIn) { v in set("Change Fade In") { $0.fadeIn = min(v, clip.length) } }
                    .help("Fade in")
                SecondsField(value: clip.fadeOut) { v in set("Change Fade Out") { $0.fadeOut = min(v, clip.length) } }
                    .help("Fade out")
            }
            Button("Remove") {
                mutate("Remove Image") { $0.overlays.removeAll { $0.id == id } }
                selectedOverlay = nil
            }
            .help("Take this image out of the lane (Delete)")
            Button { selectedOverlay = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .help("Done")
        }
        // Its natural width: squeezed, SwiftUI drops the labels first.
        .fixedSize()
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.7), in: Capsule())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
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
        ShowCanvas.pictureRect(in: size, zoom: zoom, aspect: outputAspect)
    }
}

/// A thin line along the bottom of the picture: empty at the start of each
/// slide, filling left to right through it, bright then dimming when paused
/// (Jason, work order 2026-09-24, reversed from an earlier drain-to-nothing
/// version). `showSlideProgress` hides it app-wide — the setting and the
/// viewer's own Slide Progress menu item share the one key.
struct SlideProgress: View {
    let engine: PlaybackEngine
    @AppStorage("showSlideProgress") private var shown = true

    var body: some View {
        if shown {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !engine.isPlaying)) { _ in
                let _ = engine.seekCount
                let tl = engine.timeline
                let t = tl.wrap(engine.now)
                let i = tl.index(at: engine.now)
                let progress: Double = tl.slides.indices.contains(i)
                    ? min(max((t - tl.slides[i].start) / tl.slides[i].length, 0), 1) : 0
                GeometryReader { g in
                    Rectangle()
                        .fill(.white.opacity(engine.isPlaying ? 0.35 + 0.5 * progress : 0.25))
                        .frame(width: g.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Transport

/// CutSim's transport: play, a scrubber across the whole show, the time.
struct TransportRow: View {
    let engine: PlaybackEngine
    /// The saved show, for its editing state (the engine's copy isn't observed).
    let show: Show
    @Binding var pps: Double
    let fit: () -> Void
    /// W7: the range button's plain click (with no range, acts like
    /// ⌥⌘-click), ⌥⌘-click and ⇧⌥⌘-click.
    let setRangeToView: () -> Void
    let setRangeToWholeShow: () -> Void
    let clearRange: () -> Void
    let toggleRangeLock: () -> Void
    @AppStorage("snapping") private var snapping = true

    /// A switch in the show's editing state, saved with no undo step.
    private func editor(_ key: WritableKeyPath<ShowEditorState, Bool>) -> Binding<Bool> {
        Binding(get: { show.editor[keyPath: key] },
                set: { v in engine.updateEditor { $0[keyPath: key] = v } })
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { engine.step(-1) } label: { Image(systemName: "backward.end.fill") }
                .help("Previous slide")
            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").frame(width: 14)
            }
            // Space is handled by EditShowView's SingleKeys, not a shortcut,
            // so it can still be typed into text fields.
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
Group {
                Toggle(isOn: $snapping) { Image(systemName: "arrow.left.and.line.vertical.and.arrow.right") }
                    .help(snapping ? "Snapping is on: edges land on markers (N)" : "Snapping is off (N)")
                rangeButton
                Toggle(isOn: editor(\.rangeLines)) { Image(systemName: "arrow.down.to.line.compact") }
                    .help("The range's ends as lines through every row (double-click an end for its own)")
                Toggle(isOn: editor(\.markerLines)) { Image(systemName: "flag") }
                    .help("The markers as lines through every row (double-click a marker for its own)")
                Toggle(isOn: editor(\.loopPlayback)) { Image(systemName: "repeat") }
                .help("Loop playback: the range, or the whole show (⌘L)")
            }
            // Icons that light up when on, not checkboxes.
            .toggleStyle(.button)
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

    /// W7: a plain click shows or hides the range as before, except with no
    /// range set, where it acts like ⌥⌘-click (Jason, 2026-09-24) and makes
    /// one from the view. ⌥⌘-click always sets it to the view; ⇧⌥⌘-click to
    /// the whole show. Both modifier clicks also sit on the right-click,
    /// since a modifier click can't be seen, alongside the lock — set from
    /// here or from either end on the ruler (one lock for the whole range).
    private var rangeButton: some View {
        let hasRange = show.editor.rangeIn != nil || show.editor.rangeOut != nil
        let on = hasRange && show.editor.rangeOn
        return Button {
            let mods = NSEvent.modifierFlags
            if mods.isSuperset(of: [.command, .option, .shift]) { setRangeToWholeShow() }
            else if mods.isSuperset(of: [.command, .option]) { setRangeToView() }
            else if !hasRange { setRangeToView() }
            else { engine.updateEditor { $0.rangeOn.toggle() } }
        } label: {
            Image(systemName: "timeline.selection")
                .symbolVariant(on ? .fill : .none)
                .foregroundStyle(on ? Color.accentColor : Color.primary)
        }
        .contextMenu {
            Button("Set Range to View") { setRangeToView() }
            Button("Set Range to Whole Show") { setRangeToWholeShow() }
            Toggle("Lock Range", isOn: Binding(get: { show.editor.rangeLocked },
                                                set: { _ in toggleRangeLock() }))
            if hasRange {
                Divider()
                Button("Clear Range") { clearRange() }
            }
        }
        .help(hasRange ? "Show or hide the range (⌥⌘-click: set to view; ⇧⌥⌘-click: set to whole show; ⌥X clears it)"
                       : "Set the range to the view (⌥⌘-click), or to the whole show (⇧⌥⌘-click)")
    }
}

/// m:ss.t — tenths, for scrubbing.
func formatClock(_ s: Double) -> String {
    let t = max(s, 0)
    let m = Int(t) / 60
    return String(format: "%d:%04.1f", m, t - Double(m * 60))
}


// MARK: - Single-key commands

/// Keys with no modifier (or only Shift) for the window this sits in,
/// taken before AppKit dispatches them, except while text is being edited:
/// then the key goes to the text. `handle` returns true for a key it used.
/// Held keys don't repeat the command (a held space would flicker between
/// play and pause).
struct SingleKeys: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle }

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?
        /// The key last used, so its auto-repeats are swallowed too.
        private var held: UInt16?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                let swallow = MainActor.assumeIsolated { self?.swallows(event) ?? false }
                return swallow ? nil : event
            }
        }

        /// True for a key this used (or a repeat of it): AppKit never sees it.
        private func swallows(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, window.attachedSheet == nil,
                  !(window.firstResponder is NSText) else { return false }
            if event.type == .keyUp {
                if event.keyCode == held { held = nil }
                return false
            }
            if event.isARepeat { return event.keyCode == held }
            guard handle?(event) == true else { return false }
            held = event.keyCode
            return true
        }

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

extension NSEvent {
    /// The modifiers a shortcut cares about: not Caps Lock, not the flags
    /// the arrow and keypad keys carry.
    var plainModifiers: NSEvent.ModifierFlags {
        modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
    }
}
