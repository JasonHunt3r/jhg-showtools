import AppKit
import ServiceManagement
import SwiftUI

/// The host: an ordinary Xcode-built app. It carries the tile extension
/// and, nested in Contents/Library/LoginItems, the helper.
@main
struct NestHostApp: App {
    @NSApplicationDelegateAdaptor(HostDelegate.self) var delegate

    var body: some Scene {
        Window("NestProbe", id: "main") {
            VStack(spacing: 10) {
                Text("NestProbe host").font(.title2)
                Text("Helper: \(HostDelegate.helperURL?.path ?? "missing")")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Register the helper at login") { HostDelegate.registerHelper() }
                Button("Launch the helper") { HostDelegate.launchHelper() }
            }
            .padding(30)
            .frame(width: 520)
        }
    }
}

final class HostDelegate: NSObject, NSApplicationDelegate {
    static var helperURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/NestHelper.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        ProbeLog.write("host launched from \(Bundle.main.bundleURL.path)")
        // Registering on launch, so the measurement needs no clicking.
        Self.registerHelper()
    }

    /// The nested-helper way: SMAppService.loginItem(identifier:).
    static func registerHelper() {
        let service = SMAppService.loginItem(identifier: "com.jhg.nestprobe.helper")
        do {
            try service.register()
            ProbeLog.write("helper registered at login, status \(service.status.rawValue)")
        } catch {
            ProbeLog.write("helper register FAILED: \(error), status \(service.status.rawValue)")
        }
    }

    static func launchHelper() {
        guard let helperURL else { return ProbeLog.write("no helper to launch") }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { _, error in
            ProbeLog.write("helper launch \(error.map { "FAILED: \($0)" } ?? "ok")")
        }
    }
}

enum ProbeLog {
    static func write(_ s: String) {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/NestProbe.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(Bundle.main.bundleIdentifier ?? "?")] \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}
