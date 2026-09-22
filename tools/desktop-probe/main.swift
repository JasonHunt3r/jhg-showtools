// Phase 5 test program, part 1 (plan: "Rethought with Jason 2026-09-22").
// Throwaway: proves a live window can sit beneath the desktop icons on every
// monitor and Space, with clicks passing through, before BGTools is built.
// It never opens a library.
//
//   tools/desktop-probe/build.sh            → build/DesktopProbe.app
//   open build/DesktopProbe.app --args <log file>
//
// Each monitor gets a slowly shifting colour with its name and a ticking
// clock (so a screenshot shows it's live). The menu bar icon "BG" pauses a
// monitor or quits. Every event that could disturb the window is logged:
// screens changing, Space changes, sleep and wake, occlusion.
//
// Part 2: `--per-space` gives every desktop Space its own window (and its
// own colour), placed with the unofficial CoreGraphics Space calls, which
// yabai and Hammerspoon also use. There's no public way to tell Spaces
// apart; these exist on macOS 27.0 (checked 2026-09-22).
import AppKit

enum Spaces {
    typealias ConnFn = @convention(c) () -> Int32
    typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>
    typealias MoveFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    static let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    static let conn = unsafeBitCast(dlsym(cg, "CGSMainConnectionID")!, to: ConnFn.self)()
    static let copy = unsafeBitCast(dlsym(cg, "CGSCopyManagedDisplaySpaces")!, to: CopyFn.self)
    static let add = unsafeBitCast(dlsym(cg, "CGSAddWindowsToSpaces")!, to: MoveFn.self)
    static let remove = unsafeBitCast(dlsym(cg, "CGSRemoveWindowsFromSpaces")!, to: MoveFn.self)

    struct Space { let id: Int; let uuid: String; let index: Int }

    /// Each display's ordinary desktops (not full-screen apps), by the
    /// display's UUID.
    static func desktops() -> [String: [Space]] {
        let displays = copy(conn).takeRetainedValue() as? [[String: Any]] ?? []
        var out: [String: [Space]] = [:]
        for d in displays {
            guard let display = d["Display Identifier"] as? String else { continue }
            let spaces = (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int) == 0 }
            out[display] = spaces.enumerated().map { i, s in
                Space(id: s["ManagedSpaceID"] as? Int ?? 0, uuid: s["uuid"] as? String ?? "", index: i + 1)
            }
        }
        return out
    }

    static func move(_ window: NSWindow, to space: Int) {
        let w = [NSNumber(value: window.windowNumber)] as CFArray
        let all = desktops().values.flatMap { $0 }.map { NSNumber(value: $0.id) } as CFArray
        remove(conn, w, all)
        add(conn, w, [NSNumber(value: space)] as CFArray)
    }
}

extension NSScreen {
    var displayUUID: String {
        let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        guard let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, u) as String
    }
}

let perSpace = CommandLine.arguments.contains("--per-space")

let logURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") })
                 ?? NSTemporaryDirectory() + "desktop-probe.log")

func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

final class LiveView: NSView {
    let name: String
    var paused = false
    private var hue: CGFloat = CGFloat.random(in: 0...1)
    private var timer: Timer?

    init(frame: NSRect, name: String) {
        self.name = name
        super.init(frame: frame)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10, repeats: true) { [weak self] _ in
            guard let self, !self.paused else { return }
            self.hue = (self.hue + 0.002).truncatingRemainder(dividingBy: 1)
            self.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let top = NSColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1)
        let bottom = NSColor(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.3, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)
        let clock = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let text = "BGTools probe · \(name) · \(clock)\(paused ? " · paused" : "")"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height * 0.42), withAttributes: attrs)
    }
}

final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var status: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        log("launch macOS \(ProcessInfo.processInfo.operatingSystemVersionString) pid \(getpid())")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "BG"
        buildWindows()
        let nc = NotificationCenter.default, wc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            log("screens changed: \(NSScreen.screens.map(\.localizedName))"); self?.buildWindows()
        }
        wc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            log("space changed; windows on screen: \(self?.windows.map { $0.isOnActiveSpace } ?? [])")
            self?.checkSpaces()
        }
        for (name, note) in [("will sleep", NSWorkspace.willSleepNotification), ("did wake", NSWorkspace.didWakeNotification),
                             ("screens slept", NSWorkspace.screensDidSleepNotification), ("screens woke", NSWorkspace.screensDidWakeNotification)] {
            wc.addObserver(forName: note, object: nil, queue: .main) { _ in log(name) }
        }
    }

    var spaceSet = ""

    func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        guard !perSpace else { return buildSpaceWindows() }
        windows = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            w.title = "BGTools probe \(screen.localizedName)"
            w.contentView = LiveView(frame: NSRect(origin: .zero, size: screen.frame.size), name: screen.localizedName)
            w.delegate = self
            w.setFrame(screen.frame, display: true)
            w.orderFront(nil)
            log("window \(w.windowNumber) on \(screen.localizedName) \(screen.frame) level \(w.level.rawValue)")
            return w
        }
        rebuildMenu()
    }

    /// One window per desktop Space on each screen, moved onto its Space.
    func buildSpaceWindows() {
        let all = Spaces.desktops()
        spaceSet = all.mapValues { $0.map(\.id) }.description
        windows = NSScreen.screens.flatMap { screen -> [NSWindow] in
            (all[screen.displayUUID] ?? []).map { space in
                let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
                w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
                w.collectionBehavior = [.stationary, .ignoresCycle]
                w.ignoresMouseEvents = true
                w.isReleasedWhenClosed = false
                w.hasShadow = false
                let label = "\(screen.localizedName) · Space \(space.index)"
                w.title = "BGTools probe \(label)"
                w.contentView = LiveView(frame: NSRect(origin: .zero, size: screen.frame.size), name: label)
                w.delegate = self
                w.setFrame(screen.frame, display: true)
                w.orderFront(nil)
                Spaces.move(w, to: space.id)
                log("window \(w.windowNumber) → \(label) (space id \(space.id), uuid \(space.uuid.isEmpty ? "none" : space.uuid))")
                return w
            }
        }
        rebuildMenu()
    }

    /// Spaces added or removed in Mission Control: rebuild.
    func checkSpaces() {
        guard perSpace else { return }
        let now = Spaces.desktops().mapValues { $0.map(\.id) }.description
        if now != spaceSet { log("spaces changed: \(now)"); buildWindows() }
    }

    func windowDidChangeOcclusionState(_ n: Notification) {
        guard let w = n.object as? NSWindow else { return }
        log("occlusion \(w.title): \(w.occlusionState.contains(.visible) ? "visible" : "hidden")")
    }

    func rebuildMenu() {
        let menu = NSMenu()
        for (i, w) in windows.enumerated() {
            guard let v = w.contentView as? LiveView else { continue }
            menu.addItem(NSMenuItem.sectionHeader(title: v.name))
            let item = NSMenuItem(title: "Pause", action: #selector(togglePause(_:)), keyEquivalent: "")
            item.tag = i; item.target = self; item.state = v.paused ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
    }

    @objc func togglePause(_ sender: NSMenuItem) {
        guard let v = windows[sender.tag].contentView as? LiveView else { return }
        v.paused.toggle(); v.needsDisplay = true
        log("\(v.name) \(v.paused ? "paused" : "playing")")
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = Probe()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
