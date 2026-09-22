import SwiftUI
import MetalKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ShowToolsCore

/// The show clock. Slides never keep their own timers: everything asks this
/// what time it is.
@MainActor
public final class PlaybackClock {
    public private(set) var playing = false
    /// 1 = normal; 2, 4… from pressing L again; negative plays backwards (J).
    public private(set) var rate: Double = 1
    private var base: Double = 0
    private var anchor: CFTimeInterval = 0
    /// While music plays at normal speed, the seconds since `base` come from
    /// the sound card instead of the system clock (see `MusicPlayer`). Set
    /// right after a play or seek, so it always counts from `base`.
    public var external: (() -> Double?)?

    public var now: Double {
        guard playing else { return base }
        if rate == 1, let e = external?() { return base + e }
        return base + (CACurrentMediaTime() - anchor) * rate
    }

    public func play(rate: Double? = nil) {
        if playing { base = now }
        anchor = CACurrentMediaTime()
        if let rate { self.rate = rate }
        playing = true
    }

    public func pause() {
        guard playing else { return }
        base = now
        playing = false
    }

    public func seek(_ t: Double) {
        base = t
        anchor = CACurrentMediaTime()
    }
}

/// One show being played: its timeline, clock and media, and the drawing.
///
/// Any number of views can show the same engine — the Edit Show preview and
/// its popped-out window draw the same frame from the same clock.
@MainActor
@Observable
public final class PlaybackEngine {
    public let showID: Int64
    @ObservationIgnored private weak var model: (any ShowSource)?
    @ObservationIgnored public private(set) var show: Show
    @ObservationIgnored public private(set) var timeline: ShowTimeline

    // Observed a few times a second, for controls — never per frame.
    public private(set) var isPlaying = false
    public private(set) var rate: Double = 1
    public private(set) var currentIndex = 0
    public private(set) var duration: Double = 0
    /// Bumped whenever the timeline is rebuilt, so views can re-read it.
    public private(set) var revision = 0
    /// Bumped on every seek, so a paused playhead redraws where it landed.
    public private(set) var seekCount = 0

    // The range and loop playback live in the show's editing state
    // (`Show.editor`), saved with it but not undone. Views read them from
    // the saved show, which SwiftUI observes; the engine's copy follows
    // at once when they're changed here.

    @ObservationIgnored public let clock = PlaybackClock()
    @ObservationIgnored private let music = MusicPlayer()
    /// Which pass of a looping show the music was started for: at the next
    /// pass it starts again from the top.
    @ObservationIgnored private var musicPass = 0
    @ObservationIgnored public let media: MediaProvider
    @ObservationIgnored private let device: MTLDevice
    @ObservationIgnored private let queue: MTLCommandQueue
    @ObservationIgnored private let ci: CIContext
    @ObservationIgnored private var ticker: Timer?
    /// Last moment something visible changed. While paused, views stop
    /// drawing shortly after it, so an idle preview costs nothing.
    @ObservationIgnored private var lastChange: CFTimeInterval = CACurrentMediaTime()
    /// The clock waits for the first slide's media, so a show never opens on black.
    @ObservationIgnored private var waitingToStart = false
    /// True while a handle drag or a run of nudges is drawn before it's
    /// saved. The saved show mustn't replace it until the edit is committed.
    @ObservationIgnored public private(set) var isEditingLive = false

    public init(showID: Int64, model: any ShowSource) {
        self.showID = showID
        self.model = model
        show = model.show(showID) ?? Show(id: showID, name: "")
        timeline = model.timeline(for: show)
        duration = timeline.duration
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        ci = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        // Decode at the size of the largest screen, with headroom for Ken Burns zoom.
        let largest = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2560
        media = MediaProvider(maxPixels: Int(min(largest * 1.25, 8192)), urlFor: { [weak model] in model?.url(for: $0) })
        media.onChange = { [weak self] in self?.touch() }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        music.onReset = { [weak self] in self?.syncMusic() }
    }

