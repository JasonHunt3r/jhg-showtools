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

