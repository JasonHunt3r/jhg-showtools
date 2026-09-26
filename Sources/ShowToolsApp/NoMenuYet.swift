import AppKit
import SwiftUI

/// A place that should answer a right-click but has no menu designed yet
/// (Jason, 2026-09-26): instead of nothing, a one-line greyed menu naming
/// the place and where it sits, in `spec/anatomy.md`'s names — so the gaps
/// are visible, and findable when it's time to fill them in (search the
/// code for `noMenuYet`). A menu agreed but not yet built says so in
/// `planned`, from `spec/conventions.md` §3. When a real menu is designed,
/// it replaces the note.
struct NoMenuYet: ViewModifier {
    let place: String
    var planned: String?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .contextMenu { NoMenuYetItems(place: place, planned: planned) }
    }
}

/// The note's lines, for a menu built elsewhere (a `List`'s
/// `contextMenu(forSelectionType:)` on its empty space).
struct NoMenuYetItems: View {
    let place: String
    var planned: String?

    var body: some View {
        Button("No menu yet — \(place)") {}.disabled(true)
        if let planned { Button("Agreed, not built: \(planned)") {}.disabled(true) }
    }
}

extension View {
    func noMenuYet(_ place: String, planned: String? = nil) -> some View {
        modifier(NoMenuYet(place: place, planned: planned))
    }
}

/// A list's empty space (below its last row), for every `List` in the app.
/// SwiftUI's own list throws on a right-click there on macOS 27 —
/// "Row index -1 out of row range", from `OutlineListCoordinator`'s
/// `contextMenuForRow`, whatever menu the list declares, per-row or
/// `contextMenu(forSelectionType:)` — and shows nothing (measured
/// 2026-09-26, both the Library pane and the browser). So the click is
/// taken here first, app-wide, and the note shown directly. Nothing is
/// attached to the lists themselves (a background on a List hit the
/// layout-loop guard once, `showtools-gotchas`); a list is named by the
/// PaneKit pane it sits in (its host view's `identifier` is the pane id).
@MainActor
enum ListEmptySpace {
    private static var monitor: Any?

    /// Pane id → the place's name, and a menu agreed but not built
    /// (`spec/conventions.md` §3). Nearest pane wins.
    private static let places: [String: (place: String, planned: String?)] = [
        "library": ("Library pane", nil),
        "list": ("Edit Show › Browser", "Import…, Add from Library…"),
        "main": ("Edit Slides › Slide list", "Add from Collection…, Import…, Paste, Select All"),
    ]

    static func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// True if this was a right-click (or Control-click) on a list's empty
    /// space, now answered.
    private static func handle(_ event: NSEvent) -> Bool {
        guard event.type == .rightMouseDown
                || event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
              let content = event.window?.contentView,
              let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)) else { return false }
        var view: NSView? = hit
        while let v = view, !(v is NSTableView) { view = v.superview }
        guard let table = view as? NSTableView,
              table.row(at: table.convert(event.locationInWindow, from: nil)) == -1 else { return false }
        let named = pane(of: table).flatMap { places[$0] }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func line(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        line("No menu yet — \(named?.place ?? "a list") › empty space")
        if let planned = named?.planned { line("Agreed, not built: \(planned)") }
        NSMenu.popUpContextMenu(menu, with: event, for: table)
        return true
    }

    /// The id of the nearest PaneKit pane holding `view`.
    private static func pane(of view: NSView) -> String? {
        var v: NSView? = view.superview
        while let cur = v {
            if let id = cur.identifier?.rawValue, places[id] != nil { return id }
            v = cur.superview
        }
        return nil
    }
}