    /// Stop the timer and release video. The engine can't be used afterwards.
    public func shutdown() {
        ticker?.invalidate()
        ticker = nil
        clock.pause()
        syncMusic()
        media.stopAll()
    }

    public var now: Double { clock.now }

    public func touch() { lastChange = CACurrentMediaTime() }

    // MARK: Keeping up with edits

    private func tick() {
        if !isEditingLive, let latest = model?.show(showID), latest != show { reload(latest) }
        keepInLoop()
        let t = clock.now
        // A show that doesn't loop stops at its end (or its start, in reverse).
        if clock.playing, !timeline.loops, timeline.duration > 0 {
            if t >= timeline.duration { clock.pause(); clock.seek(timeline.duration - 0.001); syncMusic() }
            else if t < 0 { clock.pause(); clock.seek(0); syncMusic() }
        }
        // A looping show's music starts again with each pass.
        // (Checked whether or not any is sounding: the rest of a pass can be silent.)
        if clock.playing, clock.rate == 1, !show.music.isEmpty, timeline.loops,
           pass(clock.now) != musicPass { syncMusic() }
        let i = timeline.frame(at: clock.now).currentIndex ?? 0
        if i != currentIndex { currentIndex = i }
        let playing = clock.playing || waitingToStart
        if playing != isPlaying { isPlaying = playing }
        if !playing, listening != nil {
            listening = nil
            onListenEnded?()
        }
        if clock.rate != rate { rate = clock.rate }
    }

    /// Edits made while playing take effect at once; the playhead stays on
    /// the same slide, the same distance into it.
    private func reload(_ latest: Show) {
        let keep = timeline.frame(at: clock.now).currentIndex
        let keptID = keep.map { timeline.slides[$0].slide.id }
        let into = keep.map { clock.now - timeline.slides[$0].start } ?? 0
        let before = clock.now, musicBefore = show.music
        show = latest
        timeline = model?.timeline(for: latest) ?? timeline
        duration = timeline.duration
        revision += 1
        if let keptID, let s = timeline.slides.first(where: { $0.slide.id == keptID }) {
            clock.seek(s.start + max(0, min(into, s.length)))
        }
        // The music follows if the songs changed, or the playhead moved to
        // stay on its slide.
        if clock.playing, show.music != musicBefore || abs(clock.now - before) > 0.02 { syncMusic() }
        touch()
    }

    /// Takes up the source's show now and plays it from the top: for a
    /// different show, where keeping the place (as an edit does) would land
    /// somewhere arbitrary.
    public func restartWithLatest() {
        if let latest = model?.show(showID), latest != show { reload(latest) }
        seek(0)
    }

    /// Draws `edited` in place of the saved show, for a live edit that
    /// doesn't change timing (a Transform). Call `endLiveEdit` once it's
    /// committed, or abandoned.
    public func showLiveEdit(_ edited: Show) {
        isEditingLive = true
        show = edited
        timeline = model?.timeline(for: edited) ?? timeline
        touch()
    }

    /// Back to the saved show: the next tick picks it up.
    public func endLiveEdit() {
        guard isEditingLive else { return }
        isEditingLive = false
        tick()
        touch()
    }

    // MARK: Controls

    public func play() {
        if !timeline.loops, clock.now >= timeline.duration - 0.01 { clock.seek(0) }
        // Looping a range from outside it starts at its beginning.
        if show.editor.loopPlayback, let r = range, !r.contains(timeline.wrap(clock.now)) { clock.seek(r.lowerBound) }
        if let first = timeline.frame(at: clock.now).layers.last?.slide, !media.isReady(first) {
            waitingToStart = true
            media.prepare(around: first.index, in: timeline, visible: [])
        } else {
            clock.play(rate: 1)
            syncMusic()
        }
        touch()
        tick()
    }

    public func pause() {
        waitingToStart = false
        clock.pause()
        syncMusic()
        media.pauseAllVideo()
        touch()
        tick()
    }

    public func togglePlay() { clock.playing || waitingToStart ? pause() : play() }

