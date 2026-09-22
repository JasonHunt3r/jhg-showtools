import AppKit
import ShowToolsCore

/// B2 skeleton: plays one show on every monitor and Space. Which library
/// and show come from the environment for now, and a library is required:
/// tests never use the real one (CLAUDE.md).
///   BGTOOLS_LIBRARY=<library folder>  BGTOOLS_SHOW=<show id or name>
@main
@MainActor
final class BGToolsApp: NSObject, NSApplicationDelegate {
    private var reader: LibraryReader?
    private var desktop: DesktopController?

    static func main() {
        let app = NSApplication.shared
        let delegate = BGToolsApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let env = ProcessInfo.processInfo.environment
        Log.write("launch pid \(getpid())")
        guard let path = env["BGTOOLS_LIBRARY"] else {
            Log.write("no BGTOOLS_LIBRARY: nothing to play")
            return
        }
        do {
            let reader = try LibraryReader(root: URL(fileURLWithPath: path))
            self.reader = reader
            let wanted = env["BGTOOLS_SHOW"]
            guard let show = reader.shows.first(where: { wanted == nil || "\($0.id)" == wanted || $0.name == wanted }) else {
                Log.write("no show \(wanted ?? "(first)") in \(path)")
                return
            }
            Log.write("playing \"\(show.name)\" (#\(show.id))")
            desktop = DesktopController(source: reader, showID: show.id)
        } catch {
            Log.write("can't open \(path): \(error)")
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        desktop?.closeAll()
        reader?.close()
        Log.write("quit")
    }
}
