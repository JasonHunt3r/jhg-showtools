import Foundation

/// Drag-to-reorder in the Library grid (`spec/plan.md`, "Reordering"), as
/// pure functions: which slot the cursor is over, the order shown while
/// dragging, and the collection's whole order once it's dropped.
///
/// The slot comes from the cursor's position and the grid's geometry alone,
/// never from which tile happens to be drawn under the cursor. The tiles
/// move while dragging (the gap follows the cursor), so asking the tiles
/// was a feedback loop: a tile slid out from under the cursor, the preview
/// cancelled, the tile slid back, and so on for as long as the drag was
/// held (measured 2026-09-25, 45 frames of one slow drag).
public enum Reorder {
    /// The slot under a point, in a grid of `columns` equal cells laid out
    /// left to right, top to bottom, `pitch` apart (a cell plus its
    /// spacing). The point is relative to the first cell's top-left corner.
    /// Clamped so a block of `blockSize` dragged items starting there still
    /// fits among `count` slots: past the last row, or right of the last
    /// column, means the end.
    public static func slot(x: Double, y: Double, columns: Int, pitchX: Double, pitchY: Double,
                            count: Int, blockSize: Int = 1) -> Int {
        let last = max(0, count - max(1, blockSize))
        guard columns > 0, pitchX > 0, pitchY > 0 else { return last }
        let col = min(max(0, Int((x / pitchX).rounded(.down))), columns - 1)
        let row = max(0, Int((y / pitchY).rounded(.down)))
        return min(max(0, row * columns + col), last)
    }

    /// `order` with `moving` (kept in their own relative order) taken out
    /// and put back as one block starting at `index` of what's left: the
    /// order shown while dragging, the moved files standing in for the gap.
    public static func moving<ID: Hashable>(_ moving: Set<ID>, in order: [ID], to index: Int) -> [ID] {
        let block = order.filter { moving.contains($0) }
        var rest = order.filter { !moving.contains($0) }
        rest.insert(contentsOf: block, at: min(max(0, index), rest.count))
        return rest
    }

    /// The whole membership's new order, from the new order of just the
    /// part on screen. Settled with Jason 2026-09-25: what's on screen is
    /// what's saved, even from another sort (sorted by Name, a drop makes
    /// Custom Order the Name order with that one move), and files a search
    /// or filter is hiding keep their places. So the shown files fill the
    /// positions the shown files held in `all`, in their new order, and
    /// every hidden file stays exactly where it was.
    public static func merge<ID: Hashable>(_ shown: [ID], into all: [ID]) -> [ID] {
        let shownSet = Set(shown)
        var next = shown.makeIterator()
        return all.map { shownSet.contains($0) ? (next.next() ?? $0) : $0 }
    }
}
