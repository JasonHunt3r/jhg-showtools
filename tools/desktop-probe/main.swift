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
import AppKit

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
        }
        for (name, note) in [("will sleep", NSWorkspace.willSleepNotification), ("did wake", NSWorkspace.didWakeNotification),
                             ("screens slept", NSWorkspace.screensDidSleepNotification), ("screens woke", NSWorkspace.screensDidWakeNotification)] {
            wc.addObserver(forName: note, object: nil, queue: .main) { _ in log(name) }
        }
    }

    func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
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
