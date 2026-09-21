import SwiftUI
import MetalKit
import CoreImage
import ShowToolsCore

/// The show clock. Slides never keep their own timers: everything asks this
/// what time it is. (Phase 3 swaps in the music's clock when there is one.)
@MainActor
final class PlaybackClock {
    private(set) var playing = false
    private var base: Double = 0
    private var anchor: CFTimeInterval = 0

    var now: Double { playing ? base + (CACurrentMediaTime() - anchor) : base }

    func play() {
        guard !playing else { return }
        anchor = CACurrentMediaTime()
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

/// What the on-screen overlay shows. Updated a few times a second, not per frame.
@MainActor
@Observable
final class HUDState {
    var visible = true
    var slideText = ""
    var timeText = ""
    var playing = false
    var typedNumber = ""
    var message: String?
}

/// One playing show: its window, clock, media and render loop.
@MainActor
final class Player: NSObject, NSWindowDelegate, MTKViewDelegate {

    // MARK: Opening

    private static var open: [Player] = []

    static func open(show: Show, model: AppModel, fullScreen: Bool, startAt index: Int? = nil) {
        let p = Player(showID: show.id, model: model)
        open.append(p)
        p.present(fullScreen: fullScreen, startAt: index)
    }

    // MARK: State

    private let showID: Int64
    private let model: AppModel
    private var show: Show
    private(set) var timeline: ShowTimeline
    private let clock = PlaybackClock()
    private let media: MediaProvider
    let hud = HUDState()

    private var window: NSWindow!
    private var view: PlayerMTKView!
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let ci: CIContext
    private var hudTimer: Timer?
    private var hudHideAt: Date = .distantFuture
    /// The clock waits for the first slide's media, so a show never opens on black.
    private var waitingToStart = true
    private var wantsToPlay = true

    private init(showID: Int64, model: AppModel) {
        self.showID = showID
        self.model = model
        show = model.show(showID) ?? Show(id: showID, name: "")
        timeline = model.timeline(for: show)
        device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        ci = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        // Decode at the size of the largest screen, with headroom for Ken Burns zoom.
        let largest = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2560
        media = MediaProvider(maxPixels: Int(min(largest * 1.25, 8192)), urlFor: { [weak model] in model?.url(for: $0) })
        super.init()
    }

    private func present(fullScreen: Bool, startAt index: Int?) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 1280, height: 720)
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.midY - size.height / 2)
        window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = show.name
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self

        view = PlayerMTKView(frame: NSRect(origin: .zero, size: size), device: device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.preferredFramesPerSecond = 60
        view.delegate = self
        view.player = self

        let host = PassthroughHostingView(rootView: HUDView(hud: hud))
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        window.contentView = view

        if let index { clock.seek(timeline.settledTime(of: index)) }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        if fullScreen { window.toggleFullScreen(nil) }

        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        showHUD()
    }

