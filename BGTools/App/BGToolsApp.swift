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
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.write("launch pid \(getpid())")
        let desktop = DesktopController(store: .standard())
        self.desktop = desktop
        panel = PanelController(desktop: desktop, windowState: windowState) { [weak self] in self?.showWindow() }
        let env = ProcessInfo.processInfo.environment
        if env["BGTOOLS_OPEN_WINDOW"] != nil { showWindow() }
        if env["BGTOOLS_OPEN_PANEL"] != nil { panel?.open() }
        LoginItem.registerOnceIfInstalled()
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

    func showWindow() {
        guard let desktop else { return }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "BGTools"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainWindow().environment(desktop).environment(windowState))
            w.center()
            w.setFrameAutosaveName("BGToolsMain")
            w.delegate = self
            window = w
        }
        desktop.keepReaders = true
        // An accessory app has no Dock icon; while its window is open it
        // acts like an ordinary app (Dock, ⌘Tab), and goes back after.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
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
