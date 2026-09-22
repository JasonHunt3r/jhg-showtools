import AppKit
import ShowToolsCore

/// ShowTools carries BGTools inside it and copies it to `~/Applications`
/// the first time the desktop is turned on, replacing the copy whenever
/// this build carries a newer one (Jason, 2026-09-22; spec/bgtools.md,
/// question 6). Deleting ShowTools leaves BGTools behind, on purpose.
enum BGToolsInstall {
    static let installedURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/BGTools.app")

    /// The copy inside ShowTools.app, or nil in a `swift run` build.
    static var bundledURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/BGTools.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleVersion"] as? String
    }

    /// Versions rarely change while BGTools is being built, so a newer
    /// executable counts as newer too.
    static func isNewer(_ a: URL, than b: URL) -> Bool {
        func built(_ app: URL) -> Date {
            (try? FileManager.default.attributesOfItem(atPath: app.appendingPathComponent("Contents/MacOS/BGTools").path))?[.modificationDate] as? Date ?? .distantPast
        }
        return built(a) > built(b)
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedURL.path) }

    /// Copies BGTools out if it isn't there, or if this build carries a
    /// different version. Returns where it is, or throws.
    @discardableResult
    static func install() throws -> URL {
        guard let bundledURL else { throw BGToolsInstallError.notBundled }
        let fm = FileManager.default
        if isInstalled, version(of: installedURL) == version(of: bundledURL), !isNewer(bundledURL, than: installedURL) {
            return installedURL
        }
        try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A copy in place of a running BGTools would leave it half-written,
        // so it's quit first, then replaced whole.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.jhg.bgtools") {
            app.terminate()
        }
        let staged = installedURL.deletingLastPathComponent()
            .appendingPathComponent(".BGTools-new-\(UUID().uuidString).app")
        try fm.copyItem(at: bundledURL, to: staged)
        if isInstalled { _ = try fm.replaceItemAt(installedURL, withItemAt: staged) }
        else { try fm.moveItem(at: staged, to: installedURL) }
        return installedURL
    }

    /// Installs if needed and opens BGTools' window.
    static func openDesktop() throws {
        let app = try install()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: config) { running, error in
            if let error { return NSLog("BGTools didn't open: \(error)") }
            // BGTools has no window of its own at launch (it's a menu-bar
            // -less agent), so ask it for one.
            _ = running
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSWorkspace.shared.open(URL(string: "bgtools://window")!)
            }
        }
    }
}

enum BGToolsInstallError: LocalizedError {
    case notBundled

    var errorDescription: String? {
        "This build of ShowTools doesn't carry BGTools. Build it with make-app.sh."
    }
}
