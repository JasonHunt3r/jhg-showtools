import AppKit
import ShowToolsCore
import ShowToolsPlayback

/// A monitor's Space, by what lasts: the display's UUID and the Space's
/// uuid (the main display's first desktop has none, so it's "desktop 1").
struct ScreenKey: Hashable, CustomStringConvertible {
    let display: String
    let space: String
    var description: String { "\(display.prefix(8))/\(space.isEmpty ? "desktop1" : String(space.prefix(8)))" }
}

/// One window per monitor and Space at desktop level: above the wallpaper,
/// below Finder's icons, clicks passing through (measured).
@MainActor
final class DesktopWindow {
    let key: ScreenKey
    let window: NSWindow
    let engine: PlaybackEngine

    init(key: ScreenKey, screen: NSScreen, source: ShowSource, showID: Int64) {
        self.key = key
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
                          defer: false, screen: screen)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .black
        engine = PlaybackEngine(showID: showID, model: source)
        let canvas = engine.makeView()
        canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        engine.play()
    }

    func place(on screen: NSScreen, spaceID: Int?) {
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
        if let spaceID { Spaces.move(window, to: spaceID) }
    }

    func close() {
        engine.shutdown()
        window.orderOut(nil)
        window.close()
    }
}

/// Keeps a window on every monitor and Space as they come and go. One
/// display change fires two or three notices in the same second
/// (measured), so it waits a moment and rebuilds once. Windows whose
/// monitor and Space are still there are kept, so their shows don't
/// restart; they're only placed again (Space ids change on a replug).
@MainActor
final class DesktopController {
    private let source: LibraryReader
    private let showID: Int64
    private var windows: [ScreenKey: DesktopWindow] = [:]
    private var pending: DispatchWorkItem?
    private var lastLayout = ""

    init(source: LibraryReader, showID: Int64) {
        self.source = source
        self.showID = showID
        let nc = NotificationCenter.default, wc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.soon("screens changed") }
        }
        wc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.soon("space changed") }
        }
        rebuild(reason: "launch")
    }

    private func soon(_ reason: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.rebuild(reason: reason) } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func rebuild(reason: String) {
        let desktops = Spaces.desktops()
        var wanted: [(ScreenKey, NSScreen, Int?)] = []
        for screen in NSScreen.screens {
            let display = screen.displayUUID
            if Spaces.available, let spaces = desktops[display], !spaces.isEmpty {
                for s in spaces { wanted.append((ScreenKey(display: display, space: s.uuid), screen, s.id)) }
            } else {
                // Fallback: one window on every Space of this display.
                wanted.append((ScreenKey(display: display, space: "all"), screen, nil))
            }
        }
        let layout = wanted.map { "\($0.0)@\($0.2 ?? -1)\($0.1.frame)" }.joined(separator: " ")
        guard layout != lastLayout else { return }   // a Space switch alone changes nothing
        lastLayout = layout

        let keys = Set(wanted.map(\.0))
        for (key, w) in windows where !keys.contains(key) {
            w.close()
            windows[key] = nil
            Log.write("closed \(key)")
        }
        for (key, screen, spaceID) in wanted {
            let w: DesktopWindow
            if let existing = windows[key] {
                w = existing
            } else {
                w = DesktopWindow(key: key, screen: screen, source: source, showID: showID)
                if spaceID == nil { w.window.collectionBehavior.insert(.canJoinAllSpaces) }
                windows[key] = w
                Log.write("opened \(key) on \(screen.localizedName)")
            }
            w.place(on: screen, spaceID: spaceID)
        }
        Log.write("layout (\(reason)): \(windows.count) windows")
    }

    func closeAll() {
        windows.values.forEach { $0.close() }
        windows = [:]
    }
}
