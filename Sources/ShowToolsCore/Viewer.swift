import CoreGraphics

/// The viewer drawer's pure parts (`spec/plan.md`, "The viewer drawer"):
/// which selected files it shows, which one is outlined after ← / →, and
/// where each one goes side by side. The views (`SelectionViewer`) only
/// draw what these work out.
public enum Viewer {
    /// Side by side shows at most this many at once, with a "+N more" note
    /// past it: ⌘A on thousands of files shouldn't try to draw them all
    /// (settled with Jason, 2026-09-26).
    public static let sideBySideCap = 12

    /// The files shown side by side: the selection in its own order, at
    /// most `cap` of them, and always including `primary` — when it would
    /// fall past the cap, it takes the last place shown. With how many
    /// more there are.
    public static func shown<ID: Hashable>(_ ordered: [ID], primary: ID?,
                                          cap: Int = sideBySideCap) -> (ids: [ID], more: Int) {
        guard ordered.count > cap, cap > 0 else { return (ordered, 0) }
        var ids = Array(ordered.prefix(cap))
        if let primary, !ids.contains(primary), ordered.contains(primary) { ids[cap - 1] = primary }
        return (ids, ordered.count - cap)
    }

    /// ← / → while the viewer is open with several selected: the outlined
    /// file moves to the next (`delta` 1) or previous (−1) selected one,
    /// wrapping, and the selection stays as it is (Jason, 2026-09-26,
    /// Aperture's multi-up). With none outlined, → starts at the first and
    /// ← at the last.
    public static func step<ID: Hashable>(_ ordered: [ID], from primary: ID?, by delta: Int) -> ID? {
        guard !ordered.isEmpty else { return nil }
        guard let primary, let i = ordered.firstIndex(of: primary) else {
            return delta < 0 ? ordered.last : ordered.first
        }
        let n = ordered.count
        return ordered[((i + delta) % n + n) % n]
    }

    /// Side by side: the pictures in rows, reading order, with the column
    /// count that makes them as large as they can be (the most picture
    /// area, each one fitted whole into its cell). A short last row is
    /// centred. `aspects` are width ÷ height; 0 or less counts as square.
    /// Frames are in the box's own coordinates, y growing downward.
    public static func sideBySide(aspects: [CGFloat], in size: CGSize, spacing: CGFloat = 8) -> [CGRect] {
        let n = aspects.count
        guard n > 0, size.width > 0, size.height > 0 else { return [] }
        let ratios = aspects.map { $0 > 0 ? $0 : 1 }
        var best: (columns: Int, area: CGFloat) = (1, -1)
        for columns in 1...n {
            let rows = (n + columns - 1) / columns
            let cell = cellSize(columns: columns, rows: rows, in: size, spacing: spacing)
            guard cell.width > 0, cell.height > 0 else { continue }
            let area = ratios.reduce(CGFloat(0)) { sum, r in
                let fit = fitted(r, in: cell)
                return sum + fit.width * fit.height
            }
            if area > best.area { best = (columns, area) }
        }
        let columns = best.columns, rows = (n + columns - 1) / columns
        let cell = cellSize(columns: columns, rows: rows, in: size, spacing: spacing)
        return ratios.enumerated().map { i, r in
            let row = i / columns, column = i % columns
            let inRow = min(columns, n - row * columns)
            // A short last row is centred along the width.
            let rowWidth = CGFloat(inRow) * cell.width + CGFloat(inRow - 1) * spacing
            let left = (size.width - rowWidth) / 2
            let x = left + CGFloat(column) * (cell.width + spacing)
            let y = CGFloat(row) * (cell.height + spacing)
            let fit = fitted(r, in: cell)
            return CGRect(x: x + (cell.width - fit.width) / 2, y: y + (cell.height - fit.height) / 2,
                          width: fit.width, height: fit.height)
        }
    }

    static func cellSize(columns: Int, rows: Int, in size: CGSize, spacing: CGFloat) -> CGSize {
        CGSize(width: (size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns),
               height: (size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows))
    }

    /// A picture of aspect `ratio`, as large as fits whole in `cell`.
    static func fitted(_ ratio: CGFloat, in cell: CGSize) -> CGSize {
        cell.width / cell.height > ratio
            ? CGSize(width: cell.height * ratio, height: cell.height)
            : CGSize(width: cell.width, height: cell.width / ratio)
    }
}