    // MARK: Render loop

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(view) }
    }

    private func render(_ view: MTKView) {
        let t = clock.now
        var state = timeline.frame(at: t)

        if waitingToStart {
            if let first = state.layers.last?.slide, media.isReady(first) {
                waitingToStart = false
                if wantsToPlay { clock.seek(t); clock.play() }
            } else if let first = state.layers.last {
                media.prepare(around: first.slide.index, in: timeline, visible: [])
            }
        }
        // A show that doesn't loop stops on its last frame.
        if !timeline.loops, clock.playing, t >= timeline.duration {
            clock.pause()
            clock.seek(max(timeline.duration - 0.001, 0))
            state = timeline.frame(at: clock.now)
            showHUD()
        }

        if let i = state.currentIndex {
            media.prepare(around: i, in: timeline, visible: state.layers)
        }

        guard let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        let size = view.drawableSize
        let playing = clock.playing
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

    // MARK: HUD + live edits

    private func tick() {
        // Edits made in the main window while playing take effect right away.
        if let latest = model.show(showID), latest != show {
            let keepIndex = timeline.frame(at: clock.now).currentIndex ?? 0
            let into = clock.now - (timeline.slides.indices.contains(keepIndex) ? timeline.slides[keepIndex].start : 0)
            show = latest
            timeline = model.timeline(for: show)
            window.title = show.name
            if timeline.slides.indices.contains(keepIndex) {
                clock.seek(timeline.slides[keepIndex].start + max(into, 0))
            }
        }

        let state = timeline.frame(at: clock.now)
        let n = timeline.slides.count
        hud.slideText = n == 0 ? "No slides" : "\((state.currentIndex ?? 0) + 1) / \(n)"
        hud.timeText = "\(formatDuration(timeline.wrap(clock.now))) / \(formatDuration(timeline.duration))"
        hud.playing = clock.playing || (waitingToStart && wantsToPlay)

        if hud.visible, Date() > hudHideAt, hud.typedNumber.isEmpty {
            hud.visible = false
            if window.styleMask.contains(.fullScreen) { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    func showHUD(_ message: String? = nil) {
        hud.message = message
        hud.visible = true
        hudHideAt = Date().addingTimeInterval(2.5)
        tick()
    }

    // MARK: Controls

    func togglePlay() {
        if clock.playing || (waitingToStart && wantsToPlay) {
            wantsToPlay = false
            clock.pause()
            media.pauseAllVideo()
        } else {
            wantsToPlay = true
            if !waitingToStart {
                if !timeline.loops, clock.now >= timeline.duration - 0.01 { clock.seek(0) }
                clock.play()
            }
        }
        showHUD()
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
        // Keep within the current loop pass so wrapping transitions stay right.
        let passStart = timeline.loops && timeline.duration > 0
            ? (clock.now / timeline.duration).rounded(.down) * timeline.duration : 0
        let s = timeline.slides[index]
        clock.seek(passStart + (clock.playing ? s.start : timeline.settledTime(of: index)))
        showHUD()
    }

    func typeDigit(_ d: String) {
        hud.typedNumber += d
        showHUD()
    }

    func commitTypedNumber() {
        if let n = Int(hud.typedNumber) { go(to: n - 1) }
        hud.typedNumber = ""
        showHUD()
    }

    func escape() {
        if !hud.typedNumber.isEmpty {
            hud.typedNumber = ""
        } else if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            window.close()
        }
    }

    func toggleFullScreen() { window.toggleFullScreen(nil) }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        hudTimer?.invalidate()
        view.isPaused = true
        view.delegate = nil
        media.stopAll()
        Player.open.removeAll { $0 === self }
    }

    func windowDidExitFullScreen(_ notification: Notification) { showHUD() }
}

/// The HUD sits over the picture but never takes a click or the keyboard.
final class PassthroughHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Takes the keyboard for the player.
final class PlayerMTKView: MTKView {
    weak var player: Player?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let p = player else { return super.keyDown(with: event) }
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: p.togglePlay()                   // space
        case 123: p.step(-1)                      // ←
        case 124: p.step(1)                       // →
        case 115: p.go(to: 0)                     // Home
        case 119: p.go(to: p.timeline.slides.count - 1)   // End
        case 36, 76: p.commitTypedNumber()        // Return, Enter
        case 53: p.escape()                       // Esc
        default:
            if chars.count == 1, chars.first!.isNumber { p.typeDigit(chars) }
            else if chars.lowercased() == "f" { p.toggleFullScreen() }
            else if chars.lowercased() == "h" { p.showHUD() }
            else { super.keyDown(with: event) }
        }
    }

    override func mouseMoved(with event: NSEvent) { player?.showHUD() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { player?.toggleFullScreen() }
    }
}

struct HUDView: View {
    let hud: HUDState

    var body: some View {
        VStack {
            Spacer()
            if hud.visible {
                VStack(spacing: 6) {
                    if !hud.typedNumber.isEmpty {
                        Text("Go to slide \(hud.typedNumber)_  ↩")
                            .font(.title2.monospacedDigit().weight(.semibold))
                    }
                    HStack(spacing: 14) {
                        Image(systemName: hud.playing ? "play.fill" : "pause.fill")
                        Text(hud.slideText).monospacedDigit()
                        Text(hud.timeText).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("space play/pause · ← → slides · type a number ↩ to jump · F full screen · esc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 30)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: hud.visible)
    }
}
