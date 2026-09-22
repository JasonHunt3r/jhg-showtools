import AppKit

/// The nested helper: BGTools' stand-in. No window; it only logs that it
/// ran and what URLs reached it.
@main
@MainActor
final class NestHelperApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = NestHelperApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        HelperLog.write("helper LAUNCHED from \(Bundle.main.bundleURL.path), parent pid \(getppid())")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        HelperLog.write("helper got \(urls.map(\.absoluteString).joined(separator: ", "))")
    }
}

enum HelperLog {
    static func write(_ s: String) {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/NestProbe.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(Bundle.main.bundleIdentifier ?? "?")] \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}
