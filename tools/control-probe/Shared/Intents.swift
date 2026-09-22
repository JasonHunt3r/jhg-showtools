import AppIntents
import AppKit

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

/// Part 6: can a tile change the running app without bringing it forward?
/// Three routes, one tile each. Every perform logs which process ran it.
enum NextColour {
    static let notification = Notification.Name("com.jhg.BGControlProbe.nextColour")
    static let url = URL(string: "bgcontrolprobe://next")!
    static var inApp: Bool { Bundle.main.bundleIdentifier == "com.jhg.BGControlProbe" }
}

/// Route A: a distributed notification (a sandboxed poster may send a
/// name, never userInfo).
struct NextColourByNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Colour (notification)"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        ProbeLog.write("A notification tile ran")
        DistributedNotificationCenter.default().postNotificationName(NextColour.notification, object: "A", userInfo: nil, deliverImmediately: true)
        return .result()
    }
}

/// Route B: open a URL the app handles, asking it not to come forward.
struct NextColourByURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Colour (URL)"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        ProbeLog.write("B URL tile ran")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        do { try await NSWorkspace.shared.open(NextColour.url, configuration: config); ProbeLog.write("B open ok") }
        catch { ProbeLog.write("B open failed: \(error)") }
        return .result()
    }
}

/// Route C: nothing but the intent. If the system runs it in the app
/// (the type is compiled into both), it can act directly.
struct NextColourDirectIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Colour (direct)"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        ProbeLog.write("C direct tile ran")
        if NextColour.inApp { await MainActor.run { ColourState.shared.next(via: "C") } }
        return .result()
    }
}

/// The app's swatch. Compiled into the extension too (for route C's
/// check), where it's never shown.
@MainActor final class ColourState: ObservableObject {
    static let shared = ColourState()
    @Published var index = 0
    @Published var last = "nothing yet"
    func next(via route: String) {
        index += 1
        last = "\(route) at \(Date().formatted(date: .omitted, time: .standard))"
        ProbeLog.write("colour → \(index) via \(route)")
    }
}

enum ProbeLog {
    /// ~/Library/Logs for the app; the sandboxed extension's home is its
    /// container, so its lines land in
    /// ~/Library/Containers/com.jhg.BGControlProbe.BGControls/Data/Library/Logs.
    static func write(_ s: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("BGControlProbe.log")
        let who = Bundle.main.bundleIdentifier ?? "?"
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(who) pid \(getpid())] \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? Data(line.utf8).write(to: url) }
    }
}
