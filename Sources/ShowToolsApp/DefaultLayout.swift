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
    @MainActor static func restore() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })
        else { return }

        var frame = window.frame
        // Grow from the top-left, the corner AppKit keeps still, so the
        // title bar doesn't slide out from under the pointer.
        frame.origin.y += frame.height - windowSize.height
        frame.size = windowSize
        if let screen = window.screen ?? NSScreen.main {
            frame = constrain(frame, to: screen.visibleFrame)
        }
        window.setFrame(frame, display: true, animate: true)

        guard let content = window.contentView else { return }
        // The sidebar is SwiftUI's own NavigationSplitView. It is the
        // outermost plain NSSplitView in the window; Edit Show's columns
        // are a ColumnsSplitView, which is asked separately.
        for split in splitViews(in: content) {
            if let columns = split as? ColumnsSplitView {
                columns.setWidths(list: listWidth, inspector: inspectorWidth)
            } else if split.isVertical, split.arrangedSubviews.count >= 2 {
                split.setPosition(sidebarWidth, ofDividerAt: 0)
            }
        }
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
