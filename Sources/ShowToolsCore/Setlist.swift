import Foundation

// Setlist export (plan, Phase 4). A show goes out as a folder: its slides
// numbered in show order at the top, its songs in `music/`, its images-row
// files in `overlays/`, and two manifests — `show.json`, which carries the
// whole show exactly, and `show.tsv`, the readable one to edit in Numbers.

// MARK: - show.json

/// Everything a show is, with files named by their place in the folder
/// rather than by library id. Decoded field by field, like every saved type.
public struct SetlistManifest: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version = SetlistManifest.currentVersion
    public var name: String
    /// The exporting library's `identifier()` and the show's id there, so a
    /// later export of the same show can recognise this folder.
    public var library: String
    public var showID: Int64
    public var exportedAt: Date
    /// Whether the copies had their metadata stripped.
    public var metadataStripped: Bool
    public var defaults: ShowDefaults
    public var slides: [SetlistSlide]
    public var overlays: [SetlistClip<OverlayClip>]
    public var music: [SetlistClip<AudioClip>]
    public var markers: [Marker]
    public var rows: [TimelineRow]
    public var editor: ShowEditorState
    /// Each library file the show uses, once: its rating and tags, which an
    /// import gives only to files it brings in new.
    public var files: [SetlistFileInfo]

    public init(name: String, library: String, showID: Int64, exportedAt: Date,
                metadataStripped: Bool, defaults: ShowDefaults, slides: [SetlistSlide],
                overlays: [SetlistClip<OverlayClip>], music: [SetlistClip<AudioClip>],
                markers: [Marker], rows: [TimelineRow], editor: ShowEditorState,
                files: [SetlistFileInfo]) {
        self.name = name; self.library = library; self.showID = showID
        self.exportedAt = exportedAt; self.metadataStripped = metadataStripped
        self.defaults = defaults; self.slides = slides; self.overlays = overlays
        self.music = music; self.markers = markers; self.rows = rows
        self.editor = editor; self.files = files
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        version = get(.version, 1)
        name = get(.name, "")
        library = get(.library, "")
        showID = get(.showID, 0)
        exportedAt = get(.exportedAt, Date(timeIntervalSince1970: 0))
        metadataStripped = get(.metadataStripped, false)
        defaults = get(.defaults, ShowDefaults())
        slides = get(.slides, Lenient<SetlistSlide>.List()).items
        overlays = get(.overlays, Lenient<SetlistClip<OverlayClip>>.List()).items
        music = get(.music, Lenient<SetlistClip<AudioClip>>.List()).items
        markers = get(.markers, Lenient<Marker>.List()).items
        rows = TimelineRow.normalized(get(.rows, Lenient<TimelineRow>.List()).items)
        editor = get(.editor, ShowEditorState())
        files = get(.files, Lenient<SetlistFileInfo>.List()).items
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// One slide: its file in the folder, the file's library hash (import
/// matches on it first, since a stripped copy hashes differently), the
/// slide's id in the exporting library (auto Ken Burns is seeded from it),
/// and its settings.
public struct SetlistSlide: Codable, Hashable, Sendable {
    public var file: String
    public var hash: String
    public var id: Int64
    public var settings: SlideSettings

    public init(file: String, hash: String, id: Int64, settings: SlideSettings) {
        self.file = file; self.hash = hash; self.id = id; self.settings = settings
    }

    /// A slide without its file is nothing to import, so that fails and the
    /// list skips it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        hash = ((try? c.decodeIfPresent(String.self, forKey: .hash)) ?? nil) ?? ""
        id = ((try? c.decodeIfPresent(Int64.self, forKey: .id)) ?? nil) ?? 0
        settings = ((try? c.decodeIfPresent(SlideSettings.self, forKey: .settings)) ?? nil) ?? SlideSettings()
    }
}

/// A song or lane image and its file. The clip's own `itemID` is the
/// exporting library's and means nothing on import; `file` and `hash` say
/// which file it is.
public struct SetlistClip<Clip: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var file: String
    public var hash: String
    public var clip: Clip

    public init(file: String, hash: String, clip: Clip) {
        self.file = file; self.hash = hash; self.clip = clip
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        hash = ((try? c.decodeIfPresent(String.self, forKey: .hash)) ?? nil) ?? ""
        clip = try c.decode(Clip.self, forKey: .clip)
    }
}

public struct SetlistFileInfo: Codable, Hashable, Sendable {
    public var hash: String
    public var rating: Int
    public var tags: [String]

