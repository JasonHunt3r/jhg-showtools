import AppKit
import BGToolsCore
import ShowToolsCore
import ShowToolsPlayback

/// A monitor's Space, by what lasts: the display's UUID and the Space's
/// uuid ("all" when the Space calls are missing and one window serves
/// every Space).
struct ScreenKey: Hashable, CustomStringConvertible {
    let display: String
    let space: String
    var id: String { DesktopSettings.screenID(display: display, space: space) }
    var description: String { "\(display.prefix(8))/\(space.isEmpty ? "desktop1" : String(space.prefix(8)))" }
}

/// One window per monitor and Space at desktop level: above the wallpaper,
/// below Finder's icons, clicks passing through (measured). It shows a
/// player's engine; under All same, many windows show the same one.
@MainActor
final class DesktopWindow {
    let key: ScreenKey
    let window: NSWindow
    private(set) weak var engine: PlaybackEngine?

    init(key: ScreenKey, screen: NSScreen) {
        self.key = key
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
                          defer: false, screen: screen)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .black
    }

    func show(_ engine: PlaybackEngine?) {
        guard engine !== self.engine || window.contentView == nil else { return }
        self.engine = engine
        guard let engine else {
            window.contentView = NSView()
            return
        }
        let canvas = engine.makeView()
        canvas.frame = NSRect(origin: .zero, size: window.frame.size)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
    }

    func place(on screen: NSScreen, spaceID: Int?) {
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
        if let spaceID { Spaces.move(window, to: spaceID) }
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

/// Keeps a window on every monitor and Space as they come and go, and a
/// player for each screen's setting. One display change fires two or
/// three notices in the same second (measured), so it waits a moment and
/// rebuilds once. Windows and players that are still wanted are kept, so
/// their shows don't restart.
@MainActor
final class DesktopController {
    private let store: DesktopSettingsStore
    private(set) var settings: DesktopSettings
    private var settingsModified: Date?
    private var readers: [String: LibraryReader] = [:]
    /// By screen id, or "all" under All same.
    private var players: [String: Player] = [:]
    private var windows: [ScreenKey: DesktopWindow] = [:]
    private var pending: DispatchWorkItem?
    private var lastLayout = ""
    private var watch: Timer?

    init(store: DesktopSettingsStore) {
        self.store = store
        settings = store.load()
        settingsModified = store.modified
        Log.write("settings from \(store.url.path): \(settings.screens.count) screens, on \(settings.on)")
        let nc = NotificationCenter.default, wc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.soon("screens changed") }
        }
        wc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSound()
                self?.soon("space changed")
            }
        }
        // Settings edited elsewhere (by hand, for now) are taken up.
        watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSettingsFile() }
        }
        rebuild(reason: "launch")
    }

    /// Replaces the settings (the panel, the tiles) and saves them.
    func update(_ change: (inout DesktopSettings) -> Void) {
        change(&settings)
        do { try store.save(settings) } catch { Log.write("can't save settings: \(error)") }
        settingsModified = store.modified
        apply()
    }

    private func checkSettingsFile() {
        let m = store.modified
        guard m != settingsModified else { return }
        settingsModified = m
        settings = store.load()
        Log.write("settings changed on disk")
        apply()
    }

    private func soon(_ reason: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.rebuild(reason: reason) } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// The monitors and Spaces there are now, each with its screen and the
    /// Space's current id (nil: one window on every Space).
    private func wanted() -> [(ScreenKey, NSScreen, Int?)] {
        let desktops = Spaces.desktops()
        var out: [(ScreenKey, NSScreen, Int?)] = []
        for screen in NSScreen.screens {
            let display = screen.displayUUID
            if Spaces.available, let spaces = desktops[display], !spaces.isEmpty {
                for s in spaces { out.append((ScreenKey(display: display, space: s.uuid), screen, s.id)) }
            } else {
                out.append((ScreenKey(display: display, space: "all"), screen, nil))
            }
        }
        return out
    }

    private func rebuild(reason: String) {
        let want = settings.on ? wanted() : []
        let layout = want.map { "\($0.0)@\($0.2 ?? -1)\($0.1.frame)" }.joined(separator: " ")
        guard layout != lastLayout else { return }   // a Space switch alone changes nothing
        lastLayout = layout

        let keys = Set(want.map(\.0))
        for (key, w) in windows where !keys.contains(key) {
            w.close()
            windows[key] = nil
            Log.write("closed \(key)")
        }
        for (key, screen, spaceID) in want {
            if windows[key] == nil {
                let w = DesktopWindow(key: key, screen: screen)
                if spaceID == nil { w.window.collectionBehavior.insert(.canJoinAllSpaces) }
                windows[key] = w
                Log.write("opened \(key) on \(screen.localizedName)")
            }
            windows[key]?.place(on: screen, spaceID: spaceID)
        }
        Log.write("layout (\(reason)): \(windows.count) windows")
        apply()
    }

    /// Matches players to the settings and windows to players. A player
    /// whose setting hasn't changed keeps playing.
    private func apply() {
        if !settings.on {
            windows.values.forEach { $0.close() }
            windows = [:]
            lastLayout = ""
        } else if windows.isEmpty {
            lastLayout = ""
            return rebuild(reason: "switched on")
        }
        var needed: [String: ScreenSetting] = [:]
        for key in windows.keys {
            guard let s = settings.setting(for: key.id) else { continue }
            needed[settings.allSame ? "all" : key.id] = s
        }
        for (id, p) in players where needed[id] != p.setting || (p.usesRandomDefaults && settings.randomDefaults != p.randomDefaults) {
            p.stop()
            players[id] = nil
        }
        for (id, s) in needed where players[id] == nil {
            guard let reader = reader(for: s.library) else { continue }
            players[id] = Player(setting: s, reader: reader, randomDefaults: settings.randomDefaults)
        }
        for (key, w) in windows {
            w.show(players[settings.allSame ? "all" : key.id]?.engine)
        }
        // Readers no player uses any more are closed.
        let used = Set(needed.values.map(\.library))
        for (path, r) in readers where !used.contains(path) {
            r.close()
            readers[path] = nil
        }
        updateSound()
    }

    private func reader(for path: String) -> LibraryReader? {
        if let r = readers[path] { return r }
        do {
            let r = try LibraryReader(root: URL(fileURLWithPath: path))
            readers[path] = r
            return r
        } catch {
            Log.write("can't open \(path): \(error)")
            return nil
        }
    }

    /// Only the main display's current Space is heard.
    private func updateSound() {
        guard let main = NSScreen.screens.first else { return }
        let space = Spaces.current()[main.displayUUID] ?? ""
        let heard = settings.allSame ? "all" : DesktopSettings.screenID(display: main.displayUUID, space: space)
        for (id, p) in players { p.audible = id == heard }
    }

    func closeAll() {
        windows.values.forEach { $0.close() }
        windows = [:]
        players.values.forEach { $0.stop() }
        players = [:]
        readers.values.forEach { $0.close() }
        readers = [:]
    }
}
