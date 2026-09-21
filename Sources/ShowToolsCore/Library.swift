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

    /// The schema version `migrate` brings a library up to.
    public static let schemaVersion = 5

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

    public static let startingCollectionName = "Untitled Collection"

    // MARK: Collections

    public func allCollections() throws -> [MediaCollection] {
        let s = try db.prepare("SELECT id, name FROM collections ORDER BY created_at, id")
        var out: [MediaCollection] = []
        while try s.step() { out.append(MediaCollection(id: s.int(0), name: s.text(1))) }
        let m = try db.prepare("SELECT collection_id, item_id FROM collection_items ORDER BY added_at, item_id")
        var members: [Int64: [Int64]] = [:]
        while try m.step() { members[m.int(0), default: []].append(m.int(1)) }
        for i in out.indices { out[i].itemIDs = members[out[i].id] ?? [] }
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

    /// Files already in it are left as they were.
    public func addItems(_ itemIDs: [Int64], toCollection id: Int64) throws {
        let now = Date().timeIntervalSince1970
        try db.transaction {
            let s = try db.prepare("""
                INSERT OR IGNORE INTO collection_items (collection_id, item_id, added_at) VALUES (?, ?, ?)
                """)
            for item in itemIDs { try s.bind(.int(id), .int(item), .double(now)).run() }
        }
    }

    public func removeItems(_ itemIDs: [Int64], fromCollection id: Int64) throws {
        try db.transaction {
            let s = try db.prepare("DELETE FROM collection_items WHERE collection_id = ? AND item_id = ?")
            for item in itemIDs { try s.bind(.int(id), .int(item)).run() }
        }
    }

    public func url(for item: MediaItem) -> URL {
        mediaURL.appendingPathComponent(item.relativePath)
    }

    // MARK: Items

    public func allItems() throws -> [MediaItem] {
        let s = try db.prepare("""
            SELECT id, rel_path, hash, kind, width, height, duration, ingested_at, source_path, rating
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
                sourcePath: s.text(8), rating: Int(s.int(9))))
        }
        return out
    }

    /// Sets the star rating (0…5) on several files at once.
    public func setRating(_ rating: Int, for itemIDs: [Int64]) throws {
        let r = Int64(min(max(rating, 0), 5))
        try db.transaction {
            for id in itemIDs {
                try db.prepare("UPDATE items SET rating = ? WHERE id = ?").bind(.int(r), .int(id)).run()
            }
        }
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
        let s = try db.prepare("SELECT id, name, defaults, overlays, collection_id FROM shows ORDER BY created_at, id")
        var shows: [Show] = []
        while try s.step() {
            shows.append(Show(id: s.int(0), name: s.text(1),
                              defaults: decode(ShowDefaults.self, s.text(2)) ?? ShowDefaults(),
                              overlays: OverlayClip.decodeList(s.text(3)),
                              collectionID: s.isNull(4) ? nil : s.int(4)))
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
            try db.prepare("UPDATE shows SET name = ?, defaults = ?, overlays = ?, collection_id = ? WHERE id = ?")
                .bind(.text(show.name), .text(try json(show.defaults)), .text(try json(show.overlays)),
                      show.collectionID.map { .int($0) } ?? .null, .int(show.id)).run()

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
}