    public init(hash: String, rating: Int, tags: [String]) {
        self.hash = hash; self.rating = rating; self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash)
        rating = ((try? c.decodeIfPresent(Int.self, forKey: .rating)) ?? nil) ?? 0
        tags = ((try? c.decodeIfPresent([String].self, forKey: .tags)) ?? nil) ?? []
    }
}

/// A list that keeps every element it can read and steps past the rest.
enum Lenient<T: Decodable> {
    struct List: Decodable {
        var items: [T] = []
        init() {}
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            while !c.isAtEnd {
                if let v = try? c.decode(T.self) { items.append(v) } else { _ = try? c.decode(Skip.self) }
            }
        }
    }
    struct Skip: Decodable {}
}

// MARK: - show.tsv

/// The readable manifest: one line per slide, a header row, show-wide
/// defaults in `#` lines at the top, and an empty cell for "use the
/// default". It carries only what reads well as text; `show.json` has the
/// rest. Columns are found by their header, so they can be moved.
///
/// Numbers are written short (at most three decimals), so a cell can be
/// rounder than the value behind it. On import (4b) a cell still reading
/// exactly what export wrote keeps the JSON's exact value; only a changed
/// cell replaces it.
public enum SetlistTSV {
    public static let firstLine = "# ShowTools setlist v1"
    public static let columns = ["file", "length", "transition", "kenburns_start",
                                 "kenburns_end", "fit", "rotation", "background"]

    public static func text(for m: SetlistManifest) -> String {
        var lines = [firstLine]
        func meta(_ k: String, _ v: String) { lines.append("# \(k)\t\(v)") }
        meta("name", clean(m.name))
        meta("default_length", number(m.defaults.length))
        meta("default_transition", transition(m.defaults.transition))
        meta("default_kenburns", kenBurnsStart(m.defaults.kenBurns))
        meta("default_fit", m.defaults.fit.rawValue)
        meta("default_background", colour(m.defaults.background))
        meta("video_clip_length", m.defaults.videoUsesClipLength ? "yes" : "no")
        meta("loop", m.defaults.loop ? "yes" : "no")
        for song in m.music { meta("music", song.file) }
        lines.append(columns.joined(separator: "\t"))
        for s in m.slides { lines.append(cells(for: s).joined(separator: "\t")) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A slide's cells, in `columns` order.
    public static func cells(for s: SetlistSlide) -> [String] {
        let st = s.settings
        return [
            s.file,
            st.length.map(length) ?? "",
            st.transition.map(transition) ?? "",
            st.kenBurns.map(kenBurnsStart) ?? "",
            st.kenBurns.map(kenBurnsEnd) ?? "",
            st.fit?.rawValue ?? "",
            st.rotation.map(rotation) ?? "",
            st.background.map(colour) ?? "",
        ]
    }

    // MARK: Values as text

    /// Short: whole numbers without a point, others to three decimals at most.
    public static func number(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int64(x)) }
        var s = String(format: "%.3f", x)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    public static func length(_ l: SlideLength) -> String {
        switch l {
        case .seconds(let x): number(x)
        case .clip: "clip"
        }
    }

    /// `dissolve 2 lead 1`, `swipe left 0.5`: the style, its direction when
    /// the style has one, the duration, and the lead when it isn't 0.
    public static func transition(_ t: Transition) -> String {
        var parts = [t.style.rawValue]
        if t.style.usesDirection { parts.append(t.direction.rawValue) }
        parts.append(number(t.duration))
        if t.lead != 0 { parts += ["lead", number(t.lead)] }
        return parts.joined(separator: " ")
    }

    public static func frame(_ f: KenBurnsFrame) -> String {
        [f.x, f.y, f.zoom].map(number).joined(separator: ",")
    }

    public static func kenBurnsStart(_ k: KenBurnsSetting) -> String {
        switch k {
        case .off: "off"
        case .auto: "auto"
        case .custom(let kb): frame(kb.start)
        }
    }

    public static func kenBurnsEnd(_ k: KenBurnsSetting) -> String {
        if case .custom(let kb) = k { return frame(kb.end) }
        return ""
    }

    /// `off` when switched off; `0 to 90` in angles mode; `30/s`, or
    /// `30/s from 10`, in speed mode.
    public static func rotation(_ r: Rotation) -> String {
        guard r.enabled else { return "off" }
        switch r.mode {
        case .angles: return "\(number(r.startAngle)) to \(number(r.endAngle))"
        case .speed:
            return r.startAngle == 0 ? "\(number(r.speed))/s"
                : "\(number(r.speed))/s from \(number(r.startAngle))"
        }
    }

    public static func colour(_ c: SRGBColor) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.red), byte(c.green), byte(c.blue))
    }

    /// Tabs and line breaks would break the table; they become spaces.
    public static func clean(_ s: String) -> String {
        String(s.map { $0 == "\t" || $0.isNewline ? " " : $0 })
    }
}

