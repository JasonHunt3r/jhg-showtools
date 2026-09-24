import AppKit

/// A popped-out pane's window: a panel that floats, or an ordinary window
/// that can go behind (`PopOutStyle`). It shares the main window's undo
/// manager, so ⌘Z here undoes the same history. Closing it puts the pane
/// back in its slot.
@MainActor
final class PaneWindowController: NSObject, NSWindowDelegate {
    let paneID: String
    let window: NSWindow
    private weak var controller: PaneController?
    private var host: PaneHostView?
    /// True while PaneKit itself closes the window, so the close isn't
    /// taken as the user asking to put the pane back.
    private var closingQuietly = false

    init(pane: Pane, host: PaneHostView, frame: CGRect?, near parent: NSWindow?, controller: PaneController) {
        paneID = pane.id
        self.controller = controller
        self.host = host
        let size = host.frame.size.width > 50 && host.frame.size.height > 50
            ? host.frame.size : CGSize(width: 360, height: 480)
        let start = frame ?? CGRect(origin: .zero, size: size)
        let undo = controller.undoSource ?? parent
        switch pane.popOut {
        case .panel:
            let panel = PanePanel(contentRect: start,
                                  styleMask: [.titled, .closable, .resizable, .utilityWindow],
                                  backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.undoSource = undo
            window = panel
        case .window, .none:
            let w = PaneWindow(contentRect: start,
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
            w.undoSource = undo
            window = w
        }
        super.init()
        window.title = pane.title
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: max(pane.minSize, 120), height: max(pane.minSize, 120))
        let content = NSView(frame: CGRect(origin: .zero, size: start.size))
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)
        window.contentView = content
        if frame == nil, let parent {
            // Beside the main window, not on top of what it came from.
            let p = parent.frame
            window.setFrameOrigin(CGPoint(x: min(p.maxX + 12, (parent.screen?.visibleFrame.maxX ?? p.maxX) - size.width),
                                          y: p.maxY - size.height - 40))
        }
        window.delegate = self
        window.orderFront(nil)
    }

    /// Gives the pane's host back for its slot.
    func releaseHost() -> PaneHostView {
        let h = host!
        h.removeFromSuperview()
        host = nil
        return h
    }

    /// Closes the window without it counting as the user putting the pane
    /// back (the pane is already on its way back).
    func closeQuietly() {
        closingQuietly = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingQuietly else { return }
        controller?.windowClosed(paneID)
    }

    func windowDidMove(_ notification: Notification) {
        controller?.recordFrame(window.frame, for: paneID)
    }

    func windowDidResize(_ notification: Notification) {
        controller?.recordFrame(window.frame, for: paneID)
    }
}

/// A floating pane window whose undo is the main window's.
@MainActor
final class PanePanel: NSPanel {
    weak var undoSource: NSWindow?
    override var undoManager: UndoManager? { undoSource?.undoManager ?? super.undoManager }
}

/// An ordinary pane window whose undo is the main window's.
@MainActor
final class PaneWindow: NSWindow {
    weak var undoSource: NSWindow?
    override var undoManager: UndoManager? { undoSource?.undoManager ?? super.undoManager }
}
