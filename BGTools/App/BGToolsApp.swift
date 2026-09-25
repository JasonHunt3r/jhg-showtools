import AppKit
import SwiftUI
import BGToolsCore

/// BGTools: ShowTools shows as the desktop picture (spec/bgtools.md).
/// What each monitor and Space plays is in its settings file;
/// `BGTOOLS_SETTINGS` points tests at their own (never the real library).
@main
@MainActor
final class BGToolsApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var desktop: DesktopController?
    private var window: NSWindow?
    private let windowState = WindowState()
    private var panel: PanelController?

    static func main() {
        let app = NSApplication.shared
        let delegate = BGToolsApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = Self.makeMainMenu()
        app.run()
    }

    /// Just enough of a menu bar for ⌘Q to work while the settings window is
    /// open (a regular app then, so it needs one). Never shown as an
    /// accessory app, since there's no menu bar to show it in.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit BGTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.write("launch pid \(getpid())")
        let desktop = DesktopController(store: .standard())
        self.desktop = desktop
        panel = PanelController(desktop: desktop, windowState: windowState) { [weak self] in self?.showWindow() }
        windowState.moveToDisplay = { [weak self] display in self?.moveWindow(toDisplay: display) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                                name: NSApplication.didChangeScreenParametersNotification,
                                                object: nil)
        let env = ProcessInfo.processInfo.environment
        if env["BGTOOLS_OPEN_WINDOW"] != nil { showWindow() }
        if env["BGTOOLS_OPEN_PANEL"] != nil { panel?.open() }
    }

    /// A monitor going away (item 11, `ShowTools Feedback — Worklist for
    /// Next CC Session.md`) can leave an already-open window sitting on a
    /// screen that no longer exists, off in coordinates nothing draws —
    /// unreachable, since `showWindow()`'s own recenter-on-the-calling-
    /// screen logic only runs when the window is (re)opened, not while it's
    /// already open and visible. Recenter it onto the main screen the
    /// moment its own screen disappears from `NSScreen.screens`, rather
    /// than waiting for the next open.
    @objc private func screensChanged() {
        guard let window, window.isVisible, let screen = window.screen,
              !NSScreen.screens.contains(screen), let main = NSScreen.main else { return }
        center(window, on: main)
    }

    /// Opening BGTools again (Finder, Spotlight, `open`) shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// `bgtools://open` shows the panel (the Control Center tile, B5);
    /// `bgtools://window` opens the window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "bgtools" {
            Log.write("url \(url)")
            if url.host == "window" { showWindow() }
            if url.host == "open" { panel?.toggle() }
            if url.host == "show" { desktop?.update { $0.on = url.lastPathComponent == "on" } }
        }
    }

    /// Opens on the monitor with the pointer, that monitor's current Space
    /// already selected (bgtools.md, "The window opens on your screen",
    /// settled: always the calling monitor, whether the window was already
    /// open or not — so this repositions it every call, not just the first).
    func showWindow() {
        guard let desktop else { return }
        let callingScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "BGTools"
            w.isReleasedWhenClosed = false
            // Item 22, `ShowTools Feedback — Worklist for Next CC
            // Session.md`: stays visible across a Space switch, the same
            // treatment the Control Center panel already gets (Panel.swift).
            w.collectionBehavior.insert(.canJoinAllSpaces)
            w.contentView = NSHostingView(rootView: MainWindow().environment(desktop).environment(windowState))
            // The autosave keeps its size across launches; the position is
            // always overridden below, to the calling monitor.
            w.setFrameAutosaveName("BGToolsMain")
            w.delegate = self
            window = w
        }
        if let callingScreen, let w = window { center(w, on: callingScreen) }
        selectCurrentSpace(of: callingScreen, desktop: desktop)
        desktop.keepReaders = true
        // An accessory app has no Dock icon; while its window is open it
        // acts like an ordinary app (Dock, ⌘Tab), and goes back after.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// ⌥-double-click on a screen's box (bgtools.md): moves the window
    /// there without changing the selection, so the screen being set up
    /// can be looked at without dragging the window across by hand.
    func moveWindow(toDisplay display: String) {
        guard let window, let screen = NSScreen.screens.first(where: { $0.displayUUID == display }) else { return }
        center(window, on: screen)
    }

    private func center(_ window: NSWindow, on screen: NSScreen) {
        let size = window.frame.size
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        window.setFrameOrigin(origin)
    }

    private func selectCurrentSpace(of screen: NSScreen?, desktop: DesktopController) {
        guard let screen else { return }
        let display = screen.displayUUID
        let spaces = desktop.screens.filter { $0.key.display == display }
        if let s = spaces.first(where: \.isCurrent) ?? spaces.first { windowState.selection = .screen(s.id) }
    }

    func windowWillClose(_ notification: Notification) {
        if panel?.isOpen != true { desktop?.keepReaders = false }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ note: Notification) {
        desktop?.closeAll()
        Log.write("quit")
    }
}