    /// Final Cut's J/K/L: L plays, again doubles; J the same backwards; K stops.
    public func shuttle(_ direction: Int) {
        waitingToStart = false
        if direction == 0 { pause(); return }
        let current = clock.playing ? clock.rate : 0
        let next: Double = (current * Double(direction) > 0) ? min(abs(current) * 2, 8) * Double(direction)
                                                             : Double(direction)
        if next != 1 { media.pauseAllVideo() }
        clock.play(rate: next)
        syncMusic()
        touch()
        tick()
    }

    public func seek(_ t: Double) {
        clock.seek(t)
        syncMusic()
        seekCount += 1
        touch()
        tick()
    }

    /// Next/previous land with the slide fully on screen when paused, and
    /// at the start of its transition when playing (so the transition plays).
    public func step(_ delta: Int) {
        guard !timeline.isEmpty else { return }
        let n = timeline.slides.count
        let now = clock.now
        var i = timeline.index(at: now)
        // "Previous" first returns to the start of the current slide.
        if delta < 0, timeline.wrap(now) - timeline.settledTime(of: i) > 1.5 {
            go(to: i)
            return
        }
        i += delta
        if timeline.loops { i = (i % n + n) % n } else { i = min(max(i, 0), n - 1) }
        go(to: i)
    }

    public func go(to index: Int) {
        guard timeline.slides.indices.contains(index) else { return }
        // Stay within the current loop pass so wrapping transitions stay right.
        let passStart = timeline.loops && timeline.duration > 0
            ? (clock.now / timeline.duration).rounded(.down) * timeline.duration : 0
        let s = timeline.slides[index]
        seek(passStart + (clock.playing ? s.visibleStart : timeline.settledTime(of: index)))
    }

    /// Show a particular slide, fully on screen, and pause there.
    public func showSlide(id: Int64) {
        guard let i = timeline.slides.firstIndex(where: { $0.slide.id == id }) else { return }
        pause()
        seek(timeline.settledTime(of: i))
    }

    // MARK: Range and loop playback

    /// The in-to-out span, when it's on and set. With only one end set, the
    /// other is the show's start or end, as in Final Cut.
    public var range: ClosedRange<Double>? { Self.range(of: show.editor, duration: duration) }

    public static func range(of e: ShowEditorState, duration: Double) -> ClosedRange<Double>? {
        guard e.rangeOn, e.rangeIn != nil || e.rangeOut != nil else { return nil }
        let lo = e.rangeIn ?? 0, hi = e.rangeOut ?? duration
        return hi > lo ? lo...hi : nil
    }

    /// Saves a change to the show's editing state (no undo step), and
    /// takes it up at once rather than on the next tick.
    public func updateEditor(_ change: (inout ShowEditorState) -> Void) {
        model?.updateEditor(showID, change)
        if !isEditingLive, let latest = model?.show(showID), latest != show { reload(latest) }
        touch()
    }

    public func setRangeIn() {
        let t = (timeline.wrap(clock.now) * 100).rounded() / 100
        updateEditor { e in
            e.rangeIn = t
            if let o = e.rangeOut, o <= t { e.rangeOut = nil }
            e.rangeOn = true
        }
    }

    public func setRangeOut() {
        let t = (timeline.wrap(clock.now) * 100).rounded() / 100
        updateEditor { e in
            e.rangeOut = t
            if let i = e.rangeIn, i >= t { e.rangeIn = nil }
            e.rangeOn = true
        }
    }

    public func clearRange() {
        updateEditor { $0.rangeIn = nil; $0.rangeOut = nil }
    }

    /// With loop playback on, reaching the range's end (or the show's, with
    /// no range) goes back to its start. Checked every frame drawn and every
    /// tick, so it overshoots by a frame at most.
    private func keepInLoop() {
        guard show.editor.loopPlayback || listening != nil, clock.playing, clock.rate > 0, duration > 0 else { return }
        let region = listening?.range ?? range ?? 0...duration
        let local = timeline.wrap(clock.now)
        let atShowEnd = !timeline.loops && clock.now >= duration - 0.001
        if local >= region.upperBound || atShowEnd || local < region.lowerBound - 0.1 {
            seek(region.lowerBound)
        }
    }

