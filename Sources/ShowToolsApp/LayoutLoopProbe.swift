import AppKit
import ObjectiveC

/// Names the view driving the layout-loop crash (`spec/status.md`, "Known
/// issues" — `NSGenericException` from AppKit's layout-loop guard). The
/// exception's stack trace names AppKit's dispatch machinery, never the
/// SwiftUI content that keeps asking for another pass, so two prior
/// sessions (`spec/history/2026-09-23-crash-hunt*.md`) could narrow the
/// bug to a symbol (`SplitViewChildController`) but not a view.
///
/// This swizzles `-[NSView setNeedsUpdateConstraints:]`, the one call in
/// the loop's own stack that carries the view itself, and keeps a ring
/// buffer of the last views to ask — with the *hosting view's* dynamic
/// class name, which for `NSHostingView<Content>` encodes `Content`'s
/// type and so names the SwiftUI subtree, not just "NSHostingView".
/// `ExceptionProbe` appends the buffer to its log entry.
///
/// Delete with `ExceptionProbe` once the crash is named.
enum LayoutLoopProbe {
    private struct Entry {
        let seq: Int
        let cls: String
        let frame: String
        let window: String
    }

    // nonisolated(unsafe): AppKit's layout pass, and the exception it can
    // raise, both happen on the main thread — same reasoning as
    // ExceptionProbe. No lock, so this adds nothing to hang on.
    nonisolated(unsafe) private static var ring: [Entry] = []
    nonisolated(unsafe) private static var seq = 0
    private static let capacity = 80

    // Swift's NSView overlay exposes this as the `needsUpdateConstraints`
    // property, not a `setNeedsUpdateConstraints(_:)` method, so the
    // selector has to be built by hand rather than with `#selector`.
    private static let selector = NSSelectorFromString("setNeedsUpdateConstraints:")

    static func install() {
        guard let method = class_getInstanceMethod(NSView.self, selector) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let block: @convention(block) (AnyObject, Bool) -> Void = { obj, flag in
            // NSView layout is main-thread only, and this hook fires from
            // inside AppKit's own layout pass, so the isolation is real,
            // just not visible to the compiler through an ObjC swizzle.
            if let view = obj as? NSView { MainActor.assumeIsolated { record(view) } }
            original(obj, selector, flag)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    @MainActor
    private static func record(_ view: NSView) {
        seq += 1
        let entry = Entry(seq: seq,
                           cls: NSStringFromClass(type(of: view)),
                           frame: NSStringFromRect(view.frame),
                           window: view.window.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "-")
        ring.append(entry)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
    }

    /// The last calls, most recent last — read at exception time, so this
    /// never allocates on the recursion-guard path in `ExceptionProbe`.
    static func dump() -> String {
        ring.map { "  [\($0.seq)] \($0.cls) \($0.frame) win=\($0.window)" }.joined(separator: "\n")
    }
}
