import Foundation

/// Finder-style click, ⌘-click and ⇧-click, and arrow-key stepping, as pure
/// functions over the caller's own state (`spec/conventions.md` §1–2,
/// settled 2026-09-24). Each caller (the Library grid, the storyline) keeps
/// its own `selected`/`anchor`/`base`/`cursor`, all bundled here as one
/// `Result`, and writes it straight back after a click or a key.
///
/// - A plain click or ⌘-click sets a new anchor and a new base (the
///   selection right then, for the next ⇧-click to union with).
/// - A ⇧-click selects the range from the anchor to here, replacing the
///   previous ⇧-range — not adding to it (B3, E1): click 5, ⇧-click 10,
///   ⇧-click 7 leaves 5–7 selected, not 5–10.
/// - An arrow key moves the cursor by `delta` positions in the visible
///   order (±1 for ← →, ± a column count for ↑ ↓ in a grid — the caller
///   works out `delta`, this only steps it) and, extending (⇧), unions the
///   range from the anchor exactly as a ⇧-click at that position would.
public enum GridSelection {
    /// What changed: the caller writes all four fields back to its own state.
    public struct Result<ID: Hashable>: Equatable {
        public var selected: Set<ID>
        public var anchor: ID?
        public var base: Set<ID>
        public var cursor: ID?

        public init(selected: Set<ID>, anchor: ID?, base: Set<ID>, cursor: ID?) {
            self.selected = selected
            self.anchor = anchor
            self.base = base
            self.cursor = cursor
        }
    }

    /// Plain click: select only this, and anchor here.
    public static func click<ID: Hashable>(_ id: ID) -> Result<ID> {
        Result(selected: [id], anchor: id, base: [id], cursor: id)
    }

    /// ⌘-click: toggles membership. The anchor moves here too, so a
    /// following ⇧-click ranges from it, not from wherever it last was.
    public static func commandClick<ID: Hashable>(_ id: ID, selected: Set<ID>) -> Result<ID> {
        var s = selected
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        return Result(selected: s, anchor: id, base: s, cursor: id)
    }

    /// ⇧-click: the range from `anchor` to `id` in `items`' on-screen
    /// order, unioned with `base` (the selection from when the anchor was
    /// last set by a plain or ⌘-click) — so a run of ⇧-clicks each replace
    /// the range the last one added, rather than piling up. With no anchor
    /// yet (nothing plainly clicked before), or either id missing from
    /// `items`, behaves like a plain click.
    public static func shiftClick<ID: Hashable>(_ id: ID, anchor: ID?, base: Set<ID>, in items: [ID]) -> Result<ID> {
        guard let anchor, let a = items.firstIndex(of: anchor), let b = items.firstIndex(of: id) else {
            return click(id)
        }
        let range = Set(items[min(a, b)...max(a, b)])
        return Result(selected: base.union(range), anchor: anchor, base: base, cursor: id)
    }

    /// An arrow key: moves `delta` positions from `cursor` in `items`
    /// (clamped to the ends; from nowhere, the first item for a forward
    /// step or the last for a backward one). Not extending, this is a
    /// plain click on the new position. Extending (⇧), the anchor and base
    /// stay put and the range unions to the new position, exactly as
    /// `shiftClick` there would — so a run of ⇧-arrows grows or shrinks
    /// the same range a run of ⇧-clicks would.
    public static func step<ID: Hashable>(from cursor: ID?, by delta: Int, anchor: ID?, base: Set<ID>,
                                           in items: [ID], extend: Bool) -> Result<ID> {
        guard !items.isEmpty else { return Result(selected: [], anchor: nil, base: [], cursor: nil) }
        let from = cursor.flatMap { items.firstIndex(of: $0) }
        let to: Int
        if let from {
            to = min(max(from + delta, 0), items.count - 1)
        } else {
            to = delta >= 0 ? 0 : items.count - 1
        }
        let id = items[to]
        if extend, let anchor {
            return shiftClick(id, anchor: anchor, base: base, in: items)
        }
        return click(id)
    }
}
