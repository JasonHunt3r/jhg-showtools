import Foundation
import ServiceManagement

/// Starting at login. BGTools is nested inside ShowTools
/// (`Contents/Library/LoginItems`), so it registers as that host's login
/// item by identifier, not as `mainApp`. ShowTools registers it when the
/// desktop is first turned on (`BGToolsHelper.registerAtLogin`); this is
/// the same registration, flipped by the "Open at login" switch, and it
/// shows in System Settings ▸ General ▸ Login Items.
enum LoginItem {
    static let bundleID = "com.jhg.showtools.bgtools"

    private static var service: SMAppService { .loginItem(identifier: bundleID) }

    static var isOn: Bool { service.status == .enabled }

    static func setOn(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
            Log.write("login item \(on ? "registered" : "removed"): \(service.status.rawValue)")
        } catch {
            Log.write("login item \(on ? "register" : "remove") failed: \(error)")
        }
    }
}
