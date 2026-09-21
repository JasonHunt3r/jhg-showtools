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
        try migrate()
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
    }

    public func url(for item: MediaItem) -> URL {
        mediaURL.appendingPathComponent(item.relativePath)
    }

    // MARK: Items

    public func allItems() throws -> [MediaItem] {
        let s = try db.prepare("""
            SELECT id, rel_path, hash, kind, width, height, duration, ingested_at, source_path
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
                sourcePath: s.text(8)))
        }
        return out
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
        let s = try db.prepare("SELECT id, name, defaults FROM shows ORDER BY created_at, id")
        var shows: [Show] = []
        while try s.step() {
            shows.append(Show(id: s.int(0), name: s.text(1),
                              defaults: decode(ShowDefaults.self, s.text(2)) ?? ShowDefaults()))
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

    public func createShow(name: String, itemIDs: [Int64] = []) throws -> Show {
        let show = try db.transaction { () -> Show in
            try db.prepare("INSERT INTO shows (name, defaults, created_at) VALUES (?, ?, ?)")
                .bind(.text(name), .text(try json(ShowDefaults())),
                      .double(Date().timeIntervalSince1970)).run()
            return Show(id: db.lastInsertID, name: name,
                        slides: itemIDs.map { Slide(id: 0, itemID: $0) })
        }
        return try saveShow(show)
    }

    /// Writes the show and its slide order. Slides with `id <= 0` are new
    /// and get an id; the returned show carries them.
    @discardableResult
    public func saveShow(_ show: Show) throws -> Show {
        try db.transaction {
            var show = show
            try db.prepare("UPDATE shows SET name = ?, defaults = ? WHERE id = ?")
                .bind(.text(show.name), .text(try json(show.defaults)), .int(show.id)).run()

            let insert = try db.prepare(
                "INSERT INTO slides (show_id, position, item_id, settings) VALUES (?, ?, ?, ?)")
            let update = try db.prepare(
                "UPDATE slides SET position = ?, item_id = ?, settings = ? WHERE id = ? AND show_id = ?")
            for (pos, slide) in show.slides.enumerated() {
                let settings = try json(slide.settings)
                if slide.id > 0 {
                    try update.bind(.int(Int64(pos)), .int(slide.itemID), .text(settings),
                                    .int(slide.id), .int(show.id)).run()
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
