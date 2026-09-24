import AppKit

/// The window arrangement View ▸ Restore Default Layout goes back to.
///
/// Why it exists: on 2026-09-23 a double-click on the sidebar divider —
/// a touch-and-hold read as a double-click, because the dividers are hard
/// to grab — took the sidebar from 180pt to 1355pt in a 1374pt window,
/// pushing everything else off the right edge. There was no default to
/// return to and no command to ask for one, and the app saves its layout
/// on quit, so the only way back was editing preferences from outside.
/// A layout a person can break in one click needs a way back in one click.
///
/// The numbers are Jason's own arrangement, set by hand and captured
/// 2026-09-23. They are the defaults for a fresh library too, so a first
/// launch opens the way he works.
enum DefaultLayout {
    /// Size only. Where the window sits is left alone: a window that is
    /// the right shape in the wrong place is a smaller problem than one
    /// that jumps across the screen when you ask for its columns back.
    static let windowSize = NSSize(width: 1376, height: 835)
    static let sidebarWidth: CGFloat = 219
    /// Edit Show's own columns (`ColumnsSplitView`).
    static let listWidth: CGFloat = 246
    static let inspectorWidth: CGFloat = 320

    /// Puts the live views back, rather than writing preferences and
    /// waiting for a relaunch: the point is to rescue a window that is
    /// unusable *now*. Preferences follow, because each view saves its
    /// own width as it changes.
    /// UNPROVEN (2026-09-24): the staging below was written while the
    /// layout-loop crash was still unexplained, and its real cause turned
    /// out to be SwiftUI's .inspector(). It may be unnecessary, or not the
    /// right fix. PaneKit replaces it with one layout transaction
    /// (spec/panekit.md); until then, leave it be.
    /// **One change per run-loop turn, and no animation.** Doing all three
    /// in one pass is what made ⌥⌘0 raise AppKit's layout-loop exception
    /// and, once, kill the app (2026-09-23; the reason string is in the
    /// handoff). Each change moves a hosting view, each move makes SwiftUI
    /// report a new minimum size, and a second change arriving inside that
    /// same constraints pass gives the window another reason to go round.
    /// Handing back to the run loop lets one settle before the next.
    @MainActor static func restore() {
        // The *main* window, by name. "the first visible window" picked up
        // whichever panel happened to be open — the Rhythm panel, Get Info
        // — and quietly resized that instead, which is why the command
        // looked like it did nothing at all (Jason, 2026-09-23).
        let window = NSApp.windows.first { $0.frameAutosaveName == "main" }
            ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
        guard let window else { return }
        steps(for: window).forEach(later)
    }

    /// Runs `work` on its own turn of the run loop, in order.
    @MainActor private static var pending: [@MainActor () -> Void] = []
    @MainActor private static func later(_ work: @escaping @MainActor () -> Void) {
        pending.append(work)
        guard pending.count == 1 else { return }   // one drain at a time
        func drain() {
            guard !pending.isEmpty else { return }
            pending.removeFirst()()
            DispatchQueue.main.async { drain() }
        }
        DispatchQueue.main.async { drain() }
    }

    @MainActor private static func steps(for window: NSWindow) -> [@MainActor () -> Void] {
        [
            {
                var frame = window.frame
                // Grow from the top-left, the corner AppKit keeps still, so
                // the title bar doesn't slide out from under the pointer.
                frame.origin.y += frame.height - windowSize.height
                frame.size = windowSize
                if let screen = window.screen ?? NSScreen.main {
                    frame = constrain(frame, to: screen.visibleFrame)
                }
                window.setFrame(frame, display: true, animate: false)
            },
            // STALE REASONING (2026-09-24): the next lines were written
            // before the layout-loop crash's confirmed cause was found —
            // SwiftUI's .inspector() (spec/history/2026-09-23-crash-hunt-
            // session3.md) — and the sidebar was only a suspect by
            // coincidence. Restoring it is worth trying again.
            // The sidebar is deliberately NOT restored here. It is
            // SwiftUI's own NavigationSplitView, and setting its divider
            // from outside is what raised AppKit's layout-loop exception
            // — measured 2026-09-23, and staging the changes a run-loop
            // turn apart didn't help, so it is the poking and not the
            // timing. It no longer needs rescuing anyway: the sidebar is
            // capped at 360 (MainView), so the worst it can do now is be
            // too wide, which one drag undoes. Only the two things this
            // app owns outright are put back.
            {
                guard let content = window.contentView else { return }
                for case let columns as ColumnsSplitView in splitViews(in: content) {
                    columns.setWidths(list: listWidth, inspector: inspectorWidth)
                }
            },
        ]
    }

    /// Keeps a window on screen without changing its size.
    private static func constrain(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var f = frame
        f.origin.x = min(max(f.origin.x, visible.minX), max(visible.maxX - f.width, visible.minX))
        f.origin.y = min(max(f.origin.y, visible.minY), max(visible.maxY - f.height, visible.minY))
        return f
    }

    /// Every split view under `view`, outermost first.
    private static func splitViews(in view: NSView) -> [NSSplitView] {
        var found: [NSSplitView] = []
        if let split = view as? NSSplitView { found.append(split) }
        for sub in view.subviews { found += splitViews(in: sub) }
        return found
    }
}