// MARK: - Export

public enum SetlistExport {

    public enum Failure: Error, CustomStringConvertible, Equatable {
        /// The show uses files the library can't find: relink first.
        case missingFiles([String])
        /// The folder is there and isn't an earlier export of this show.
        case folderNotEmpty(String)

        public var description: String {
            switch self {
            case .missingFiles(let names):
                "\(names.count) file\(names.count == 1 ? "" : "s") the show uses can't be found: \(names.prefix(5).joined(separator: ", "))"
            case .folderNotEmpty(let name):
                "“\(name)” is already there and isn't an earlier export of this show"
            }
        }
    }

    public struct Options: Sendable {
        /// Strip metadata from the copies (the default; a Preferences
        /// setting turns it off).
        public var stripMetadata = true
        /// Add `.noindex` to the folder's name, so Spotlight skips it.
        public var hideFromSpotlight = false
        /// The folder's name, as typed in the Export panel. Nil: the show's.
        public var folderName: String?

        public init(stripMetadata: Bool = true, hideFromSpotlight: Bool = false, folderName: String? = nil) {
            self.stripMetadata = stripMetadata
            self.hideFromSpotlight = hideFromSpotlight
            self.folderName = folderName
        }
    }

    /// One file to write: from the library, to its path in the folder.
    public struct Copy: Hashable, Sendable {
        public var source: URL
        public var path: String
        public var kind: MediaKind
        /// The library item, so repeats of one file are stripped only once.
        public var itemID: Int64
    }

    /// Everything the export needs from the library, read up front on the
    /// library's own thread; `write` then runs anywhere.
    public struct Plan: Sendable {
        public var folderName: String
        public var manifest: SetlistManifest
        public var copies: [Copy]
    }

    public struct Result: Sendable {
        public var folder: URL
        public var fileCount: Int
        /// Files copied as they are because their metadata couldn't be
        /// stripped, with the reason. Empty when nothing was stripped.
        public var notStripped: [(path: String, reason: String)]
        /// An earlier export of the show was replaced.
        public var replaced: Bool
    }

    /// Reads what the show needs from the library. Fails, before anything
    /// is written, if any file the show uses is missing.
    public static func plan(_ show: Show, from lib: Library, options: Options = Options(),
                            now: Date = Date()) throws -> Plan {
        let items = Dictionary(uniqueKeysWithValues: try lib.allItems().map { ($0.id, $0) })
        let fm = FileManager.default
        var missing: [String] = []
        func item(_ id: Int64) -> MediaItem? {
            guard let it = items[id] else { missing.append("item \(id)"); return nil }
            if !fm.fileExists(atPath: lib.url(for: it).path) { missing.append(it.fileName) }
            return it
        }

        var copies: [Copy] = []
        var used: [Int64: MediaItem] = [:]
        func add(_ it: MediaItem, at path: String) {
            copies.append(Copy(source: lib.url(for: it), path: path, kind: it.kind, itemID: it.id))
            used[it.id] = it
        }

        // Slides: numbered, padded to the slide count (never under three
        // digits), one file per slide even when a file repeats.
        let width = max(3, String(show.slides.count).count)
        var slides: [SetlistSlide] = []
        for (i, s) in show.slides.enumerated() {
            guard let it = item(s.itemID) else { continue }
            let name = String(format: "%0\(width)d_", i + 1) + SetlistTSV.clean(it.fileName)
            add(it, at: name)
            slides.append(SetlistSlide(file: name, hash: it.hash, id: s.id, settings: s.settings))
        }

        // Songs and lane images: one file per library item, in their folders.
        func place<C>(_ clips: [C], in dir: String, itemID: (C) -> Int64) -> [(C, String, String)] {
            var names: [Int64: String] = [:]
            var taken: Set<String> = []
            var out: [(C, String, String)] = []
            for c in clips {
                guard let it = item(itemID(c)) else { continue }
                if names[it.id] == nil {
                    let path = dir + "/" + uniqueName(SetlistTSV.clean(it.fileName), in: dir, taken: taken)
                    taken.insert(path.lowercased())
                    names[it.id] = path
                    add(it, at: path)
                }
                out.append((c, names[it.id]!, it.hash))
            }
            return out
        }
        let music = place(show.music, in: "music") { $0.itemID }
            .map { SetlistClip(file: $0.1, hash: $0.2, clip: $0.0) }
        let overlays = place(show.overlays, in: "overlays") { $0.itemID }
            .map { SetlistClip(file: $0.1, hash: $0.2, clip: $0.0) }

        if !missing.isEmpty { throw Failure.missingFiles(missing) }

        let files = used.values.sorted { $0.id < $1.id }
            .map { SetlistFileInfo(hash: $0.hash, rating: $0.rating, tags: $0.tags) }
        let manifest = SetlistManifest(
            name: show.name, library: try lib.identifier(), showID: show.id, exportedAt: now,
            metadataStripped: options.stripMetadata, defaults: show.defaults, slides: slides,
            overlays: overlays, music: music, markers: show.markers, rows: show.rows,
            editor: show.editor, files: files)
        var folder = folderName(for: options.folderName ?? show.name)
        if folder.lowercased().hasSuffix(".noindex") { folder = String(folder.dropLast(".noindex".count)) }
        if options.hideFromSpotlight { folder += ".noindex" }
        return Plan(folderName: folder, manifest: manifest, copies: copies)
    }

