import SwiftUI
import ShowToolsCore

/// What the on-screen overlay shows.
@MainActor
@Observable
final class HUDState {
    var visible = true
    var typedNumber = ""
}

/// A window that plays a show: the Play command's own window, or the Edit
/// Show preview popped out onto a screen of its own.
@MainActor
final class Player: NSObject, NSWindowDelegate {

    private static var open: [Player] = []

    /// A fresh engine that plays from `index`, owned by this window.
    static func open(show: Show, model: AppModel, fullScreen: Bool, startAt index: Int? = nil) {
        let engine = PlaybackEngine(showID: show.id, model: model)
        if let index { engine.go(to: index) }
        let p = Player(engine: engine, ownsEngine: true, title: show.name)
        open.append(p)
        p.present(fullScreen: fullScreen)
        engine.play()
    }

    /// Shows an engine that something else owns (the Edit Show preview).
    /// Closing the window leaves the engine running.
    static func popOut(_ engine: PlaybackEngine, title: String) {
        if let existing = open.first(where: { $0.engine === engine }) {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let p = Player(engine: engine, ownsEngine: false, title: title)
        open.append(p)
        // Prefer a screen other than the editor's: that's what popping out is for.
        let editorScreen = NSApp.keyWindow?.screen
        p.present(fullScreen: false, on: NSScreen.screens.first { $0 != editorScreen })
    }

    static func closeWindows(for engine: PlaybackEngine) {
        open.filter { $0.engine === engine }.forEach { $0.window.close() }
    }

    let engine: PlaybackEngine
    private let ownsEngine: Bool
    private let title: String
    private let hud = HUDState()
    private var window: NSWindow!
    private var canvas: ShowCanvas!
    private var hideTimer: Timer?

    private init(engine: PlaybackEngine, ownsEngine: Bool, title: String) {
        self.engine = engine
        self.ownsEngine = ownsEngine
        self.title = title
        super.init()
    }

    private func present(fullScreen: Bool, on preferred: NSScreen? = nil) {
        let screen = preferred ?? NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 1280, height: 720)
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.midY - size.height / 2)
        window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self

        canvas = engine.makeView()
        canvas.onKey = { [weak self] e in self?.key(e) ?? false }
        canvas.onMouseMoved = { [weak self] in self?.showHUD() }
        canvas.onDoubleClick = { [weak self] in self?.window.toggleFullScreen(nil) }

        let host = PassthroughHostingView(rootView: HUDView(hud: hud, engine: engine))
        host.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            host.topAnchor.constraint(equalTo: canvas.topAnchor),
            host.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        window.contentView = canvas
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        if fullScreen { window.toggleFullScreen(nil) }
        showHUD()
    }

    private func key(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) { return false }
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        switch e.keyCode {
        case 49: engine.togglePlay()                          // space
        case 123: engine.step(-1)                             // ←
        case 124: engine.step(1)                              // →
        case 115: engine.go(to: 0)                            // Home
        case 119: engine.go(to: engine.timeline.slides.count - 1)   // End
        case 36, 76:                                          // Return, Enter
            if let n = Int(hud.typedNumber) { engine.go(to: n - 1) }
            hud.typedNumber = ""
        case 53:                                              // Esc
            if !hud.typedNumber.isEmpty { hud.typedNumber = "" }
            else if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            else { window.close() }
        default:
            switch chars {
            case "j": engine.shuttle(-1)
            case "k": engine.shuttle(0)
            case "l": engine.shuttle(1)
            case "f": window.toggleFullScreen(nil)
            case "h": break
            case let c where c.count == 1 && c.first!.isNumber: hud.typedNumber += c
            default: return false
            }
        }
        showHUD()
        return true
    }

    private func showHUD() {
        hud.visible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hud.typedNumber.isEmpty else { return }
                self.hud.visible = false
                if self.window.styleMask.contains(.fullScreen) { NSCursor.setHiddenUntilMouseMoves(true) }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        hideTimer?.invalidate()
        canvas.isPaused = true
        canvas.delegate = nil
        if ownsEngine { engine.shutdown() }
        Player.open.removeAll { $0 === self }
    }
}

/// The HUD sits over the picture but never takes a click or the keyboard.
final class PassthroughHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct HUDView: View {
    let hud: HUDState
    let engine: PlaybackEngine

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
                        Image(systemName: engine.isPlaying ? "play.fill" : "pause.fill")
                        if engine.isPlaying && engine.rate != 1 {
                            Text(engine.rate > 0 ? "\(Int(engine.rate))×" : "◀ \(Int(-engine.rate))×")
                        }
                        Text("\(engine.currentIndex + 1) / \(engine.timeline.slides.count)").monospacedDigit()
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            Text("\(formatDuration(engine.timeline.wrap(engine.now))) / \(formatDuration(engine.duration))")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Text("space play/pause · ← → slides · J K L shuttle · type a number ↩ to jump · F full screen · esc")
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
