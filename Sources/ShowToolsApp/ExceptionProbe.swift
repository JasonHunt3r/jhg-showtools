import AppKit
import ObjectiveC

/// Records the *reason* of every Objective-C exception the app raises.
///
/// Why this is in the shipped app rather than a scratch probe: ShowTools
/// aborted 25 times on 2026-09-22, always the same way — an exception
/// raised from `-[NSWindow _postWindowNeedsUpdateConstraints]` while
/// AppKit was already inside its layout pass, within twenty seconds of
/// launch. The crash report keeps the backtrace but not the exception's
/// reason string, which is the one fact that names the fault. macOS sends
/// that string to the unified log, which returns nothing from this app in
/// Claude's sandbox (CLAUDE.md), so it goes to a file instead. It is
/// intermittent and it happens during real use, so the catcher has to be
/// in the build Jason actually runs.
///
/// Both crash paths are watched. The AppKit one traps inside
/// `+[NSApplication _crashOnException:]`, which never reaches an uncaught
/// handler, so what's hooked is `+[NSException exceptionWithName:reason:userInfo:]`
/// — frame 2 of every one of the 25 reports. The uncaught handler catches
/// anything raised another way.
///
/// Delete this once the crash is named.
enum ExceptionProbe {
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ShowTools-exception.log")

    private typealias ExceptionWithName =
        @convention(c) (AnyObject, Selector, NSExceptionName, String?, [AnyHashable: Any]?) -> NSException
    // nonisolated(unsafe): both are written once, before any window
    // exists, and the recursion guard is only read on the thread that
    // is already raising. A lock here would be one more thing to hang
    // on the way to a crash.
    nonisolated(unsafe) private static var original: ExceptionWithName?
    private static let selector = NSSelectorFromString("exceptionWithName:reason:userInfo:")
    /// An exception raised while recording one would recurse forever.
    nonisolated(unsafe) private static var recording = false

    static func install() {
        NSSetUncaughtExceptionHandler { ExceptionProbe.record($0, how: "uncaught") }

        guard original == nil,
              let method = class_getClassMethod(NSException.self, selector) else { return }
        original = unsafeBitCast(method_getImplementation(method), to: ExceptionWithName.self)
        let watcher: @convention(block) (AnyObject, NSExceptionName, String?, [AnyHashable: Any]?)
            -> NSException = { cls, name, reason, info in
            let exception = original!(cls, selector, name, reason, info)
            record(exception, how: "raised")
            return exception
        }
        method_setImplementation(method, imp_implementationWithBlock(watcher))
    }

    /// Appends one entry. Never throws, and never raises: this runs on the
    /// way to a crash, and the point is the file, not tidiness.
    private static func record(_ exception: NSException, how: String) {
        guard !recording else { return }
        recording = true
        defer { recording = false }

        var entry = "\n\(Date()) \(how) \(exception.name.rawValue)\n"
        entry += "reason: \(exception.reason ?? "(none)")\n"
        for line in Thread.callStackSymbols { entry += "  \(line)\n" }

        guard let data = entry.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
