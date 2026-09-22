import Foundation
import ServiceManagement

/// Starting at login. `SMAppService.mainApp` works even ad hoc signed
/// (measured 2026-09-22 with two probes), and gives BGTools a switch of
/// its own in System Settings ▸ General ▸ Login Items.
enum LoginItem {
    /// Registered the first time BGTools runs from `~/Applications`, so
    /// the desktop is there after a restart without being asked for.
    static let askedKey = "registeredAtLogin"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func setOn(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.write("login item \(on ? "registered" : "removed"): \(SMAppService.mainApp.status.rawValue)")
        } catch {
            Log.write("login item \(on ? "register" : "remove") failed: \(error)")
        }
        UserDefaults.standard.set(true, forKey: askedKey)
    }

    /// On the first run of an installed copy, register. A test copy run
    /// from the build folder never does.
    static func registerOnceIfInstalled(bundle: Bundle = .main,
                                        defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: askedKey),
              bundle.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications" else { return }
        setOn(true)
    }
}