    // MARK: Listen (the Rhythm tool)

    /// While listening: the stretch that loops, and the clicks (show times).
    /// Its own loop, so the show's saved loop switch isn't touched.
    @ObservationIgnored private var listening: (range: ClosedRange<Double>, clicks: [Double])?
    public var isListening: Bool { listening != nil }

    /// Loops `range` with a click at each of `clicks`, over the songs.
    public func listen(_ range: ClosedRange<Double>, clicks: [Double]) {
        listening = (range, clicks)
        clock.seek(range.lowerBound)
        play()
    }

    /// New clicks while listening (the pattern changed): from the next pass.
    public func updateListening(_ range: ClosedRange<Double>, clicks: [Double]) {
        guard listening != nil else { return }
        listening = (range, clicks)
    }

    /// Playback stopped some other way (Space, say): Listen is over.
    @ObservationIgnored public var onListenEnded: (() -> Void)?

    public func stopListening() {
        guard listening != nil else { return }
        listening = nil
        pause()
    }

    // MARK: Music

    private func pass(_ t: Double) -> Int {
        timeline.loops && timeline.duration > 0 ? Int((t / timeline.duration).rounded(.down)) : 0
    }

    /// Music plays while the show plays forwards at normal speed; scrubbing,
    /// shuttling and paused seeks are silent (plan, Phase 3). Call after
    /// anything that starts, stops or moves the clock: the music restarts
    /// from the clock's time and takes the clock over.
    private func syncMusic() {
        clock.external = nil
        guard clock.playing, clock.rate == 1, !show.music.isEmpty || listening != nil, let model else {
            if music.isRunning { music.stop() }
            return
        }
        let t = clock.now
        clock.seek(t)                   // counts from here, like the music
        let local = timeline.wrap(t)
        // Songs stop at the show's end (step 4 makes the show as long as
        // its longest row).
        let segments: [MusicPlayer.Segment] = show.music.compactMap { clip in
            guard let item = model.item(clip.itemID), let url = model.url(for: item),
                  let seg = clip.segment(from: local, until: timeline.duration) else { return nil }
            return MusicPlayer.Segment(clipID: clip.id, url: url, delay: seg.delay, fileStart: seg.fileStart,
                                       duration: seg.duration)
        }
        musicPass = pass(t)
        let clips = show.music
        let gain: (UUID, Double) -> Float = { id, t in
            clips.first { $0.id == id }.map { Float(AudioClip.gain(of: $0, at: t, among: clips)) } ?? 0
        }
        // Listen's clicks still to come in this stretch, as seconds from now.
        let clicks = (listening?.clicks ?? []).filter { $0 >= local - 0.001 }.map { $0 - local }
        if music.start(segments, clicks: clicks, from: local, gain: gain) {
            clock.external = { [music] in music.elapsed }
        }
    }

    // MARK: Drawing

    @ObservationIgnored private var drawnSize: [ObjectIdentifier: CGSize] = [:]
    /// The motionless frame each view last drew (its slide index), so it
    /// isn't drawn again and again: a still picture on the desktop cost
    /// 40% of a core before this (measured 2026-09-22).
    @ObservationIgnored private var drawnStill: [ObjectIdentifier: Int] = [:]

