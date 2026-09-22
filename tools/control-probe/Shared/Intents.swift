import AppIntents
import Foundation

/// The "Open BGTools" tile: runs in the app, bringing its window forward.
struct OpenBGToolsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open BGTools"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ProbeLog.write("Open BGTools tile ran")
        return .result()
    }
}

/// The "Desktop Show" tile's on/off. In the probe it only remembers the
/// value (in the extension's own sandbox), to see a toggle work at all.
struct SetDesktopShowIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Desktop Show"
    @Parameter(title: "On") var value: Bool

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(value, forKey: "desktopShowOn")
        return .result()
    }
}

enum ProbeLog {
    /// ~/Library/Logs, for the unsandboxed app; the sandboxed extension
    /// can't write there, so it logs nothing.
    static func write(_ s: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BGControlProbe.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}
