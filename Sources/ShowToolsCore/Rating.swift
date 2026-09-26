import Foundation

/// A file's rating, Aperture's way (item 20 of the 2026-09-25 feedback
/// worklist): 1–5 stars, 0 unrated, and **rejected**, stored as −1 in the
/// same `rating` column (Aperture did the same), so no schema change.
public enum Rating {
    public static let rejected = -1
    public static let range = rejected...5

    public static func clamped(_ rating: Int) -> Int { min(max(rating, range.lowerBound), range.upperBound) }

    /// − and =: one star down or up. − stops at unrated, since rejecting
    /// is its own key (9), and leaves a reject alone; = lifts a reject to
    /// unrated.
    public static func stepped(_ rating: Int, by delta: Int) -> Int {
        if rating == rejected { return delta > 0 ? 0 : rejected }
        return min(max(rating + delta, 0), 5)
    }

    /// The bare keys: 1–5 set stars, 0 clears, 9 rejects, − and = step.
    public enum Key: Equatable {
        case set(Int)
        case step(Int)

        public init?(_ character: String) {
            switch character {
            case "0", "1", "2", "3", "4", "5": self = .set(Int(character)!)
            case "9": self = .set(Rating.rejected)
            case "-": self = .step(-1)
            case "=": self = .step(1)
            default: return nil
            }
        }

        public func applied(to rating: Int) -> Int {
            switch self {
            case .set(let r): r
            case .step(let d): Rating.stepped(rating, by: d)
            }
        }
    }

    /// The grids' and the browser's rating filter, a saved Int: 1–5 are
    /// "that many stars or more"; 0 (the default, and what every older
    /// saved filter already says) is unrated or better, so rejects stay
    /// hidden unless asked for; −1 shows everything; −2, rejects only.
    public enum Filter {
        public static let showAll = -1
        public static let unratedOrBetter = 0
        public static let rejectedOnly = -2

        public static func matches(_ rating: Int, filter: Int) -> Bool {
            filter == rejectedOnly ? rating == Rating.rejected : rating >= filter
        }

        /// Filtered away from the default, so the filter button lights up.
        public static func isActive(_ filter: Int) -> Bool { filter != unratedOrBetter }
    }
}
