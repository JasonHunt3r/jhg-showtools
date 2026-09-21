import SwiftUI
import MetalKit
import CoreImage
import ShowToolsCore

/// The show clock. Slides never keep their own timers: everything asks this
/// what time it is. (Phase 3 swaps in the music's clock when there is one.)
@MainActor
final class PlaybackClock {
    private(set) var playing = false
    /// 1 = normal; 2, 4… from pressing L again; negative plays backwards (J).
    private(set) var rate: Double = 1
    private var base: Double = 0
    private var anchor: CFTimeInterval = 0

    var now: Double { playing ? base + (CACurrentMediaTime() - anchor) * rate : base }

    func play(rate: Double? = nil) {
        if playing { base = now }
        anchor = CACurrentMediaTime()
        if let rate { self.rate = rate }
        playing = true
    }

    func pause() {
        guard playing else { return }
        base = now
        playing = false
    }

    func seek(_ t: Double) {
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
final class PlaybackEngine {
    let showID: Int64
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private(set) var show: Show
    @ObservationIgnored private(set) var timeline: ShowTimeline

    // Observed a few times a second, for controls — never per frame.
    private(set) var isPlaying = false
    private(set) var rate: Double = 1
    private(set) var currentIndex = 0
    private(set) var duration: Double = 0
    /// Bumped whenever the timeline is rebuilt, so views can re-read it.
    private(set) var revision = 0
    /// Bumped on every seek, so a paused playhead redraws where it landed.
    private(set) var seekCount = 0

    @ObservationIgnored let clock = PlaybackClock()
    @ObservationIgnored let media: MediaProvider
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
    @ObservationIgnored private(set) var isEditingLive = false

    init(showID: Int64, model: AppModel) {
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
    }

    /// Stop the timer and release video. The engine can't be used afterwards.
    func shutdown() {
        ticker?.invalidate()
        ticker = nil
        clock.pause()
        media.stopAll()
    }

    var now: Double { clock.now }

    func touch() { lastChange = CACurrentMediaTime() }

    // MARK: Keeping up with edits

    private func tick() {
        if !isEditingLive, let latest = model?.show(showID), latest != show { reload(latest) }
        let t = clock.now
        // A show that doesn't loop stops at its end (or its start, in reverse).
        if clock.playing, !timeline.loops, timeline.duration > 0 {
            if t >= timeline.duration { clock.pause(); clock.seek(timeline.duration - 0.001) }
            else if t < 0 { clock.pause(); clock.seek(0) }
        }
        let i = timeline.frame(at: clock.now).currentIndex ?? 0
        if i != currentIndex { currentIndex = i }
        let playing = clock.playing || waitingToStart
        if playing != isPlaying { isPlaying = playing }
        if clock.rate != rate { rate = clock.rate }
    }

    /// Edits made while playing take effect at once; the playhead stays on
    /// the same slide, the same distance into it.
    private func reload(_ latest: Show) {
        let keep = timeline.frame(at: clock.now).currentIndex
        let keptID = keep.map { timeline.slides[$0].slide.id }
        let into = keep.map { clock.now - timeline.slides[$0].start } ?? 0
        show = latest
        timeline = model?.timeline(for: latest) ?? timeline
        duration = timeline.duration
        revision += 1
        if let keptID, let s = timeline.slides.first(where: { $0.slide.id == keptID }) {
            clock.seek(s.start + max(0, min(into, s.length)))
        }
        touch()
    }

    /// Draws `edited` in place of the saved show, for a live edit that
    /// doesn't change timing (a Transform). Call `endLiveEdit` once it's
    /// committed, or abandoned.
    func showLiveEdit(_ edited: Show) {
        isEditingLive = true
        show = edited
        timeline = model?.timeline(for: edited) ?? timeline
        touch()
    }

    /// Back to the saved show: the next tick picks it up.
    func endLiveEdit() {
        guard isEditingLive else { return }
        isEditingLive = false
        tick()
        touch()
    }

    // MARK: Controls

    func play() {
        if !timeline.loops, clock.now >= timeline.duration - 0.01 { clock.seek(0) }
        if let first = timeline.frame(at: clock.now).layers.last?.slide, !media.isReady(first) {
            waitingToStart = true
            media.prepare(around: first.index, in: timeline, visible: [])
        } else {
            clock.play(rate: 1)
        }
        touch()
        tick()
    }

    func pause() {
        waitingToStart = false
        clock.pause()
        media.pauseAllVideo()
        touch()
        tick()
    }

    func togglePlay() { clock.playing || waitingToStart ? pause() : play() }

    /// Final Cut's J/K/L: L plays, again doubles; J the same backwards; K stops.
    func shuttle(_ direction: Int) {
        waitingToStart = false
        if direction == 0 { pause(); return }
        let current = clock.playing ? clock.rate : 0
        let next: Double = (current * Double(direction) > 0) ? min(abs(current) * 2, 8) * Double(direction)
                                                             : Double(direction)
        if next != 1 { media.pauseAllVideo() }
        clock.play(rate: next)
        touch()
        tick()
    }

    func seek(_ t: Double) {
        clock.seek(t)
        seekCount += 1
        touch()
        tick()
    }

    /// Next/previous land with the slide fully on screen when paused, and
    /// at the start of its transition when playing (so the transition plays).
    func step(_ delta: Int) {
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

    func go(to index: Int) {
        guard timeline.slides.indices.contains(index) else { return }
        // Stay within the current loop pass so wrapping transitions stay right.
        let passStart = timeline.loops && timeline.duration > 0
            ? (clock.now / timeline.duration).rounded(.down) * timeline.duration : 0
        let s = timeline.slides[index]
        seek(passStart + (clock.playing ? s.start : timeline.settledTime(of: index)))
    }

    /// Show a particular slide, fully on screen, and pause there.
    func showSlide(id: Int64) {
        guard let i = timeline.slides.firstIndex(where: { $0.slide.id == id }) else { return }
        pause()
        seek(timeline.settledTime(of: i))
    }

    // MARK: Drawing

    @ObservationIgnored private var drawnSize: [ObjectIdentifier: CGSize] = [:]

    func render(_ view: MTKView) {
        let key = ObjectIdentifier(view)
        let size = view.drawableSize
        let settling = CACurrentMediaTime() - lastChange < 0.6
        guard clock.playing || waitingToStart || settling || drawnSize[key] != size else { return }
        drawnSize[key] = size

        let t = clock.now
        let state = timeline.frame(at: t)
        if waitingToStart, let first = state.layers.last?.slide, media.isReady(first) {
            waitingToStart = false
            clock.seek(t)
            clock.play(rate: 1)
        }
        if let i = state.currentIndex {
            media.prepare(around: i, in: timeline, visible: state.layers)
        }

        guard let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        // Video follows the clock only at normal speed; otherwise it's seeked.
        let playing = clock.playing && clock.rate == 1
        let image = Compositor.compose(state, size: size) { [media] layer in
            media.image(for: layer, playing: playing)
        }
        let dest = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                       pixelFormat: view.colorPixelFormat, commandBuffer: cb) {
            drawable.texture
        }
        dest.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        _ = try? ci.startTask(toRender: image, to: dest)
        cb.present(drawable)
        cb.commit()
    }

    func makeView() -> ShowCanvas {
        let v = ShowCanvas(frame: NSRect(x: 0, y: 0, width: 640, height: 360), device: device)
        v.framebufferOnly = false
        v.colorPixelFormat = .bgra8Unorm
        v.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        v.preferredFramesPerSecond = 60
        v.engine = self
        v.delegate = v
        touch()
        return v
    }
}

/// An MTKView that draws whatever its engine says is on screen.
final class ShowCanvas: MTKView, MTKViewDelegate {
    weak var engine: PlaybackEngine?
    var onKey: ((NSEvent) -> Bool)?
    var onMouseMoved: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { engine?.render(self) }
    }

    override var acceptsFirstResponder: Bool { onKey != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseDown(with event: NSEvent) {
        if onKey != nil { window?.makeFirstResponder(self) }
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}

/// The engine's picture as a SwiftUI view.
struct ShowCanvasView: NSViewRepresentable {
    let engine: PlaybackEngine

    func makeNSView(context: Context) -> ShowCanvas { engine.makeView() }
    func updateNSView(_ view: ShowCanvas, context: Context) {
        if view.engine !== engine { view.engine = engine; engine.touch() }
    }
}
