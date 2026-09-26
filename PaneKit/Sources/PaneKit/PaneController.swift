import AppKit
import Observation

/// Owns a layout's state, and makes every change to it one **transaction**:
/// set everything in the model, lay out once, save, broadcast once
/// (spec/panekit.md, "Layout transactions"). Nothing half-moved is drawn,
/// and no change sets off another.
///
/// It's `@Observable`, so SwiftUI menus and toolbar buttons can follow
/// `state` (whether a pane is open, or out in a window).
@MainActor @Observable
public final class PaneController {
    /// Names the saved state (`PaneKit.<id>` in the preferences).
    public let id: String
    public let root: PaneNode
    /// What the layout is now.
    public private(set) var state: PaneKitState

    /// Posted once per transaction, with the controller as the object.
    public static let didChange = Notification.Name("PaneKit.didChange")

    /// Called once per transaction, after the layout.
    @ObservationIgnored public var onChange: ((PaneKitState) -> Void)?
    /// The main window, whose undo manager a popped-out pane's window
    /// shares, so ⌘Z there undoes the same history (the Info panel's
    /// pattern: a separate window's undo manager isn't the main window's).
    @ObservationIgnored public weak var undoSource: NSWindow?

    @ObservationIgnored weak var container: PaneContainerView?
    @ObservationIgnored var windows: [String: PaneWindowController] = [:]
    /// A drag in progress: drawn, not saved, until the drag ends.
    @ObservationIgnored var live: PaneKitState?
    @ObservationIgnored private let store: UserDefaults
    private var storeKey: String { "PaneKit.\(id)" }

    public init(id: String, root: PaneNode, store: UserDefaults = .standard) {
        self.id = id
        self.root = root
        self.store = store
        if let data = store.data(forKey: "PaneKit.\(id)"),
           let saved = try? JSONDecoder().decode(PaneKitState.self, from: data) {
            state = saved
        } else {
            state = PaneKitState()
        }
    }

    /// What's drawn: the state, or a drag in progress over it.
    var displayState: PaneKitState { live ?? state }

    // MARK: Asking

    /// Whether a split's sized side is open (not closed to its edge).
    public func isOpen(_ splitID: String) -> Bool { !state.isCollapsed(splitID) }
    public func isPoppedOut(_ paneID: String) -> Bool { state.isPoppedOut(paneID) }
    /// Every window a pane is out in, for an app that needs to reach them
    /// (its window-level keys, say).
    public var poppedOutWindows: [NSWindow] { windows.values.map(\.window) }

    // MARK: Changing: every change is one transaction

