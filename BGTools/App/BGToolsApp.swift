import AppKit
import BGToolsCore

/// BGTools: ShowTools shows as the desktop picture (spec/bgtools.md).
/// What each monitor and Space plays is in its settings file;
/// `BGTOOLS_SETTINGS` points tests at their own (never the real library).
@main
@MainActor
final class BGToolsApp: NSObject, NSApplicationDelegate {
    private var desktop: DesktopController?

    static func main() {
        let app = NSApplication.shared
        let delegate = BGToolsApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.write("launch pid \(getpid())")
        desktop = DesktopController(store: .standard())
    }

    func applicationWillTerminate(_ note: Notification) {
        desktop?.closeAll()
        Log.write("quit")
    }
}
