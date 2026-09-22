import AppKit
import WidgetKit
import LocalAuthentication
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

/// A monitor's Space as the window lists it.
struct ScreenInfo: Identifiable, Hashable {
    let key: ScreenKey
    let displayName: String
    /// The monitor's frame in screen coordinates, for the arrangement.
    let displayFrame: CGRect
    let isMainDisplay: Bool
    /// As Mission Control numbers them (0 when one window serves them all).
    let spaceIndex: Int
    var isCurrent: Bool
    var id: String { key.id }
    var title: String { spaceIndex > 0 ? "\(displayName) · Space \(spaceIndex)" : displayName }
}

/// One window per monitor and Space at desktop level: above the wallpaper,
/// below Finder's icons, clicks passing through (measured). It shows a
/// player's engine; under All same, many windows show the same one.
@MainActor
final class DesktopWindow {
    /// The desktop's frame rate: half the app's, half the power.
    static let fps = 30
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
        let canvas = engine.makeView(fps: DesktopWindow.fps)
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
@Observable
final class DesktopController {
    @ObservationIgnored let store: DesktopSettingsStore
    private(set) var settings: DesktopSettings
    @ObservationIgnored private var settingsModified: Date?
    @ObservationIgnored private var readers: [String: LibraryReader] = [:]
    /// By screen id, or "all" under All same.
    private(set) var players: [String: Player] = [:]
    /// Every monitor and Space there is now, for the window.
    private(set) var screens: [ScreenInfo] = []
    /// While BGTools' window is open, libraries it's shown stay open, so
    /// its pickers don't close and reopen them.
    @ObservationIgnored var keepReaders = false
    @ObservationIgnored private var windows: [ScreenKey: DesktopWindow] = [:]
    @ObservationIgnored private var pending: DispatchWorkItem?
    @ObservationIgnored private var lastLayout = ""
    @ObservationIgnored private var watch: Timer?
    /// Nothing can be seen: the Mac or its displays are asleep, or the
    /// screen is locked. Low Power Mode holds the picture too (Jason).
    private var asleep = false
    private var locked = false
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Private libraries unlocked in this run only: cleared on sleep or
    /// lock, never restored at launch (Jason: "we don't want to forget
    /// we've got a racy BG running the next time we open the lid").
    private(set) var unlocked: Set<String> = []
    /// The last public setting a screen played, to fall back on.
    @ObservationIgnored private var lastPublic: [String: ScreenSetting] = [:]

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
                self?.updateCurrent()
                self?.updateSound()
                self?.updatePaused()
                self?.soon("space changed")
            }
        }
        for (name, note) in [("asleep", NSWorkspace.screensDidSleepNotification),
                             ("awake", NSWorkspace.screensDidWakeNotification),
                             ("sleep", NSWorkspace.willSleepNotification),
                             ("wake", NSWorkspace.didWakeNotification)] {
            wc.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setUnseen(asleep: name == "asleep" || name == "sleep") }
            }
        }
        // The screen lock has no public notification; this one is the
        // long-standing distributed notification macOS posts.
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setUnseen(locked: locked) }
            }
        }
        nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.updatePaused()
            }
        }
        // Settings edited elsewhere (by hand, for now) are taken up.
        watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSettingsFile() }
        }
        rebuild(reason: "launch")
        publishForTiles()
    }

    /// Asleep, locked, or awake again. Sleep and lock also drop every
    /// private library, so nothing private is there when the lid opens.
    private func setUnseen(asleep: Bool? = nil, locked: Bool? = nil) {
        if let asleep { self.asleep = asleep }
        if let locked { self.locked = locked }
        Log.write("asleep \(self.asleep), locked \(self.locked)")
        if self.asleep || self.locked, !unlocked.isEmpty {
            unlocked = []
            Log.write("private libraries locked again")
            apply()
        }
        updatePaused()
    }

    /// Pauses every player none of whose screens can be seen: the Mac
    /// asleep or locked, Low Power Mode, or its Space isn't the one its
    /// display is showing (which covers a full-screen app, since that's a
    /// Space of its own).
    private func updatePaused() {
        let stopped = asleep || locked || lowPower
        var live: Set<String> = []
        if !stopped {
            for info in screens where info.isCurrent {
                live.insert(settings.allSame ? "all" : info.id)
            }
        }
        for (id, p) in players { p.paused = !live.contains(id) }
    }

    /// Whether a screen's library may play: a private one needs Touch ID
    /// in this run (spec question 11).
    func isLocked(_ setting: ScreenSetting) -> Bool {
        guard let reader = readers[setting.library] ?? reader(for: setting.library) else { return false }
        return reader.isPrivate && !unlocked.contains(setting.library)
    }

    /// Asks for Touch ID (or the Mac's password) and, if it's Jason, plays
    /// that library until the Mac sleeps or locks.
    func unlock(_ setting: ScreenSetting) async {
        let name = readers[setting.library]?.name ?? "this library"
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error),
              (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: "play the private library “\(name)” on the desktop")) == true
        else {
            Log.write("private library \(name) not unlocked")
            return
        }
        unlocked.insert(setting.library)
        Log.write("private library \(name) unlocked for this run")
        apply()
    }

    /// Replaces the settings (the panel, the tiles) and saves them.
    func update(_ change: (inout DesktopSettings) -> Void) {
        let wasOn = settings.on
        change(&settings)
        if settings.on != wasOn { publishForTiles() }
        do { try store.save(settings) } catch { Log.write("can't save settings: \(error)") }
        settingsModified = store.modified
        apply()
    }

    /// The Desktop Show tile can't read the settings (it's sandboxed, and
    /// a test's settings are elsewhere), so BGTools writes its on/off to a
    /// file the tile may read, and asks Control Center to redraw it.
    func publishForTiles() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BGTools")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["on": settings.on])
                .write(to: dir.appendingPathComponent("control-state.json"), options: .atomic)
        } catch {
            Log.write("can't write the tiles' state: \(error)")
        }
        ControlCenter.shared.reloadControls(ofKind: "com.jhg.bgtools.desktopShow")
    }

    private func checkSettingsFile() {
        let m = store.modified
        guard m != settingsModified else { return }
        settingsModified = m
        settings = store.load()
        Log.write("settings changed on disk")
        publishForTiles()
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
        let current = Spaces.current()
        var out: [(ScreenKey, NSScreen, Int?)] = []
        var infos: [ScreenInfo] = []
        for (n, screen) in NSScreen.screens.enumerated() {
            let display = screen.displayUUID
            if Spaces.available, let spaces = desktops[display], !spaces.isEmpty {
                for s in spaces {
                    let key = ScreenKey(display: display, space: s.uuid)
                    out.append((key, screen, s.id))
                    infos.append(ScreenInfo(key: key, displayName: screen.localizedName, displayFrame: screen.frame,
                                            isMainDisplay: n == 0, spaceIndex: s.index,
                                            isCurrent: current[display] == s.uuid))
                }
            } else {
                let key = ScreenKey(display: display, space: "all")
                out.append((key, screen, nil))
                infos.append(ScreenInfo(key: key, displayName: screen.localizedName, displayFrame: screen.frame,
                                        isMainDisplay: n == 0, spaceIndex: 0, isCurrent: true))
            }
        }
        if infos != screens { screens = infos }
        return out
    }

    /// Marks the Space each monitor shows now.
    private func updateCurrent() {
        let current = Spaces.current()
        let updated = screens.map { var i = $0; i.isCurrent = i.spaceIndex == 0 || current[i.key.display] == i.key.space; return i }
        if updated != screens { screens = updated }
    }

    private func rebuild(reason: String) {
        let all = wanted()
        let want = settings.on ? all : []
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
            guard var s = settings.setting(for: key.id) else { continue }
            if isLocked(s) {
                // A private library that isn't unlocked: the screen's last
                // public setting, or the "new screens" default.
                guard let fallback = [lastPublic[key.id], settings.newScreens].compactMap({ $0 }).first(where: { !isLocked($0) })
                else { continue }
                s = fallback
            } else {
                lastPublic[key.id] = s
            }
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
        for (path, r) in readers where !used.contains(path) && !keepReaders {
            r.close()
            readers[path] = nil
        }
        updateSound()
        updatePaused()
    }

    /// The libraries to offer: ShowTools' own and any a setting names.
    func libraryChoices() -> [LibraryChoice] {
        let named = settings.screens.values.map(\.library)
            + [settings.allSameSetting?.library, settings.newScreens?.library].compactMap { $0 }
        return LibraryChoices.list(named: named)
    }

    /// A first choice for a screen that has none: all files of the first
    /// library on offer.
    func startingSetting() -> ScreenSetting? {
        (settings.newScreens?.library ?? libraryChoices().first?.path).map { ScreenSetting(library: $0, mode: .allFiles) }
    }

    /// One line for the list: what a screen plays.
    func summary(for screenID: String) -> String {
        guard settings.on else { return "Off" }
        guard let s = settings.setting(for: screenID) else { return "Wallpaper" }
        if isLocked(s) { return "Private · locked" }
        let what = Self.describe(s.mode, in: readers[s.library]?.contents)
        let source = settings.allSame ? "All same" : settings.screens[screenID] == nil ? "New screens" : nil
        return [what, s.stillsOnly ? "stills" : nil, source].compactMap { $0 }.joined(separator: " · ")
    }

    /// A mode in words, naming its show or collection when the library's read.
    static func describe(_ mode: PlayMode, in contents: DesktopShow.Library?) -> String {
        func showName(_ id: Int64) -> String { contents?.shows.first { $0.id == id }?.name ?? "a show" }
        switch mode {
        case .show(let id): return showName(id)
        case .shuffled(let id): return "\(showName(id)), shuffled"
        case .collection(let id): return "Random from \(contents?.collections.first { $0.id == id }?.name ?? "a collection")"
        case .randomShow: return "A random show"
        case .allFiles: return "Random from all files"
        }
    }

    /// The player a screen shows (All same's under All same).
    func player(for screenID: String) -> Player? { players[settings.allSame ? "all" : screenID] }

    func reader(for path: String) -> LibraryReader? {
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
