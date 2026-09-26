import Foundation

/// Where the library lives, and the Spotlight rule.
///
/// Spotlight skips any folder whose name ends in `.noindex` (verified with
/// `mdfind` on this Mac, 2026-09-20: a probe file inside was not found, its
/// twin in a plain folder was). So hiding the library is a rename, and the
/// Preferences toggle just renames the folder back and forth.
public enum LibraryLocation {
    public static let baseName = "ShowTools Library"

    public static var parent: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    }
    public static var hiddenURL: URL { parent.appendingPathComponent(baseName + ".noindex") }
    public static var visibleURL: URL { parent.appendingPathComponent(baseName) }

    /// The existing library under either name, or the hidden default if
    /// there is none yet.
    public static func resolve() -> URL {
        // Testing hook: point the app at a scratch library.
        if let override = ProcessInfo.processInfo.environment["SHOWTOOLS_LIBRARY"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: hiddenURL.path) { return hiddenURL }
        if fm.fileExists(atPath: visibleURL.path) { return visibleURL }
        return hiddenURL
    }

    public static func isHidden(_ url: URL) -> Bool { url.pathExtension == "noindex" }

    /// Why this launch mustn't open a library, or nil if it may. Any
    /// `SHOWTOOLS_` setting marks a test launch (a dev hook, or a mistyped
    /// `SHOWTOOLS_LIBRARY`), and a test launch must name its scratch
    /// library: without one, `resolve()` falls back to the real library.
    public static func testLaunchProblem(
        _ env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let ours = env.keys.filter { $0.hasPrefix("SHOWTOOLS_") }.sorted()
        guard !ours.isEmpty, (env["SHOWTOOLS_LIBRARY"] ?? "").isEmpty else { return nil }
        return "This launch sets \(ours.joined(separator: ", ")) but no SHOWTOOLS_LIBRARY, "
            + "so it would open the real library. Nothing was opened. "
            + "Set SHOWTOOLS_LIBRARY to a scratch library."
    }

    /// True when `url`, or the folder it would be created in, syncs to iCloud.
    public static func isInICloud(_ url: URL) -> Bool {
        let fm = FileManager.default
        var probe = url
        while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        if fm.isUbiquitousItem(at: probe) { return true }
        return probe.path.contains("/Library/Mobile Documents/")
    }
}

/// Test launches (those with `SHOWTOOLS_LIBRARY`) leave a note in the app's
/// defaults while they run, removed when they quit. A note left by a copy
/// that's no longer running means it crashed, and a plain launch soon after
/// is most likely the crash reporter's Reopen (or macOS relaunching it),
/// which carries none of the test's environment and would open the real
/// library. That launch opens nothing, once: the notes are cleared, so the
/// next deliberate launch opens normally. (2026-09-21: a crash relaunch
/// created an empty real library.)
public struct TestLaunchRecord {
    public static let key = "runningTestLaunches"
    let defaults: UserDefaults
    let isAlive: (Int32) -> Bool

