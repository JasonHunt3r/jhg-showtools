import AppKit
import ServiceManagement
import ShowToolsCore

/// BGTools lives inside ShowTools, at `Contents/Library/LoginItems/BGTools.app`
/// (spec/xcode-port.md). Nothing is copied out any more: View ▸ Desktop Show…
/// launches the nested copy and registers it to start at login, and deleting
/// ShowTools takes BGTools, its tiles and its login item with it.
enum BGToolsHelper {
    static let bundleID = "com.jhg.showtools.bgtools"

    /// The nested BGTools, or nil under `swift run`, which has no bundle.
    static var nestedURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/BGTools.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// ShowTools owns the decision to start BGTools at login; BGTools no
    /// longer registers itself on first run. Its "Open at login" switch
    /// flips this same registration.
    static func registerAtLogin() {
        let service = SMAppService.loginItem(identifier: bundleID)
        guard service.status != .enabled else { return }
        do { try service.register() } catch {
            NSLog("BGTools login registration failed: \(error)")
        }
    }

    static func unregisterAtLogin() {
        let service = SMAppService.loginItem(identifier: bundleID)
        guard service.status == .enabled else { return }
        do { try service.unregister() } catch {
            NSLog("BGTools login unregistration failed: \(error)")
        }
    }

    static var isRegisteredAtLogin: Bool {
        SMAppService.loginItem(identifier: bundleID).status == .enabled
    }

    /// Launches BGTools and opens its window.
    static func openDesktop() throws {
        guard let nestedURL else { throw BGToolsError.notBundled }
        registerAtLogin()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: nestedURL, configuration: config) { _, error in
            if let error { return NSLog("BGTools didn't open: \(error)") }
            // BGTools has no window of its own at launch (it's an agent),
            // so ask it for one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSWorkspace.shared.open(URL(string: "bgtools://window")!)
            }
        }
    }

    /// Item 21, `ShowTools Feedback — Worklist for Next CC Session.md`:
    /// "Launch BGT when launching ShowTools." No window request — this is
    /// meant to be silent, just getting the desktop background ready, not
    /// popping BGTools' own window in front of ShowTools' every time it
    /// opens. A no-op if it's already running (its own accessory-app
    /// activation policy means a second launch would still just reopen it
    /// quietly, but there's no reason to ask twice).
    static func launchAtShowToolsStartupIfEnabled() {
        guard UserDefaults.standard.bool(forKey: launchWithShowToolsKey), let nestedURL else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        NSWorkspace.shared.openApplication(at: nestedURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("BGTools didn't open at ShowTools launch: \(error)") }
        }
    }

    static let launchWithShowToolsKey = "launchBGToolsWithShowTools"
}

enum BGToolsError: LocalizedError {
    case notBundled

    var errorDescription: String? {
        "This build of ShowTools doesn't carry BGTools. Build it with make-app.sh."
    }
}