    public func render(_ view: MTKView) {
        let key = ObjectIdentifier(view)
        let size = view.drawableSize
        let settling = CACurrentMediaTime() - lastChange < 0.6
        guard clock.playing || waitingToStart || settling || drawnSize[key] != size else { return }
        drawnSize[key] = size

        keepInLoop()
        let t = clock.now
        let state = timeline.frame(at: t)
        if waitingToStart, let first = state.layers.last?.slide, media.isReady(first) {
            waitingToStart = false
            clock.seek(t)
            clock.play(rate: 1)
            syncMusic()
        }
        let overlay = timeline.overlay(at: t)
        // Nothing moving, nothing new to draw: skip this frame.
        let motionless = state.isMotionless && overlay == nil && (view as? ShowCanvas)?.stage == nil
        if motionless, !settling, let i = state.currentIndex, drawnStill[key] == i {
            return
        }
        drawnStill[key] = motionless ? state.currentIndex : nil
        if let i = state.currentIndex {
            media.prepare(around: i, in: timeline, visible: state.layers, alsoKeep: overlaysNear(t))
        }

        guard let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        // Video follows the clock only at normal speed; otherwise it's seeked.
        let playing = clock.playing && clock.rate == 1
        let source: (Layer) -> CIImage? = { [media] layer in media.image(for: layer, playing: playing) }
        let overlaySource: (OverlayLayer) -> CIImage? = { [media] o in media.image(for: o) }
        let image = (view as? ShowCanvas)?.stage.map {
            stageImage(state, overlay: overlay, overlaySource: overlaySource, size: size, stage: $0, source: source)
        } ?? Compositor.compose(state, size: size, overlay: overlay, overlaySource: overlaySource, source: source)
        let dest = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                       pixelFormat: view.colorPixelFormat, commandBuffer: cb) {
            drawable.texture
        }
        dest.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        _ = try? ci.startTask(toRender: image, to: dest)
        cb.present(drawable)
        cb.commit()
    }

    /// The Edit Show work area: the picture framed inside the view at the
    /// stage's zoom. Wherever an image hangs past the frame it's drawn,
    /// dimmed, outside the edge; with an image selected, the previous
    /// slide's last frame lies over it, see-through (the onion skin).
    private func stageImage(_ state: FrameState, overlay: OverlayLayer?,
                            overlaySource: @escaping (OverlayLayer) -> CIImage?,
                            size: CGSize, stage: ShowCanvas.Stage,
                            source: (Layer) -> CIImage?) -> CIImage {
        let whole = CGRect(origin: .zero, size: size)
        // Centred, so the same in Core Image's y-up space as in the view's.
        let frame = ShowCanvas.pictureRect(in: size, zoom: stage.zoom, aspect: stage.aspect)
        guard frame.width >= 1, frame.height >= 1 else { return CIImage(color: .black).cropped(to: whole) }
        let move = CGAffineTransform(translationX: frame.minX, y: frame.minY)

        /// A layer's whole image where it sits, not cropped to the frame.
        func uncropped(_ layer: Layer, opacity: Double) -> CIImage? {
            guard let img = source(layer),
                  let m = Compositor.placement(for: layer, imageExtent: img.extent, outputSize: frame.size)
            else { return nil }
            let f = CIFilter.colorMatrix()
            f.inputImage = img.transformed(by: m.concatenating(move))
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity))
            return f.outputImage
        }

        var out = CIImage(color: .black).cropped(to: whole)
        for layer in state.layers {
            if let over = uncropped(layer, opacity: 0.35) { out = over.composited(over: out) }
        }
        out = Compositor.compose(state, size: frame.size, overlay: overlay, overlaySource: overlaySource,
                                 source: source)
            .transformed(by: move).composited(over: out)
        if stage.zoom < 1 {
            // The frame's edge, so a black slide still shows where it ends.
            let w: CGFloat = 2, grey = CIImage(color: CIColor(red: 0.45, green: 0.45, blue: 0.45))
            for r in [CGRect(x: frame.minX - w, y: frame.minY - w, width: frame.width + 2 * w, height: w),
                      CGRect(x: frame.minX - w, y: frame.maxY, width: frame.width + 2 * w, height: w),
                      CGRect(x: frame.minX - w, y: frame.minY, width: w, height: frame.height),
                      CGRect(x: frame.maxX, y: frame.minY, width: w, height: frame.height)] {
                out = grey.cropped(to: r).composited(over: out)
            }
        }
        if let id = stage.onionSlideID, stage.onionOpacity > 0, let before = lastFrame(before: id),
           before.slide.item.kind != .video,        // seeking another video would disturb it
           let onion = uncropped(before, opacity: stage.onionOpacity) {
            out = onion.composited(over: out)
        }
        return out.cropped(to: whole)
    }

    /// The lane's images showing now or starting in the next few seconds,
    /// so their files are decoded before they're needed.
    private func overlaysNear(_ t: Double) -> [MediaItem] {
        let local = timeline.wrap(t)
        return timeline.overlays.filter { $0.end > local - 1 && $0.start < local + 8 }.map(\.item)
    }

    /// The slide before `id` as it looks at the very end of its move: the
    /// frame a match cut lines up against. Nil for the first slide of a show
    /// that doesn't loop.
    private func lastFrame(before id: Int64) -> Layer? {
        guard let i = timeline.slides.firstIndex(where: { $0.slide.id == id }),
              timeline.slides.count > 1, i > 0 || timeline.loops else { return nil }
        let prev = timeline.slides[i > 0 ? i - 1 : timeline.slides.count - 1]
        return Layer(slide: prev, localTime: prev.visibleSpan,
                     transitionInPlays: prev.transitionIn.duration,
                     transitionOutPlays: prev.transitionOut)
    }

    /// `fps`: the desktop draws at 30, where 60 costs twice the power for
    /// no visible gain (measured 2026-09-22); the app's previews use 60.
    public func makeView(fps: Int = 60) -> ShowCanvas {
        let v = ShowCanvas(frame: NSRect(x: 0, y: 0, width: 640, height: 360), device: device)
        v.framebufferOnly = false
        v.colorPixelFormat = .bgra8Unorm
        v.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        v.preferredFramesPerSecond = fps
        v.engine = self
        v.delegate = v
        touch()
        return v
    }
}

