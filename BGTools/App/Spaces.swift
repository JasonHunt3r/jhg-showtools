import AppKit

/// Spaces have no public identity. These are the unofficial CoreGraphics
/// calls yabai and Hammerspoon use; they exist on macOS 27.0 (measured).
/// If an update removes them, `available` is false and each display gets
/// one window on every Space instead.
enum Spaces {
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>
    private typealias MoveFn = @convention(c) (Int32, CFArray, CFArray) -> Void

    nonisolated(unsafe) private static let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    private static let connFn = dlsym(cg, "CGSMainConnectionID").map { unsafeBitCast($0, to: ConnFn.self) }
    private static let copyFn = dlsym(cg, "CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: CopyFn.self) }
    private static let addFn = dlsym(cg, "CGSAddWindowsToSpaces").map { unsafeBitCast($0, to: MoveFn.self) }
    private static let removeFn = dlsym(cg, "CGSRemoveWindowsFromSpaces").map { unsafeBitCast($0, to: MoveFn.self) }

    static var available: Bool { connFn != nil && copyFn != nil && addFn != nil && removeFn != nil }

    struct Space: Hashable {
        /// Changes when a display is plugged back in (19 → 23, measured):
        /// only for placing windows, never for remembering.
        let id: Int
        /// Lasting. Empty for the main display's first desktop.
        let uuid: String
        /// 1-based, as Mission Control numbers them.
        let index: Int
    }

    /// Each display's ordinary desktops (not full-screen apps), by the
    /// display's UUID.
    static func desktops() -> [String: [Space]] {
        guard let connFn, let copyFn else { return [:] }
        let displays = copyFn(connFn()).takeRetainedValue() as? [[String: Any]] ?? []
        var out: [String: [Space]] = [:]
        for d in displays {
            guard let display = d["Display Identifier"] as? String else { continue }
            let spaces = (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int) == 0 }
            out[display] = spaces.enumerated().map { i, s in
                Space(id: s["ManagedSpaceID"] as? Int ?? 0, uuid: s["uuid"] as? String ?? "", index: i + 1)
            }
        }
        return out
    }

    /// The uuid of the Space each display is showing now, by display UUID.
    static func current() -> [String: String] {
        guard let connFn, let copyFn else { return [:] }
        let displays = copyFn(connFn()).takeRetainedValue() as? [[String: Any]] ?? []
        var out: [String: String] = [:]
        for d in displays {
            guard let display = d["Display Identifier"] as? String,
                  let cur = d["Current Space"] as? [String: Any] else { continue }
            out[display] = cur["uuid"] as? String ?? ""
        }
        return out
    }

    /// Puts the window on one Space only.
    static func move(_ window: NSWindow, to space: Int) {
        guard let connFn, let addFn, let removeFn else { return }
        let w = [NSNumber(value: window.windowNumber)] as CFArray
        let all = desktops().values.flatMap { $0 }.map { NSNumber(value: $0.id) } as CFArray
        removeFn(connFn(), w, all)
        addFn(connFn(), w, [NSNumber(value: space)] as CFArray)
    }
}

extension NSScreen {
    /// The display's lasting id: a monitor plugged back in has the same one.
    var displayUUID: String {
        let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        guard let u = CGDisplayCreateUUIDFromDisplayID(n)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, u) as String
    }
}