    /// A show's name as a folder name: no slashes or colons, no leading dot.
    public static func folderName(for name: String) -> String {
        var s = String(SetlistTSV.clean(name).map { $0 == "/" || $0 == ":" ? "-" : $0 })
            .trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Untitled Show" : s
    }

    /// `name`, or `name 2`, `name 3`… when `dir/name` is in `taken`
    /// (lowercased, as the Mac's file system compares names).
    static func uniqueName(_ name: String, in dir: String, taken: Set<String>) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var n = 2
        while taken.contains((dir + "/" + candidate).lowercased()) {
            candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            n += 1
        }
        return candidate
    }

    /// Whether the folder holds an earlier export of the same show.
    public static func isEarlierExport(_ folder: URL, of m: SetlistManifest) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("show.json")),
              let old = try? SetlistManifest.decoder().decode(SetlistManifest.self, from: data)
        else { return false }
        return !old.library.isEmpty && old.library == m.library && old.showID == m.showID
    }

    /// Writes the folder inside `parent`. It's built beside it under a hidden
    /// name and moved into place only when complete, so a failed export
    /// leaves nothing half-written. An earlier export of the same show is
    /// replaced, the old one going to `discard` (the Trash, by default).
    public static func write(
        _ plan: Plan, into parent: URL, options: Options = Options(),
        discard: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> Result {
        let fm = FileManager.default
        let dest = parent.appendingPathComponent(plan.folderName, isDirectory: true)
        var replacing = false
        var emptyDest = false
        if fm.fileExists(atPath: dest.path) {
            let contents = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? ["?"])
                .filter { $0 != ".DS_Store" }
            if isEarlierExport(dest, of: plan.manifest) { replacing = true }
            else if contents.isEmpty { emptyDest = true }
            else { throw Failure.folderNotEmpty(plan.folderName) }
        }

        let staging = parent.appendingPathComponent(".\(plan.folderName).exporting-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var notStripped: [(path: String, reason: String)] = []
        do {
            var firstCopy: [Int64: URL] = [:]
            for (n, c) in plan.copies.enumerated() {
                let out = staging.appendingPathComponent(c.path)
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let earlier = firstCopy[c.itemID] {
                    // A repeat: a clone of the copy already made, stripped or not.
                    try fm.copyItem(at: earlier, to: out)
                } else if options.stripMetadata {
                    do {
                        try await MetadataStrip.strip(c.source, to: out, kind: c.kind)
                    } catch {
                        notStripped.append((c.path, "\(error)"))
                        try fm.copyItem(at: c.source, to: out)
                    }
                } else {
                    // copyItem clones on APFS: no space used on the same drive.
                    try fm.copyItem(at: c.source, to: out)
                }
                if firstCopy[c.itemID] == nil { firstCopy[c.itemID] = out }
                progress(n + 1, plan.copies.count)
            }
            let json = try SetlistManifest.encoder().encode(plan.manifest)
            try json.write(to: staging.appendingPathComponent("show.json"))
            try Data(SetlistTSV.text(for: plan.manifest).utf8)
                .write(to: staging.appendingPathComponent("show.tsv"))

            if replacing { try discard(dest) } else if emptyDest { try fm.removeItem(at: dest) }
            try fm.moveItem(at: staging, to: dest)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        return Result(folder: dest, fileCount: plan.copies.count, notStripped: notStripped,
                      replaced: replacing)
    }
}