/// An MTKView that draws whatever its engine says is on screen.
public final class ShowCanvas: MTKView, MTKViewDelegate {
    public weak var engine: PlaybackEngine?
    /// Set on the Edit Show preview only, making it a work area. Every other
    /// canvas (pop-out, player) is the picture and nothing else.
    public var stage: Stage?

    public struct Stage: Equatable {
        /// 1 fits the picture to the view; below 1 leaves room round it.
        public var zoom: CGFloat = 1
        /// The selected image's slide: the onion skin shows the slide before it.
        public var onionSlideID: Int64?
        public var onionOpacity: Double = 0.5
        /// The shape the show is framed for (ShowTools: the main screen's).
        public var aspect: CGFloat = 16 / 9

        public init(zoom: CGFloat = 1, onionSlideID: Int64? = nil, onionOpacity: Double = 0.5, aspect: CGFloat = 16 / 9) {
            self.zoom = zoom
            self.onionSlideID = onionSlideID
            self.onionOpacity = onionOpacity
            self.aspect = aspect
        }
    }

    /// The picture's frame inside a view of `size` at `zoom` (1 fits it).
    public static func pictureRect(in size: CGSize, zoom: CGFloat, aspect: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let z = min(max(zoom, 0.05), 1)
        let w = min(size.width, size.height * aspect) * z
        let h = w / aspect
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    public var onKey: ((NSEvent) -> Bool)?
    public var onMouseMoved: (() -> Void)?
    public var onDoubleClick: (() -> Void)?

    public nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { engine?.render(self) }
    }

    public override var acceptsFirstResponder: Bool { onKey != nil }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    public override func mouseMoved(with event: NSEvent) { onMouseMoved?() }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    public override func mouseDown(with event: NSEvent) {
        if onKey != nil { window?.makeFirstResponder(self) }
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}

/// The engine's picture as a SwiftUI view.
public struct ShowCanvasView: NSViewRepresentable {
    public let engine: PlaybackEngine
    public var stage: ShowCanvas.Stage? = nil

    public init(engine: PlaybackEngine, stage: ShowCanvas.Stage? = nil) {
        self.engine = engine
        self.stage = stage
    }

    public func makeNSView(context: Context) -> ShowCanvas {
        let v = engine.makeView()
        v.stage = stage
        return v
    }
    public func updateNSView(_ view: ShowCanvas, context: Context) {
        if view.engine !== engine { view.engine = engine; engine.touch() }
        if view.stage != stage { view.stage = stage; engine.touch() }
    }
}