    /// The one way the layout changes: `change` edits a copy of the state;
    /// then one layout, one save, one broadcast. No-op if nothing changed.
    public func perform(_ change: (inout PaneKitState) -> Void) {
        var next = state
        change(&next)
        live = nil
        guard next != state else { return }
        state = next
        save()
        container?.needsLayout = true
        syncWindows()
        onChange?(state)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// A `linkedAncestor` split (`.row`'s `nearIsRigid`) now also keeps
    /// `near` unmoved when `far` collapses or reopens, not just on a direct
    /// drag: the freed space goes to `main` instead — item 1,
    /// `ShowTools Feedback — Worklist for Next CC Session.md`. Before this,
    /// a collapse skipped the link (`PaneModel.row`'s own doc comment said
    /// so), so closing the inspector grew the list column, not the preview.
    public func setOpen(_ splitID: String, _ open: Bool) {
        perform { s in
            let wasOpen = !(s.splits[splitID]?.collapsed ?? false)
            s.splits[splitID, default: SplitState()].collapsed = !open
            guard open != wasOpen, let split = root.split(splitID), let ancestorID = split.linkedAncestor,
                  let ancestor = root.split(ancestorID) else { return }
            let ownSize = s.splits[splitID]?.size ?? split.defaultSize
            let delta = ownSize + PaneLayout.dividerThickness - PaneLayout.closedThickness(split)
            var ancestorState = s.splits[ancestorID] ?? SplitState()
            let current = ancestorState.size ?? ancestor.defaultSize
            let next = current + (open ? delta : -delta)
            ancestorState.size = min(max(next, ancestor.range.lowerBound), ancestor.range.upperBound)
            s.splits[ancestorID] = ancestorState
        }
    }

    public func toggle(_ splitID: String) { setOpen(splitID, !isOpen(splitID)) }

    /// Moves a pane into a panel or window of its own. Its slot closes up;
    /// its place in the tree is kept, so putting it back returns it there.
    public func popOut(_ paneID: String) {
        guard let pane = root.pane(paneID), pane.popOut != .none else { return }
        perform { $0.panes[paneID, default: PaneWindowState()].poppedOut = true }
    }

    public func putBack(_ paneID: String) {
        perform { $0.panes[paneID, default: PaneWindowState()].poppedOut = false }
    }

    public func togglePopOut(_ paneID: String) {
        isPoppedOut(paneID) ? putBack(paneID) : popOut(paneID)
    }

    /// Every pane back to its default size, open, and in the window.
    public func restoreDefaults() { perform { $0 = PaneKitState() } }

    /// A preset is a state; applying it is one transaction. Window frames
    /// already known are kept, so a pane popping out lands where it was.
    public func apply(_ preset: PaneKitState) {
        perform { current in
            var next = preset
            for (id, s) in current.panes where next.panes[id]?.windowFrame == nil {
                next.panes[id, default: PaneWindowState()].windowFrame = s.windowFrame
            }
            current = next
        }
    }

    // MARK: Drags (drawn live, saved on release)

    func liveChange(_ change: (inout PaneKitState) -> Void) {
        var next = live ?? state
        change(&next)
        live = next
        container?.needsLayout = true
    }

    /// Ends a drag: what it drew becomes the state, in one transaction.
    func endLive() {
        guard let finished = live else { return }
        perform { $0 = finished }
    }

    // MARK: Windows

    /// Where a popped-out pane's window was: remembered, but not a layout
    /// change, so it's saved without a transaction.
    func recordFrame(_ frame: CGRect, for paneID: String) {
        state.panes[paneID, default: PaneWindowState()].windowFrame = frame
        save()
    }

    /// The user closed a popped-out pane's window: it goes back in its slot.
    func windowClosed(_ paneID: String) {
        windows[paneID] = nil
        if isPoppedOut(paneID) { putBack(paneID) }
    }

    /// Makes the windows match the state: opens one for each pane that's
    /// out, and closes the ones whose pane has come back.
    func syncWindows() {
        guard let container, container.window != nil else { return }
        for pane in root.panes {
            let out = state.isPoppedOut(pane.id)
            if out, windows[pane.id] == nil, let host = container.takeHost(pane.id) {
                windows[pane.id] = PaneWindowController(pane: pane, host: host,
                                                        frame: state.panes[pane.id]?.windowFrame,
                                                        near: container.window, controller: self)
            } else if !out, let w = windows.removeValue(forKey: pane.id) {
                container.returnHost(w.releaseHost(), for: pane.id)
                w.closeQuietly()
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { store.set(data, forKey: storeKey) }
    }

    // MARK: Menus (for AppKit apps; SwiftUI apps can bind to `state`)

    /// A View-menu section: Show/Hide for each closable side, Show in
    /// Window for each pane that can pop out, and Restore Default Layout.
    public func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for split in root.splits where split.collapsible {
            let id = split.id
            items.append(PaneMenuItem.make(title: { [weak self] in
                (self?.isOpen(id) ?? true) ? "Hide \(split.sizedTitle)" : "Show \(split.sizedTitle)"
            }, state: nil) { [weak self] in self?.toggle(id) })
        }
        let poppable = root.panes.filter { $0.popOut != .none }
        if !poppable.isEmpty { items.append(.separator()) }
        for pane in poppable {
            let id = pane.id
            items.append(PaneMenuItem.make(title: { "\(pane.title) in Its Own Window" },
                                           state: { [weak self] in self?.isPoppedOut(id) ?? false }) { [weak self] in
                self?.togglePopOut(id)
            })
        }
        items.append(.separator())
        items.append(PaneMenuItem.make(title: { "Restore Default Layout" }, state: nil) { [weak self] in
            self?.restoreDefaults()
        })
        return items
    }
}

/// A menu item whose title, checkmark and action are closures, refreshed
/// each time its menu opens.
@MainActor
final class PaneMenuItem: NSObject, NSMenuItemValidation {
    let title: () -> String
    let checked: (() -> Bool)?
    let action: () -> Void
    /// Items hold their targets weakly, so the targets are kept here.
    private static var alive: [PaneMenuItem] = []

    private init(title: @escaping () -> String, checked: (() -> Bool)?, action: @escaping () -> Void) {
        self.title = title
        self.checked = checked
        self.action = action
    }

    static func make(title: @escaping () -> String, state: (() -> Bool)?,
                     action: @escaping () -> Void) -> NSMenuItem {
        let target = PaneMenuItem(title: title, checked: state, action: action)
        alive.append(target)
        let item = NSMenuItem(title: title(), action: #selector(run(_:)), keyEquivalent: "")
        item.target = target
        return item
    }

    @objc func run(_ sender: NSMenuItem) { action() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = title()
        if let checked { item.state = checked() ? .on : .off }
        return true
    }
}
