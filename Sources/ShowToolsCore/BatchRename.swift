import Foundation

/// Finder's *Rename Items* sheet: the same three modes, computed as pure
/// name transforms so the caller can preview them before anything on disk
/// changes. `Library.renameItems` does the actual move; nothing here
/// touches the filesystem or the database.
public enum BatchRename {
    public enum Mode: Sendable, Equatable {
        /// Every occurrence of `find` in the name (not the extension)
        /// becomes `with`. An empty `find` changes nothing.
        case replaceText(find: String, with: String)
        /// `text` goes at the very start or the very end of the name.
        case addText(String, Position)
        /// A name, followed by a running index, counter or date, each
        /// starting at `start`.
        case format(name: String, counter: Counter, start: Int)

        public enum Position: Sendable { case before, after }
        public enum Counter: Sendable {
            /// 1, 2, 3…
            case index
            /// Zero-padded to whatever width the batch needs: 01, 02… 10.
            case counter
            /// Today's date, then a running number to keep several unique.
            case date
        }
    }

    /// One new name per name given, in the same order, each keeping its
    /// own extension. `names` are current filenames (with extension).
    public static func apply(_ mode: Mode, to names: [String]) -> [String] {
        names.enumerated().map { i, name in
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let newStem = apply(mode, stem: stem, index: i, count: names.count)
            return ext.isEmpty ? newStem : "\(newStem).\(ext)"
        }
    }

    private static func apply(_ mode: Mode, stem: String, index i: Int, count: Int) -> String {
        switch mode {
        case .replaceText(let find, let with):
            return find.isEmpty ? stem : stem.replacingOccurrences(of: find, with: with)
        case .addText(let text, let position):
            return position == .before ? text + stem : stem + text
        case .format(let name, let counter, let start):
            let n = start + i
            switch counter {
            case .index:
                return "\(name) \(n)"
            case .counter:
                let width = String(start + count - 1).count
                return "\(name) \(String(format: "%0\(width)d", n))"
            case .date:
                return "\(name) \(dateStamp()) \(n)"
            }
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