    public init(defaults: UserDefaults = .standard,
                isAlive: @escaping (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        self.defaults = defaults
        self.isAlive = isAlive
    }

    private var notes: [String: String] {
        get { defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    /// A test launch starting: note it.
    public func begin(pid: Int32, library: String) { notes[String(pid)] = library }

    /// A test launch quitting properly: remove its note.
    public func end(pid: Int32) { notes[String(pid)] = nil }

    /// For a plain launch: why it mustn't open a library, or nil. Clears the
    /// notes of every copy no longer running, so it only refuses once.
    public func crashRelaunchProblem() -> String? {
        let dead = notes.filter { pid, _ in Int32(pid).map { !isAlive($0) } ?? true }
        guard !dead.isEmpty else { return nil }
        notes = notes.filter { dead[$0.key] == nil }
        return "The last test copy of ShowTools (on \(dead.values.sorted().joined(separator: ", "))) "
            + "didn't quit normally, so this launch is probably its crash relaunch. It has no "
            + "SHOWTOOLS_LIBRARY and would have opened the real library, so nothing was opened. "
            + "Quit and open ShowTools again to use the real library."
    }
}

public enum LibraryReadError: Error, Equatable, CustomStringConvertible {
    case missing(URL)
    case version(found: Int, known: Int)

    public var description: String {
        switch self {
        case .missing(let url): return "No library at \(url.path)"
        case .version(let found, let known) where found < known:
            return "This library is from an older ShowTools. Open it in ShowTools once to bring it up to date."
        case .version:
            return "This library is from a newer ShowTools. Update BGTools."
        }
    }
}

/// The library database plus the folder of media it manages.
///
/// Not thread-safe: the app uses it from the main actor. Heavy file work
/// (hashing, copying, probing) happens elsewhere; only the row writes land here.
public final class Library {
    public let root: URL
    private let db: Database

    public var mediaURL: URL { root.appendingPathComponent("Media", isDirectory: true) }
    public var isHidden: Bool { LibraryLocation.isHidden(root) }

    public init(root: URL) throws {
        if LibraryLocation.isInICloud(root) {
            throw DatabaseError(description:
                "The library can't live in an iCloud-synced folder: \(root.path)")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Media"),
                               withIntermediateDirectories: true)
        self.root = root
        db = try Database(path: root.appendingPathComponent("Library.sqlite").path)
        try backUpBeforeUpgrade()
        try migrate()
    }

    /// Opens a library only to read it (BGTools): never creates, backs up,
    /// migrates or writes anything, and refuses a schema other than this
    /// build's, since the columns it reads must be the ones it knows.
    /// ShowTools brings an older library up to date when it opens it.
    public init(readingOnly root: URL) throws {
        let file = root.appendingPathComponent("Library.sqlite")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw LibraryReadError.missing(root)
        }
        self.root = root
        db = try Database(path: file.path, readOnly: true)
        let v = db.userVersion
        if v != Self.schemaVersion { throw LibraryReadError.version(found: v, known: Self.schemaVersion) }
    }

    /// Changes each time any process saves to the library.
    public var changeCount: Int { db.dataVersion }

    /// Reads inside one snapshot, so a show and its slides always match.
    public func snapshot<T>(_ body: () throws -> T) throws -> T { try db.snapshot(body) }

    /// The schema version `migrate` brings a library up to.
    public static let schemaVersion = 14

    /// Before an existing library is upgraded, a copy of its database as it
    /// was, beside it: `Library.sqlite.v<N>.bak`. Upgrades are additive and
    /// tested, but once real photos are in a library a bad one mustn't be
    /// permanent. `VACUUM INTO` makes a consistent copy with the WAL
    /// included. A backup of that version already there is kept, and if the
    /// copy can't be made the library doesn't open, rather than upgrade
    /// without one.
    private func backUpBeforeUpgrade() throws {
        let v = db.userVersion
        guard v > 0, v < Self.schemaVersion else { return }
        let backup = root.appendingPathComponent("Library.sqlite.v\(v).bak")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try db.exec("VACUUM INTO '\(backup.path.replacingOccurrences(of: "'", with: "''"))'")
    }

    private func migrate() throws {
        if db.userVersion < 1 {
            try db.transaction {
                try db.exec("""
                    CREATE TABLE items (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        rel_path TEXT NOT NULL UNIQUE,
                        hash TEXT NOT NULL UNIQUE,
                        kind TEXT NOT NULL,
                        width INTEGER NOT NULL,
                        height INTEGER NOT NULL,
                        duration REAL,
                        ingested_at REAL NOT NULL,
                        source_path TEXT NOT NULL
                    );
                    CREATE TABLE shows (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        defaults TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE slides (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        show_id INTEGER NOT NULL REFERENCES shows(id) ON DELETE CASCADE,
                        position INTEGER NOT NULL,
                        item_id INTEGER NOT NULL REFERENCES items(id),
                        settings TEXT NOT NULL
                    );
                    CREATE INDEX slides_by_show ON slides(show_id, position);
                    PRAGMA user_version = 1;
                    """)
            }
        }
        // 2 (2026-09-21): star ratings on files. Additive: every existing
        // file starts unrated, and nothing else changes.
        if db.userVersion < 2 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE items ADD COLUMN rating INTEGER NOT NULL DEFAULT 0;
                    PRAGMA user_version = 2;
                    """)
            }
        }
        // 3 (2026-09-21): the lane's images row, a JSON list on each show.
        // Additive: every existing show starts with none.
        if db.userVersion < 3 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE shows ADD COLUMN overlays TEXT NOT NULL DEFAULT '[]';
                    PRAGMA user_version = 3;
                    """)
            }
        }
        // 4 (2026-09-21): collections. Library → Collection → Show. A
        // starting collection gets everything already in the library, and
        // every existing show goes into it, so nothing seems to vanish.
        // Deleting a collection takes its shows with it (as deleting an
        // Event does in Final Cut); the app asks first.
        if db.userVersion < 4 {
            try db.transaction {
                try db.exec("""
                    CREATE TABLE collections (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE collection_items (
                        collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                        added_at REAL NOT NULL,
                        PRIMARY KEY (collection_id, item_id)
                    );
                    ALTER TABLE shows ADD COLUMN collection_id INTEGER
                        REFERENCES collections(id) ON DELETE CASCADE;
                    """)
                try db.prepare("INSERT INTO collections (name, created_at) VALUES (?, ?)")
                    .bind(.text(Self.startingCollectionName), .double(Date().timeIntervalSince1970)).run()
                let cid = db.lastInsertID
                try db.prepare("""
                    INSERT INTO collection_items (collection_id, item_id, added_at)
                    SELECT ?, id, ingested_at FROM items
                    """).bind(.int(cid)).run()
                try db.prepare("UPDATE shows SET collection_id = ?").bind(.int(cid)).run()
                try db.exec("PRAGMA user_version = 4")
            }
        }
        // 5 (2026-09-21): the library's own settings, starting with whether
        // it's private. Kept in the library so it holds wherever it's opened.
        if db.userVersion < 5 {
            try db.transaction {
                try db.exec("""
                    CREATE TABLE library_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    PRAGMA user_version = 5;
                    """)
            }
        }
        // 6 (2026-09-21): tags on files, for the Info panel. Additive: every
        // existing file starts with none.
        if db.userVersion < 6 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE items ADD COLUMN tags TEXT NOT NULL DEFAULT '[]';
                    PRAGMA user_version = 6;
                    """)
            }
        }
        // 7 (2026-09-21): each show's timeline rows, in its own order (plan,
        // Phase 3). Additive: an empty list reads as the default order.
        if db.userVersion < 7 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE shows ADD COLUMN rows TEXT NOT NULL DEFAULT '[]';
                    PRAGMA user_version = 7;
                    """)
            }
        }
        // 8 (2026-09-21): each show's songs, for the music row (plan, Phase 3).
        // Additive: every show starts with none. Songs themselves are
        // ordinary library items, of kind "audio".
        if db.userVersion < 8 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE shows ADD COLUMN music TEXT NOT NULL DEFAULT '[]';
                    PRAGMA user_version = 8;
                    """)
            }
        }
        // 9 (2026-09-21): each show's markers, dropped by hand (plan, Phase 3).
        // Additive: every show starts with none.
        if db.userVersion < 9 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE shows ADD COLUMN markers TEXT NOT NULL DEFAULT '[]';
                    PRAGMA user_version = 9;
                    """)
            }
        }
        // 10 (2026-09-21): each show's editing state (range, loop, lines), so
        // it opens as it was left. Additive: '{}' reads as the defaults.
        if db.userVersion < 10 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE shows ADD COLUMN editor TEXT NOT NULL DEFAULT '{}';
                    PRAGMA user_version = 10;
                    """)
            }
        }
        // 11 (2026-09-22): named rhythm patterns (plan, Phase 3 step 7), kept
        // in the library like its collections. Additive: none to start with.
        if db.userVersion < 11 {
            try db.transaction {
                try db.exec("""
                    CREATE TABLE rhythm_patterns (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL UNIQUE,
                        pattern TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    PRAGMA user_version = 11;
                    """)
            }
        }
        // 12 (2026-09-22): a saved pattern keeps its "a quarter note = N
        // beats" too (Jason). Additive: NULL leaves the setting as it is.
        if db.userVersion < 12 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE rhythm_patterns ADD COLUMN beats_per_quarter REAL;
                    PRAGMA user_version = 12;
                    """)
            }
        }
        // 13 (2026-09-24): groups inside collections — sub-folders of a
        // collection's files (plan, "Groups inside collections"). Additive:
        // no existing library has any, so every collection opens with none.
        if db.userVersion < 13 {
            try db.transaction {
                try db.exec("""
                    CREATE TABLE groups (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                        parent_id INTEGER REFERENCES groups(id) ON DELETE CASCADE,
                        name TEXT NOT NULL,
                        created_at REAL NOT NULL
                    );
                    CREATE TABLE group_items (
                        group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
                        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                        added_at REAL NOT NULL,
                        PRIMARY KEY (group_id, item_id)
                    );
                    PRAGMA user_version = 13;
                    """)
            }
        }
        // 14 (2026-09-25): a drag order for a collection's or group's files
        // (plan, "Reordering"), separate from `added_at`. Additive: every
        // existing membership starts ordered exactly as it reads today,
        // since `sort_key` is backfilled from `added_at` — the same order
        // `allCollections`/`allGroups` already sorted by.
        if db.userVersion < 14 {
            try db.transaction {
                try db.exec("""
                    ALTER TABLE collection_items ADD COLUMN sort_key REAL;
                    UPDATE collection_items SET sort_key = added_at;
                    ALTER TABLE group_items ADD COLUMN sort_key REAL;
                    UPDATE group_items SET sort_key = added_at;
                    PRAGMA user_version = 14;
                    """)
            }
        }
    }

    // MARK: The library itself

    /// Its name: the folder's, without ".noindex".
    public var name: String {
        (isHidden ? root.deletingPathExtension() : root).lastPathComponent
    }

    /// A private library asks for Touch ID or the Mac's password before it
    /// opens, and isn't listed in Open Recent (the app does both). It guards
    /// the door in ShowTools only; the files are still ordinary files.
    public var isPrivate: Bool {
        (try? db.prepare("SELECT value FROM library_settings WHERE key = 'private'").firstText()) == "1"
    }

    public func setPrivate(_ on: Bool) throws {
        try db.prepare("""
            INSERT INTO library_settings (key, value) VALUES ('private', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """).bind(.text(on ? "1" : "0")).run()
    }

    /// A random id for this library, made the first time it's asked for.
    /// An export records it, so exporting the same show again can recognise
    /// its earlier folder (plan, Phase 4).
    public func identifier() throws -> String {
        if let id = try db.prepare("SELECT value FROM library_settings WHERE key = 'id'").firstText() {
            return id
        }
        let id = UUID().uuidString
        try db.prepare("INSERT INTO library_settings (key, value) VALUES ('id', ?)").bind(.text(id)).run()
        return id
    }

    public static let startingCollectionName = "Untitled Collection"

    // MARK: Rhythm patterns (schema 11)

    /// The named patterns, by name.
    public func allRhythmPatterns() throws -> [SavedRhythm] {
        let s = try db.prepare("""
            SELECT id, name, pattern, beats_per_quarter FROM rhythm_patterns ORDER BY name COLLATE NOCASE, id
            """)
        var out: [SavedRhythm] = []
        while try s.step() {
            out.append(SavedRhythm(id: s.int(0), name: s.text(1), pattern: RhythmPattern(text: s.text(2)),
                                   beatsPerQuarter: s.isNull(3) ? nil : s.double(3)))
        }
        return out
    }

    /// Saves a pattern under a name, with its note length ("a quarter note
    /// = N beats"). A name already used is replaced, as saving a preset
    /// over one does.
    @discardableResult
    public func saveRhythmPattern(name: String, _ pattern: RhythmPattern, beatsPerQuarter: Double? = nil) throws -> SavedRhythm {
        try db.prepare("""
            INSERT INTO rhythm_patterns (name, pattern, beats_per_quarter, created_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET pattern = excluded.pattern, beats_per_quarter = excluded.beats_per_quarter
            """).bind(.text(name), .text(pattern.text), beatsPerQuarter.map { .double($0) } ?? .null,
                      .double(Date().timeIntervalSince1970)).run()
        let id = try db.prepare("SELECT id FROM rhythm_patterns WHERE name = ?").bind(.text(name))
        _ = try id.step()
        return SavedRhythm(id: id.int(0), name: name, pattern: pattern, beatsPerQuarter: beatsPerQuarter)
    }

    public func deleteRhythmPattern(id: Int64) throws {
        try db.prepare("DELETE FROM rhythm_patterns WHERE id = ?").bind(.int(id)).run()
    }

    // MARK: Collections

    public func allCollections() throws -> [MediaCollection] {
        let s = try db.prepare("SELECT id, name FROM collections ORDER BY created_at, id")
        var out: [MediaCollection] = []
        while try s.step() { out.append(MediaCollection(id: s.int(0), name: s.text(1))) }
        let m = try db.prepare("SELECT collection_id, item_id, added_at FROM collection_items ORDER BY sort_key, item_id")
        var members: [Int64: [Int64]] = [:]
        var added: [Int64: [Int64: Double]] = [:]
        while try m.step() { members[m.int(0), default: []].append(m.int(1)); added[m.int(0), default: [:]][m.int(1)] = m.double(2) }
        for i in out.indices {
            out[i].itemIDs = members[out[i].id] ?? []
            out[i].addedAt = added[out[i].id] ?? [:]
        }
        return out
    }

    public func createCollection(name: String) throws -> MediaCollection {
        try db.prepare("INSERT INTO collections (name, created_at) VALUES (?, ?)")
            .bind(.text(name), .double(Date().timeIntervalSince1970)).run()
        return MediaCollection(id: db.lastInsertID, name: name)
    }

    public func renameCollection(id: Int64, to name: String) throws {
        try db.prepare("UPDATE collections SET name = ? WHERE id = ?").bind(.text(name), .int(id)).run()
    }

    /// Its shows go with it; the files stay in the library.
    public func deleteCollection(id: Int64) throws {
        try db.prepare("DELETE FROM collections WHERE id = ?").bind(.int(id)).run()
    }

    /// Files already in it are left as they were. New ones join at the end
    /// of the drag order (`sort_key`), all at the same key — as they
    /// already shared one `added_at`, ties break on item id, same as today.
    public func addItems(_ itemIDs: [Int64], toCollection id: Int64) throws {
        let now = Date().timeIntervalSince1970
        try db.transaction {
            let next = try nextSortKey("collection_items", column: "collection_id", id: id)
            let s = try db.prepare("""
                INSERT OR IGNORE INTO collection_items (collection_id, item_id, added_at, sort_key) VALUES (?, ?, ?, ?)
                """)
            for item in itemIDs { try s.bind(.int(id), .int(item), .double(now), .double(next)).run() }
        }
    }

    /// One past the highest `sort_key` already in `table` for `id` (0 if
    /// there's none), so newly added files land after everything already
    /// there.
    private func nextSortKey(_ table: String, column: String, id: Int64) throws -> Double {
        let q = try db.prepare("SELECT COALESCE(MAX(sort_key), -1) FROM \(table) WHERE \(column) = ?").bind(.int(id))
        _ = try q.step()
        return q.double(0) + 1
    }

    /// What `removeItems(_:fromCollection:)` took out: the collection
    /// memberships, for the caller's own bookkeeping, and the group
    /// memberships that came out with them (a file taken out of a
    /// collection also comes out of that collection's groups, in the same
    /// transaction — plan, "Groups inside collections"), so
    /// `restoreItems(_:toCollection:)` can put both back.
    public struct CollectionRemoval: Sendable {
        public let items: [(itemID: Int64, addedAt: Double, sortKey: Double)]
        public let groupMemberships: [(groupID: Int64, itemID: Int64, addedAt: Double, sortKey: Double)]
    }

    /// Takes files out of a collection, and returns when each had been
    /// added and its drag position, so undo can put them back exactly
    /// where they were.
    @discardableResult
    public func removeItems(_ itemIDs: [Int64], fromCollection id: Int64) throws -> CollectionRemoval {
        try db.transaction {
            let q = try db.prepare("SELECT added_at, sort_key FROM collection_items WHERE collection_id = ? AND item_id = ?")
            let s = try db.prepare("DELETE FROM collection_items WHERE collection_id = ? AND item_id = ?")
            var removed: [(itemID: Int64, addedAt: Double, sortKey: Double)] = []
            for item in itemIDs {
                q.bind(.int(id), .int(item))
                if try q.step() { removed.append((item, q.double(0), q.double(1))) }
                try s.bind(.int(id), .int(item)).run()
            }
            let groupMemberships = try groupMembershipsOfItems(itemIDs, inCollection: id)
            for m in groupMemberships {
                try db.prepare("DELETE FROM group_items WHERE group_id = ? AND item_id = ?")
                    .bind(.int(m.groupID), .int(m.itemID)).run()
            }
            return CollectionRemoval(items: removed, groupMemberships: groupMemberships)
        }
    }

    private func groupMembershipsOfItems(_ itemIDs: [Int64], inCollection collectionID: Int64) throws -> [(groupID: Int64, itemID: Int64, addedAt: Double, sortKey: Double)] {
        guard !itemIDs.isEmpty else { return [] }
        let ids = itemIDs.map(String.init).joined(separator: ",")
        let s = try db.prepare("""
            SELECT group_items.group_id, group_items.item_id, group_items.added_at, group_items.sort_key
            FROM group_items JOIN groups ON groups.id = group_items.group_id
            WHERE groups.collection_id = ? AND group_items.item_id IN (\(ids))
            """).bind(.int(collectionID))
        var out: [(groupID: Int64, itemID: Int64, addedAt: Double, sortKey: Double)] = []
        while try s.step() { out.append((s.int(0), s.int(1), s.double(2), s.double(3))) }
        return out
    }

    /// Puts files back in a collection as they were: undoing a removal.
    /// Files no longer in the library are skipped.
    public func restoreItems(_ entries: [(itemID: Int64, addedAt: Double, sortKey: Double)], toCollection id: Int64) throws {
        try db.transaction {
            let s = try db.prepare("""
                INSERT OR IGNORE INTO collection_items (collection_id, item_id, added_at, sort_key)
                SELECT ?, id, ?, ? FROM items WHERE id = ?
                """)
            for e in entries { try s.bind(.int(id), .double(e.addedAt), .double(e.sortKey), .int(e.itemID)).run() }
        }
    }

    /// Puts files back in their groups: undoing the group side of
    /// `removeItems(_:fromCollection:)`. Files or groups no longer there
    /// are skipped.
    public func restoreGroupMemberships(_ entries: [(groupID: Int64, itemID: Int64, addedAt: Double, sortKey: Double)]) throws {
        try db.transaction {
            let g = try db.prepare("""
                INSERT OR IGNORE INTO group_items (group_id, item_id, added_at, sort_key)
                SELECT ?, id, ?, ? FROM items WHERE id = ?
                """)
            for m in entries { try g.bind(.int(m.groupID), .double(m.addedAt), .double(m.sortKey), .int(m.itemID)).run() }
        }
    }

    /// Sets a collection's whole drag order at once, from the front end's
    /// own reordered array — however the drag got there. Renumbered as
    /// plain integers every call: a personal media library's collections
    /// aren't big enough for a full rewrite to cost anything real (plan,
    /// "Reordering"). Ids not in the collection are ignored.
    public func setOrder(_ itemIDs: [Int64], inCollection id: Int64) throws {
        try db.transaction {
            let s = try db.prepare("UPDATE collection_items SET sort_key = ? WHERE collection_id = ? AND item_id = ?")
            for (i, item) in itemIDs.enumerated() { try s.bind(.double(Double(i)), .int(id), .int(item)).run() }
        }
    }

    /// The group version of `setOrder(_:inCollection:)`.
    public func setOrder(_ itemIDs: [Int64], inGroup id: Int64) throws {
        try db.transaction {
            let s = try db.prepare("UPDATE group_items SET sort_key = ? WHERE group_id = ? AND item_id = ?")
            for (i, item) in itemIDs.enumerated() { try s.bind(.double(Double(i)), .int(id), .int(item)).run() }
        }
    }

    /// Everything deleting a collection takes with it, to put back on undo.
    public struct CollectionSnapshot: Sendable {
        public let id: Int64
        public let name: String
        public let createdAt: Double
        public let members: [(itemID: Int64, addedAt: Double, sortKey: Double)]
        public let shows: [(show: Show, createdAt: Double)]
        public let groups: [GroupSnapshot]
    }

    public func snapshotCollection(id: Int64) throws -> CollectionSnapshot? {
        let c = try db.prepare("SELECT name, created_at FROM collections WHERE id = ?").bind(.int(id))
        guard try c.step() else { return nil }
        let name = c.text(0), createdAt = c.double(1)
        let m = try db.prepare("SELECT item_id, added_at, sort_key FROM collection_items WHERE collection_id = ?").bind(.int(id))
        var members: [(itemID: Int64, addedAt: Double, sortKey: Double)] = []
        while try m.step() { members.append((m.int(0), m.double(1), m.double(2))) }
        let times = try db.prepare("SELECT id, created_at FROM shows WHERE collection_id = ?").bind(.int(id))
        var created: [Int64: Double] = [:]
        while try times.step() { created[times.int(0)] = times.double(1) }
        let shows = try allShows().filter { $0.collectionID == id }.map { ($0, created[$0.id] ?? 0) }
        let groups = try snapshotGroups(inCollection: id)
        return CollectionSnapshot(id: id, name: name, createdAt: createdAt, members: members, shows: shows, groups: groups)
    }

    /// Undoes `deleteCollection`: the collection, its files in their order,
    /// its groups (with their own files) and its shows, all with their old
    /// ids, so undo steps recorded against them still find them. Slides of
    /// files deleted since are left out.
    public func restoreCollection(_ snap: CollectionSnapshot) throws {
        try db.transaction {
            try db.prepare("INSERT INTO collections (id, name, created_at) VALUES (?, ?, ?)")
                .bind(.int(snap.id), .text(snap.name), .double(snap.createdAt)).run()
            try restoreItems(snap.members, toCollection: snap.id)
            for g in snap.groups { try restoreGroup(g) }
            let exists = try db.prepare("SELECT 1 FROM items WHERE id = ?")
            for (show, createdAt) in snap.shows {
                try db.prepare("INSERT INTO shows (id, name, defaults, created_at, collection_id) VALUES (?, ?, '{}', ?, ?)")
                    .bind(.int(show.id), .text(show.name), .double(createdAt), .int(snap.id)).run()
                var s = show
                s.slides = try s.slides.filter { slide in
                    exists.bind(.int(slide.itemID))
                    return try exists.step()
                }
                try saveShow(s)
            }
        }
    }

    // MARK: Groups (schema 13)

    public func allGroups() throws -> [MediaGroup] {
        let s = try db.prepare("SELECT id, collection_id, parent_id, name FROM groups ORDER BY created_at, id")
        var out: [MediaGroup] = []
        while try s.step() {
            out.append(MediaGroup(id: s.int(0), collectionID: s.int(1),
                                   parentID: s.isNull(2) ? nil : s.int(2), name: s.text(3)))
        }
        let m = try db.prepare("SELECT group_id, item_id, added_at FROM group_items ORDER BY sort_key, item_id")
        var members: [Int64: [Int64]] = [:]
        var added: [Int64: [Int64: Double]] = [:]
        while try m.step() { members[m.int(0), default: []].append(m.int(1)); added[m.int(0), default: [:]][m.int(1)] = m.double(2) }
        for i in out.indices {
            out[i].itemIDs = members[out[i].id] ?? []
            out[i].addedAt = added[out[i].id] ?? [:]
        }
        return out
    }

    public func createGroup(name: String, collectionID: Int64, parentID: Int64? = nil) throws -> MediaGroup {
        try db.prepare("INSERT INTO groups (collection_id, parent_id, name, created_at) VALUES (?, ?, ?, ?)")
            .bind(.int(collectionID), parentID.map { .int($0) } ?? .null, .text(name),
                  .double(Date().timeIntervalSince1970)).run()
        return MediaGroup(id: db.lastInsertID, collectionID: collectionID, parentID: parentID, name: name)
    }

    public func renameGroup(id: Int64, to name: String) throws {
        try db.prepare("UPDATE groups SET name = ? WHERE id = ?").bind(.text(name), .int(id)).run()
    }

    /// Nests a group inside another (or, `newParentID` nil, back to the top)
    /// — groups hold groups, like folders (plan). Both stay in the same
    /// collection; a group's `collection_id` never changes. Refuses a move
    /// that would make a group its own descendant, walking up from
    /// `newParentID` to check.
    public func moveGroup(id: Int64, toParent newParentID: Int64?) throws {
        guard let newParentID else {
            try db.prepare("UPDATE groups SET parent_id = NULL WHERE id = ?").bind(.int(id)).run()
            return
        }
        guard newParentID != id else {
            throw DatabaseError(description: "A group can't be nested inside itself.")
        }
        let own = try db.prepare("SELECT collection_id FROM groups WHERE id = ?").bind(.int(id))
        guard try own.step() else { throw DatabaseError(description: "No such group.") }
        let ownCollection = own.int(0)
        let target = try db.prepare("SELECT collection_id FROM groups WHERE id = ?").bind(.int(newParentID))
        guard try target.step() else { throw DatabaseError(description: "No such group.") }
        guard target.int(0) == ownCollection else {
            throw DatabaseError(description: "A group can only be nested inside one in the same collection.")
        }
        var cursor: Int64? = newParentID
        let parentOf = try db.prepare("SELECT parent_id FROM groups WHERE id = ?")
        while let c = cursor {
            guard c != id else {
                throw DatabaseError(description: "A group can't be nested inside its own descendant.")
            }
            parentOf.bind(.int(c))
            guard try parentOf.step() else { break }
            cursor = parentOf.isNull(0) ? nil : parentOf.int(0)
        }
        try db.prepare("UPDATE groups SET parent_id = ? WHERE id = ?").bind(.int(newParentID), .int(id)).run()
    }

    /// Its sub-groups go with it, as in Finder; the files stay in the
    /// collection. Use `snapshotGroupSubtree` first if the caller wants undo.
    public func deleteGroup(id: Int64) throws {
        try db.prepare("DELETE FROM groups WHERE id = ?").bind(.int(id)).run()
    }

    /// Files already in the group are left as they were. Only files already
    /// in the group's own collection are added — **a group's files must be
    /// in its collection** (plan) — so a file not yet in that collection is
    /// silently skipped rather than added to either.
    public func addItems(_ itemIDs: [Int64], toGroup id: Int64) throws {
        guard !itemIDs.isEmpty else { return }
        let ids = itemIDs.map(String.init).joined(separator: ",")
        let now = Date().timeIntervalSince1970
        try db.transaction {
            let next = try nextSortKey("group_items", column: "group_id", id: id)
            try db.prepare("""
                INSERT OR IGNORE INTO group_items (group_id, item_id, added_at, sort_key)
                SELECT ?, ci.item_id, ?, ? FROM collection_items ci
                JOIN groups g ON g.id = ?
                WHERE ci.collection_id = g.collection_id AND ci.item_id IN (\(ids))
                """).bind(.int(id), .double(now), .double(next), .int(id)).run()
        }
    }

    /// Takes files out of a group, and returns when each had been added, so
    /// undo can put them back in their places. The files stay in the collection.
    @discardableResult
    public func removeItems(_ itemIDs: [Int64], fromGroup id: Int64) throws -> [(itemID: Int64, addedAt: Double, sortKey: Double)] {
        try db.transaction {
            let q = try db.prepare("SELECT added_at, sort_key FROM group_items WHERE group_id = ? AND item_id = ?")
            let s = try db.prepare("DELETE FROM group_items WHERE group_id = ? AND item_id = ?")
            var removed: [(itemID: Int64, addedAt: Double, sortKey: Double)] = []
            for item in itemIDs {
                q.bind(.int(id), .int(item))
                if try q.step() { removed.append((item, q.double(0), q.double(1))) }
                try s.bind(.int(id), .int(item)).run()
            }
            return removed
        }
    }

    /// Puts files back in a group as they were: undoing a removal, or the
    /// group side of `removeItems(_:fromCollection:)`.
    public func restoreItems(_ entries: [(itemID: Int64, addedAt: Double, sortKey: Double)], toGroup id: Int64) throws {
        try restoreGroupMemberships(entries.map { (groupID: id, itemID: $0.itemID, addedAt: $0.addedAt, sortKey: $0.sortKey) })
    }

    /// One group's own row and files, to put back on undo — not its
    /// sub-groups; `snapshotGroupSubtree` gathers a whole tree of these,
    /// root first, so a parent always restores before its children.
    public struct GroupSnapshot: Sendable {
        public let id: Int64
        public let collectionID: Int64
        public let parentID: Int64?
        public let name: String
        public let createdAt: Double
        public let items: [(itemID: Int64, addedAt: Double, sortKey: Double)]
    }

    private func snapshotOneGroup(id: Int64) throws -> GroupSnapshot? {
        let g = try db.prepare("SELECT collection_id, parent_id, name, created_at FROM groups WHERE id = ?").bind(.int(id))
        guard try g.step() else { return nil }
        let m = try db.prepare("SELECT item_id, added_at, sort_key FROM group_items WHERE group_id = ?").bind(.int(id))
        var items: [(itemID: Int64, addedAt: Double, sortKey: Double)] = []
        while try m.step() { items.append((m.int(0), m.double(1), m.double(2))) }
        return GroupSnapshot(id: id, collectionID: g.int(0), parentID: g.isNull(1) ? nil : g.int(1),
                              name: g.text(2), createdAt: g.double(3), items: items)
    }

    /// A group and every group nested inside it, root first (breadth-first,
    /// so a parent's row always comes before its children's) — what
    /// `deleteGroup` takes with it, to put back on undo.
    public func snapshotGroupSubtree(id: Int64) throws -> [GroupSnapshot] {
        var out: [GroupSnapshot] = []
        var queue = [id]
        while !queue.isEmpty {
            let gid = queue.removeFirst()
            guard let snap = try snapshotOneGroup(id: gid) else { continue }
            out.append(snap)
            let c = try db.prepare("SELECT id FROM groups WHERE parent_id = ? ORDER BY created_at, id").bind(.int(gid))
            while try c.step() { queue.append(c.int(0)) }
        }
        return out
    }

    /// Every group in a collection, root groups (and their subtrees) first —
    /// what `deleteCollection` takes with it, to put back on undo alongside
    /// the collection itself.
    private func snapshotGroups(inCollection collectionID: Int64) throws -> [GroupSnapshot] {
        let r = try db.prepare("""
            SELECT id FROM groups WHERE collection_id = ? AND parent_id IS NULL ORDER BY created_at, id
            """).bind(.int(collectionID))
        var roots: [Int64] = []
        while try r.step() { roots.append(r.int(0)) }
        return try roots.flatMap { try snapshotGroupSubtree(id: $0) }
    }

    private func restoreGroup(_ snap: GroupSnapshot) throws {
        try db.prepare("INSERT INTO groups (id, collection_id, parent_id, name, created_at) VALUES (?, ?, ?, ?, ?)")
            .bind(.int(snap.id), .int(snap.collectionID), snap.parentID.map { .int($0) } ?? .null,
                  .text(snap.name), .double(snap.createdAt)).run()
        try restoreItems(snap.items, toGroup: snap.id)
    }

    /// Undoes `deleteGroup`: the group (or the whole subtree
    /// `snapshotGroupSubtree` gathered) and its files, each with its old id.
    public func restoreGroupSubtree(_ snaps: [GroupSnapshot]) throws {
        try db.transaction { for g in snaps { try restoreGroup(g) } }
    }

    public func url(for item: MediaItem) -> URL {
        mediaURL.appendingPathComponent(item.relativePath)
    }

    // MARK: Items

    public func allItems() throws -> [MediaItem] {
        let s = try db.prepare("""
            SELECT id, rel_path, hash, kind, width, height, duration, ingested_at, source_path, rating, tags
            FROM items ORDER BY ingested_at, id
            """)
        var out: [MediaItem] = []
        while try s.step() {
            out.append(MediaItem(
                id: s.int(0), relativePath: s.text(1), hash: s.text(2),
                kind: MediaKind(rawValue: s.text(3)) ?? .image,
                pixelWidth: Int(s.int(4)), pixelHeight: Int(s.int(5)),
                duration: s.isNull(6) ? nil : s.double(6),
                ingestedAt: Date(timeIntervalSince1970: s.double(7)),
                sourcePath: s.text(8), rating: Int(s.int(9)), tags: Self.decodeTags(s.text(10))))
        }
        return out
    }

    /// Sets the rating (−1 rejected, 0 unrated, 1…5 stars) on several
    /// files at once.
    public func setRating(_ rating: Int, for itemIDs: [Int64]) throws {
        let r = Int64(Rating.clamped(rating))
        try db.transaction {
            for id in itemIDs {
                try db.prepare("UPDATE items SET rating = ? WHERE id = ?").bind(.int(r), .int(id)).run()
            }
        }
    }

    /// Sets the exact tag list on one file. The Info panel does the
    /// union/intersection logic for tagging several at once; this just writes.
    public func setTags(_ tags: [String], for itemID: Int64) throws {
        try db.prepare("UPDATE items SET tags = ? WHERE id = ?")
            .bind(.text(Self.encodeTags(tags)), .int(itemID)).run()
    }

    static func encodeTags(_ tags: [String]) -> String {
        (try? String(decoding: JSONSerialization.data(withJSONObject: tags), as: UTF8.self)) ?? "[]"
    }

    static func decodeTags(_ json: String) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
        return obj as? [String] ?? []
    }

    public func itemID(forHash hash: String) throws -> Int64? {
        let s = try db.prepare("SELECT id FROM items WHERE hash = ?").bind(.text(hash))
        return try s.step() ? s.int(0) : nil
    }

    public func insertItem(relativePath: String, hash: String, probe: MediaProbe,
                           sourcePath: String) throws -> MediaItem {
        let now = Date()
        try db.prepare("""
            INSERT INTO items (rel_path, hash, kind, width, height, duration, ingested_at, source_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """).bind(.text(relativePath), .text(hash), .text(probe.kind.rawValue),
                      .int(Int64(probe.width)), .int(Int64(probe.height)),
                      probe.duration.map { .double($0) } ?? .null,
                      .double(now.timeIntervalSince1970), .text(sourcePath)).run()
        return MediaItem(id: db.lastInsertID, relativePath: relativePath, hash: hash,
                           kind: probe.kind, pixelWidth: probe.width, pixelHeight: probe.height,
                           duration: probe.duration, ingestedAt: now, sourcePath: sourcePath)
    }

    /// What deleting a file from the library takes with it, kept so it can
    /// all go back: the file's own row, its collection memberships, and
    /// every slide (in every show) that used it. The lane's images
    /// (`shows.overlays`) aren't a `slides` row, so the caller — which
    /// already has each show in memory — restores those itself.
    public struct DeletedItem: Sendable {
        public let item: MediaItem
        public let collectionIDs: [Int64]
        public let slides: [(showID: Int64, slideID: Int64, position: Int64, settings: String)]
    }

    /// Removes files from the library: every slide that used them (across
    /// every show), their collection memberships (cascades from the item
    /// row), then the items themselves. `slides.item_id` has no cascade —
    /// on purpose, so a bug elsewhere can't silently drop a slide — so the
    /// slide rows must go first. Only the database changes; the caller
    /// moves the files themselves to the Trash.
    public func deleteItems(_ itemIDs: [Int64]) throws -> [DeletedItem] {
        try db.transaction {
            var out: [DeletedItem] = []
            for id in itemIDs {
                let s = try db.prepare("""
                    SELECT id, rel_path, hash, kind, width, height, duration, ingested_at, source_path, rating, tags
                    FROM items WHERE id = ?
                    """).bind(.int(id))
                guard try s.step() else { continue }
                let item = MediaItem(id: s.int(0), relativePath: s.text(1), hash: s.text(2),
                                      kind: MediaKind(rawValue: s.text(3)) ?? .image,
                                      pixelWidth: Int(s.int(4)), pixelHeight: Int(s.int(5)),
                                      duration: s.isNull(6) ? nil : s.double(6),
                                      ingestedAt: Date(timeIntervalSince1970: s.double(7)),
                                      sourcePath: s.text(8), rating: Int(s.int(9)), tags: Self.decodeTags(s.text(10)))
                let cs = try db.prepare("SELECT collection_id FROM collection_items WHERE item_id = ?").bind(.int(id))
                var collectionIDs: [Int64] = []
                while try cs.step() { collectionIDs.append(cs.int(0)) }
                let sl = try db.prepare("SELECT id, show_id, position, settings FROM slides WHERE item_id = ?")
                    .bind(.int(id))
                var slides: [(showID: Int64, slideID: Int64, position: Int64, settings: String)] = []
                while try sl.step() {
                    slides.append((showID: sl.int(1), slideID: sl.int(0), position: sl.int(2), settings: sl.text(3)))
                }
                try db.prepare("DELETE FROM slides WHERE item_id = ?").bind(.int(id)).run()
                try db.prepare("DELETE FROM items WHERE id = ?").bind(.int(id)).run()
                out.append(DeletedItem(item: item, collectionIDs: collectionIDs, slides: slides))
            }
            return out
        }
    }

    /// Undoes `deleteItems`: the item row, its collection memberships, and
    /// every slide it had, each back with its original id, so anything else
    /// keyed on it (an undo step still on the stack, a selection) still
    /// lines up. A show or collection that's since been deleted for some
    /// other reason is skipped rather than failing the whole restore.
    public func restoreItems(_ deleted: [DeletedItem]) throws {
        try db.transaction {
            for d in deleted {
                let item = d.item
                try db.prepare("""
                    INSERT INTO items (id, rel_path, hash, kind, width, height, duration, ingested_at,
                                        source_path, rating, tags)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """).bind(.int(item.id), .text(item.relativePath), .text(item.hash), .text(item.kind.rawValue),
                              .int(Int64(item.pixelWidth)), .int(Int64(item.pixelHeight)),
                              item.duration.map { .double($0) } ?? .null,
                              .double(item.ingestedAt.timeIntervalSince1970), .text(item.sourcePath),
                              .int(Int64(item.rating)), .text(Self.encodeTags(item.tags))).run()
                let now = Date().timeIntervalSince1970
                let ci = try db.prepare("""
                    INSERT INTO collection_items (collection_id, item_id, added_at, sort_key) VALUES (?, ?, ?, ?)
                    """)
                for cid in d.collectionIDs {
                    let next = try nextSortKey("collection_items", column: "collection_id", id: cid)
                    try? ci.bind(.int(cid), .int(item.id), .double(now), .double(next)).run()
                }
                let si = try db.prepare("INSERT INTO slides (id, show_id, position, item_id, settings) VALUES (?, ?, ?, ?, ?)")
                for s in d.slides { try? si.bind(.int(s.slideID), .int(s.showID), .int(s.position), .int(item.id), .text(s.settings)).run() }
            }
        }
    }

    /// Renames files on disk and updates their rows to match. A wanted name
    /// already taken — by another file, or by one just renamed earlier in
    /// this same batch — is numbered the way an import would; nothing is
    /// ever silently overwritten. `slides` and `collection_items` refer to
    /// an item by id, never by name, so every show and collection is
    /// untouched. Returns each renamed item's old name, keyed by id — pass
    /// that straight back in to undo it (or to redo an undo).
    @discardableResult
    public func renameItems(_ names: [Int64: String]) throws -> [Int64: String] {
        var previous: [Int64: String] = [:]
        let fm = FileManager.default
        try db.transaction {
            for (id, wanted) in names {
                guard !wanted.isEmpty else { continue }
                let s = try db.prepare("SELECT rel_path FROM items WHERE id = ?").bind(.int(id))
                guard try s.step() else { continue }
                let oldRel = s.text(0)
                guard oldRel != wanted else { continue }
                let oldURL = mediaURL.appendingPathComponent(oldRel)
                guard fm.fileExists(atPath: oldURL.path) else { continue }
                let newURL = Ingest.uniqueURL(in: mediaURL, for: wanted)
                try fm.moveItem(at: oldURL, to: newURL)
                try db.prepare("UPDATE items SET rel_path = ? WHERE id = ?")
                    .bind(.text(newURL.lastPathComponent), .int(id)).run()
                previous[id] = oldRel
            }
        }
        return previous
    }

    /// One item's outcome from `relinkMissingItems`: `newPath` nil means no
    /// file on disk matched its hash, so it's still missing.
    public struct RelinkOutcome: Sendable {
        public let itemID: Int64
        public let oldPath: String
        public let newPath: String?
    }

    /// Repairs the database after files were rearranged by hand in Finder
    /// (plan: "the app owns this folder... the hash-based relink can
    /// recover from it, but that's a repair, not a workflow"). Every file
    /// actually under `Media/` is hashed once; a missing item whose hash
    /// matches one of them is pointed at its new path. `hash` is `UNIQUE`
    /// in the schema, so a match is never ambiguous between two items —
    /// at most one item can ever have a given hash.
    public func relinkMissingItems() throws -> [RelinkOutcome] {
        let fm = FileManager.default
        let s = try db.prepare("SELECT id, rel_path, hash FROM items")
        var rows: [(id: Int64, path: String, hash: String)] = []
        while try s.step() { rows.append((s.int(0), s.text(1), s.text(2))) }

        let missing = rows.filter { !fm.fileExists(atPath: mediaURL.appendingPathComponent($0.path).path) }
        guard !missing.isEmpty else { return [] }

        var byHash: [String: String] = [:]
        // Resolved on both sides: FileManager's enumerator can hand back a
        // path in a different (if equivalent) form than mediaURL's own —
        // /tmp vs /private/tmp, measured directly in a test — which broke
        // a plain string-prefix strip.
        let mediaPath = mediaURL.resolvingSymlinksInPath().path
        for url in Ingest.collect([mediaURL]) {
            guard let hash = try? Ingest.sha256(of: url) else { continue }
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(mediaPath + "/") else { continue }
            byHash[hash] = String(resolved.dropFirst(mediaPath.count + 1))
        }

        return try db.transaction {
            var out: [RelinkOutcome] = []
            for item in missing {
                guard let found = byHash[item.hash] else {
                    out.append(RelinkOutcome(itemID: item.id, oldPath: item.path, newPath: nil))
                    continue
                }
                try db.prepare("UPDATE items SET rel_path = ? WHERE id = ?")
                    .bind(.text(found), .int(item.id)).run()
                out.append(RelinkOutcome(itemID: item.id, oldPath: item.path, newPath: found))
            }
            return out
        }
    }

    // MARK: Shows

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private func json<T: Encodable>(_ v: T) throws -> String {
        String(decoding: try Self.encoder.encode(v), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ s: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(s.utf8))
    }

    public func allShows() throws -> [Show] {
        let s = try db.prepare("SELECT id, name, defaults, overlays, collection_id, rows, music, markers, editor FROM shows ORDER BY created_at, id")
        var shows: [Show] = []
        while try s.step() {
            shows.append(Show(id: s.int(0), name: s.text(1),
                              defaults: decode(ShowDefaults.self, s.text(2)) ?? ShowDefaults(),
                              overlays: OverlayClip.decodeList(s.text(3)),
                              collectionID: s.isNull(4) ? nil : s.int(4),
                              rows: TimelineRow.decodeList(s.text(5)),
                              music: AudioClip.decodeList(s.text(6)),
                              markers: Marker.decodeList(s.text(7)),
                              editor: decode(ShowEditorState.self, s.text(8)) ?? ShowEditorState()))
        }
        let sl = try db.prepare("SELECT id, item_id, settings FROM slides WHERE show_id = ? ORDER BY position")
        for i in shows.indices {
            sl.bind(.int(shows[i].id))
            while try sl.step() {
                shows[i].slides.append(Slide(
                    id: sl.int(0), itemID: sl.int(1),
                    settings: decode(SlideSettings.self, sl.text(2)) ?? SlideSettings()))
            }
        }
        return shows
    }

    /// A new show in a collection. Its files join the collection if they
    /// aren't in it already.
    public func createShow(name: String, collectionID: Int64? = nil, itemIDs: [Int64] = []) throws -> Show {
        let show = try db.transaction { () -> Show in
            try db.prepare("INSERT INTO shows (name, defaults, created_at, collection_id) VALUES (?, ?, ?, ?)")
                .bind(.text(name), .text(try json(ShowDefaults())),
                      .double(Date().timeIntervalSince1970), collectionID.map { .int($0) } ?? .null).run()
            return Show(id: db.lastInsertID, name: name,
                        slides: itemIDs.map { Slide(id: 0, itemID: $0) }, collectionID: collectionID)
        }
        if let collectionID, !itemIDs.isEmpty { try addItems(itemIDs, toCollection: collectionID) }
        return try saveShow(show)
    }

    /// Writes the show and its slide order. Slides with `id <= 0` are new
    /// and get an id; the returned show carries them.
    @discardableResult
    public func saveShow(_ show: Show) throws -> Show {
        try db.transaction {
            var show = show
            try db.prepare("UPDATE shows SET name = ?, defaults = ?, overlays = ?, collection_id = ?, rows = ?, music = ?, markers = ?, editor = ? WHERE id = ?")
                .bind(.text(show.name), .text(try json(show.defaults)), .text(try json(show.overlays)),
                      show.collectionID.map { .int($0) } ?? .null, .text(try json(show.rows)),
                      .text(try json(show.music)), .text(try json(show.markers)), .text(try json(show.editor)),
                      .int(show.id)).run()

            let insert = try db.prepare(
                "INSERT INTO slides (show_id, position, item_id, settings) VALUES (?, ?, ?, ?)")
            // An existing id is written back even if its row is gone: that's
            // how undo restores a removed slide with its identity intact.
            let upsert = try db.prepare("""
                INSERT INTO slides (id, show_id, position, item_id, settings) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET show_id = excluded.show_id, position = excluded.position,
                    item_id = excluded.item_id, settings = excluded.settings
                """)
            for (pos, slide) in show.slides.enumerated() {
                let settings = try json(slide.settings)
                if slide.id > 0 {
                    try upsert.bind(.int(slide.id), .int(show.id), .int(Int64(pos)), .int(slide.itemID),
                                    .text(settings)).run()
                } else {
                    try insert.bind(.int(show.id), .int(Int64(pos)), .int(slide.itemID),
                                    .text(settings)).run()
                    show.slides[pos].id = db.lastInsertID
                }
            }
            // Anything no longer in the list was removed.
            let keep = show.slides.map { String($0.id) }.joined(separator: ",")
            try db.prepare("DELETE FROM slides WHERE show_id = ? AND id NOT IN (\(keep.isEmpty ? "0" : keep))")
                .bind(.int(show.id)).run()
            return show
        }
    }

    public func deleteShow(id: Int64) throws {
        try db.prepare("DELETE FROM shows WHERE id = ?").bind(.int(id)).run()
    }

    /// Everything deleting a show on its own takes with it, to put back on
    /// undo (a show deleted along with its collection is `CollectionSnapshot`'s job).
    public struct ShowSnapshot: Sendable {
        public let show: Show
        public let createdAt: Double
    }

    public func snapshotShow(id: Int64) throws -> ShowSnapshot? {
        let c = try db.prepare("SELECT created_at FROM shows WHERE id = ?").bind(.int(id))
        guard try c.step() else { return nil }
        let createdAt = c.double(0)
        guard let show = try allShows().first(where: { $0.id == id }) else { return nil }
        return ShowSnapshot(show: show, createdAt: createdAt)
    }

    /// Undoes `deleteShow`: the show, with its old id, so undo steps
    /// recorded against it still find it. Slides of files deleted since are
    /// left out, as `restoreCollection` already does for a show's shows.
    public func restoreShow(_ snap: ShowSnapshot) throws {
        try db.transaction {
            try db.prepare("INSERT INTO shows (id, name, defaults, created_at, collection_id) VALUES (?, ?, '{}', ?, ?)")
                .bind(.int(snap.show.id), .text(snap.show.name), .double(snap.createdAt),
                      snap.show.collectionID.map { .int($0) } ?? .null).run()
            let exists = try db.prepare("SELECT 1 FROM items WHERE id = ?")
            var s = snap.show
            s.slides = try s.slides.filter { slide in
                exists.bind(.int(slide.itemID))
                return try exists.step()
            }
            try saveShow(s)
        }
    }
}
