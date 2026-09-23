import Foundation
import UniformTypeIdentifiers

// Setlist import (plan, Phase 4). An exported folder becomes a new show:
// `show.json` supplies everything, and `show.tsv` has the last word on what
// it shows — slide order, and any cell changed since export. A folder with
// neither is read as its pictures in Finder's name order.

// MARK: - Reading show.tsv

extension SetlistTSV {

    public struct Table: Sendable {
        /// `# key<tab>value` lines, keys lowercased.
        public var meta: [String: String] = [:]
        public var header: [String] = []
        /// Each row's cells by column name, and its line number in the file.
        public var rows: [(line: Int, cells: [String: String])] = []

        public func has(_ column: String) -> Bool { header.contains(column) }
    }

    public struct BadCell: Error, CustomStringConvertible {
        public var text: String
        public var description: String { "can't read “\(text)”" }
    }

    /// Reads the table. The header is the first line not starting with `#`;
    /// blank lines are skipped. Column names are matched without case, and a
    /// cell a spreadsheet wrapped in quotes is unwrapped.
    public static func parse(_ text: String) -> Table {
        var t = Table()
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let cells = line.components(separatedBy: "\t").map(unquote)
            if line.hasPrefix("#") {
                let key = cells[0].dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                if cells.count > 1 { t.meta[key] = cells[1] }
                continue
            }
            if t.header.isEmpty {
                t.header = cells.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                continue
            }
            var row: [String: String] = [:]
            for (i, name) in t.header.enumerated() where !name.isEmpty {
                row[name] = i < cells.count ? cells[i] : ""
            }
            t.rows.append((n + 1, row))
        }
        return t
    }

    static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
    }

    // MARK: Text to values. Empty text is never passed: it means "default".

    static func parseNumber(_ s: String) throws -> Double {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v.isFinite else { throw BadCell(text: s) }
        return v
    }

    public static func parseLength(_ s: String) throws -> SlideLength {
        if s.trimmingCharacters(in: .whitespaces).lowercased() == "clip" { return .clip }
        let v = try parseNumber(s)
        guard v > 0 else { throw BadCell(text: s) }
        return .seconds(v)
    }

    public static func parseTransition(_ s: String) throws -> Transition {
        var words = s.split(separator: " ").map { $0.lowercased() }
        guard !words.isEmpty,
              let style = TransitionStyle.allCases.first(where: { $0.rawValue.lowercased() == words[0] })
        else { throw BadCell(text: s) }
        words.removeFirst()
        var direction = Direction.left
        if let d = words.first.flatMap({ Direction(rawValue: $0) }) { direction = d; words.removeFirst() }
        guard let first = words.first else { throw BadCell(text: s) }
        let duration = try parseNumber(first)
        words.removeFirst()
        var lead = 0.0
        if words.first == "lead", words.count == 2 { lead = try parseNumber(words[1]); words = [] }
        guard words.isEmpty, duration >= 0 else { throw BadCell(text: s) }
        return Transition(style: style, duration: duration, direction: direction, lead: lead)
    }

    public static func parseFrame(_ s: String) throws -> PanAndZoomFrame {
        let v = try s.split(separator: ",").map { try parseNumber(String($0)) }
        guard v.count == 3, v[2] > 0 else { throw BadCell(text: s) }
        return PanAndZoomFrame(x: v[0], y: v[1], zoom: v[2])
    }

    /// The two Pan and Zoom cells together. A move with no end holds still at
    /// its start. `base` supplies what the cells don't carry (easing,
    /// acceleration, freeze).
    public static func parsePanAndZoom(start: String, end: String, base: PanAndZoomSetting?) throws -> PanAndZoomSetting? {
        let s = start.trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "": return nil
        case "off": return .off
        case "auto": return .auto
        default:
            let a = try parseFrame(s)
            let b = end.trimmingCharacters(in: .whitespaces).isEmpty ? a : try parseFrame(end)
            if case .custom(var kb) = base { kb.start = a; kb.end = b; return .custom(kb) }
            return .custom(PanAndZoom(start: a, end: b))
        }
    }

    public static func parseFit(_ s: String) throws -> Fit {
        guard let f = Fit(rawValue: s.trimmingCharacters(in: .whitespaces).lowercased()) else { throw BadCell(text: s) }
        return f
    }

    /// `off`, `0 to 90`, `30/s` or `30/s from 10`. `base` keeps what the
    /// cell doesn't carry (pivots, acceleration, freeze).
    public static func parseRotation(_ s: String, base: Rotation?) throws -> Rotation {
        var r = base ?? Rotation()
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "off" { r.enabled = false; return r }
        r.enabled = true
        let words = t.split(separator: " ").map(String.init)
        if words.count == 3, words[1] == "to" {
            r.mode = .angles
            r.startAngle = try parseNumber(words[0])
            r.endAngle = try parseNumber(words[2])
            return r
        }
        if let first = words.first, first.hasSuffix("/s"), words.count == 1 || (words.count == 3 && words[1] == "from") {
            r.mode = .speed
            r.speed = try parseNumber(String(first.dropLast(2)))
            r.startAngle = words.count == 3 ? try parseNumber(words[2]) : 0
            return r
        }
        throw BadCell(text: s)
    }

    public static func parseColour(_ s: String) throws -> SRGBColor {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { throw BadCell(text: s) }
        return SRGBColor(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255,
                         blue: Double(v & 0xff) / 255)
    }

    public static func parseYesNo(_ s: String) throws -> Bool {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "yes", "true", "1", "on": return true
        case "no", "false", "0", "off": return false
        default: throw BadCell(text: s)
        }
    }
}

// MARK: - Import

public enum SetlistImport {

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case notAFolder
        case nothingToImport

        public var description: String {
            switch self {
            case .notAFolder: "that isn't a folder"
            case .nothingToImport: "the folder has no pictures to make a show from"
            }
        }
    }

    /// A file the show refers to: its path in the folder, the library hash
    /// the manifest recorded for it (matched first), and the hash of the
    /// file actually in the folder (nil when it's missing).
    public struct FileRef: Hashable, Sendable {
        public var path: String
        public var libraryHash: String?
        public var fileHash: String?
        public var url: URL
    }

    /// What the folder describes, JSON and TSV already merged. Nothing here
    /// touches a library, so it's read off the main thread.
    public struct Reading: Sendable {
        public var folder: URL
        /// The folder's name without `.noindex`: the new show's name.
        public var name: String
        public var defaults: ShowDefaults
        public var slides: [(file: String, settings: SlideSettings)]
        public var music: [SetlistClip<AudioClip>]
        public var overlays: [SetlistClip<OverlayClip>]
        public var markers: [Marker]
        public var rows: [TimelineRow]
        public var editor: ShowEditorState
        /// Every file referred to, by path.
        public var files: [String: FileRef]
        /// Ratings and tags by library hash, for files brought in new.
        public var fileInfo: [String: SetlistFileInfo]
        /// Which manifests were read.
        public var hadJSON: Bool
        public var hadTSV: Bool
        /// What couldn't be read or found, for the import panel to show.
        public var problems: [String]
    }

    public static func read(_ folder: URL) async throws -> Reading {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw Failure.notAFolder
        }
        var problems: [String] = []
        let manifest: SetlistManifest? = {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("show.json")) else { return nil }
            do { return try SetlistManifest.decoder().decode(SetlistManifest.self, from: data) } catch {
                problems.append("show.json couldn't be read, so it was ignored")
                return nil
            }
        }()
        let table: SetlistTSV.Table? = (try? String(contentsOf: folder.appendingPathComponent("show.tsv"),
                                                    encoding: .utf8)).map(SetlistTSV.parse)

        var r = Reading(
            folder: folder, name: showName(for: folder), defaults: manifest?.defaults ?? ShowDefaults(),
            slides: [], music: manifest?.music ?? [], overlays: manifest?.overlays ?? [],
            markers: manifest?.markers ?? [], rows: manifest?.rows ?? TimelineRow.defaultOrder(),
            editor: manifest?.editor ?? ShowEditorState(), files: [:],
            fileInfo: Dictionary((manifest?.files ?? []).map { ($0.hash, $0) }, uniquingKeysWith: { a, _ in a }),
            hadJSON: manifest != nil, hadTSV: table != nil, problems: [])
        var libraryHash: [String: String] = [:]
        for s in manifest?.slides ?? [] { libraryHash[s.file] = s.hash }
        for c in r.music { libraryHash[c.file] = c.hash }
        for c in r.overlays { libraryHash[c.file] = c.hash }

        if let table, table.has("file") {
            r.defaults = mergeDefaults(r.defaults, table.meta, problems: &problems)
            r.slides = mergeSlides(manifest?.slides ?? [], table, problems: &problems)
        } else if let table, !table.header.isEmpty || !table.rows.isEmpty {
            problems.append("show.tsv has no “file” column, so it was ignored")
            r.hadTSV = false
            r.slides = (manifest?.slides ?? []).map { ($0.file, seeded($0)) }
        } else if let manifest {
            r.slides = manifest.slides.map { ($0.file, seeded($0)) }
        } else {
            // No manifest: the folder's pictures in Finder's name order.
            let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { !$0.hasPrefix(".") && Ingest.isMedia(folder.appendingPathComponent($0)) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for n in names {
                if isSong(n) { problems.append("\(n) is a song; add it to the music row by hand") }
                else { r.slides.append((n, SlideSettings())) }
            }
        }

        // Every file referred to: where it is, and its hash if it's there.
        var paths = r.slides.map(\.file) + r.music.map(\.file) + r.overlays.map(\.file)
        paths = paths.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        for p in paths {
            guard let url = inside(folder, p) else {
                problems.append("\(p) is outside the folder, so it was left out")
                continue
            }
            let hash = fm.fileExists(atPath: url.path) ? try? Ingest.sha256(of: url) : nil
            r.files[p] = FileRef(path: p, libraryHash: libraryHash[p], fileHash: hash, url: url)
        }
        r.slides.removeAll { r.files[$0.file] == nil }
        r.music.removeAll { r.files[$0.file] == nil }
        r.overlays.removeAll { r.files[$0.file] == nil }
        if r.slides.isEmpty && r.music.isEmpty && r.overlays.isEmpty { throw Failure.nothingToImport }
        r.problems = problems
        return r
    }

    /// The folder's name, without `.noindex`.
    public static func showName(for folder: URL) -> String {
        let n = folder.lastPathComponent
        return n.lowercased().hasSuffix(".noindex") ? String(n.dropLast(".noindex".count)) : n
    }

    static func isSong(_ name: String) -> Bool {
        UTType(filenameExtension: (name as NSString).pathExtension)?.conforms(to: .audio) == true
    }

    /// `path` inside `folder`, or nil if it climbs out of it.
    static func inside(_ folder: URL, _ path: String) -> URL? {
        let url = folder.appendingPathComponent(path).standardizedFileURL
        let root = folder.standardizedFileURL.path
        return url.path.hasPrefix(root + "/") ? url : nil
    }

    /// A slide's settings with its exported id kept as its auto Pan and Zoom
    /// seed, unless it already carries one from an earlier import.
    static func seeded(_ s: SetlistSlide) -> SlideSettings {
        var st = s.settings
        if st.panAndZoomSeed == nil, s.id != 0 { st.panAndZoomSeed = s.id }
        return st
    }

    // MARK: Merging the TSV over the JSON

    /// A cell still reading what export would write for the JSON's value
    /// keeps that exact value; a changed one replaces it; one that can't be
    /// read keeps it too, and is reported.
    static func merge<T>(_ base: T?, cell: String?, written: (T) -> String, where place: String,
                         problems: inout [String], parse: (String) throws -> T?) -> T? {
        guard let cell else { return base }
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        if trimmed == (base.map(written) ?? "") { return base }
        if trimmed.isEmpty { return nil }
        do { return try parse(trimmed) } catch {
            problems.append("\(place): \(error)")
            return base
        }
    }

    static func mergeSlides(_ json: [SetlistSlide], _ t: SetlistTSV.Table, problems: inout [String]) -> [(file: String, settings: SlideSettings)] {
        var byFile: [String: SetlistSlide] = [:]
        for s in json where byFile[s.file] == nil { byFile[s.file] = s }
        var used: Set<String> = []
        var out: [(file: String, settings: SlideSettings)] = []
        for (line, row) in t.rows {
            let file = (row["file"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !file.isEmpty else { continue }
            let js = byFile[file] ?? byFile.first { $0.key.lowercased() == file.lowercased() }?.value
            var st = js.map(seeded) ?? SlideSettings()
            // A row repeated in the spreadsheet is a second use: its own auto move.
            if let js, used.contains(js.file) { st.panAndZoomSeed = nil }
            if let js { used.insert(js.file) }
            let at = { (col: String) in "show.tsv line \(line), \(col)" }

            st.length = merge(st.length, cell: row["length"], written: SetlistTSV.length,
                              where: at("length"), problems: &problems, parse: SetlistTSV.parseLength)
            st.transition = merge(st.transition, cell: row["transition"], written: SetlistTSV.transition,
                                  where: at("transition"), problems: &problems, parse: SetlistTSV.parseTransition)
            if row["panzoom_start"] != nil || row["panzoom_end"] != nil {
                let base = st.panAndZoom
                let start = row["panzoom_start"] ?? base.map(SetlistTSV.panAndZoomStart) ?? ""
                let end = row["panzoom_end"] ?? base.map(SetlistTSV.panAndZoomEnd) ?? ""
                let wasStart = base.map(SetlistTSV.panAndZoomStart) ?? ""
                let wasEnd = base.map(SetlistTSV.panAndZoomEnd) ?? ""
                if start.trimmingCharacters(in: .whitespaces) != wasStart || end.trimmingCharacters(in: .whitespaces) != wasEnd {
                    do { st.panAndZoom = try SetlistTSV.parsePanAndZoom(start: start, end: end, base: base) } catch {
                        problems.append("\(at("Pan and Zoom")): \(error)")
                    }
                }
            }
            st.fit = merge(st.fit, cell: row["fit"], written: { $0.rawValue },
                           where: at("fit"), problems: &problems, parse: SetlistTSV.parseFit)
            let rotationBase = st.rotation
            st.rotation = merge(st.rotation, cell: row["rotation"], written: SetlistTSV.rotation,
                                where: at("rotation"), problems: &problems) {
                try SetlistTSV.parseRotation($0, base: rotationBase)
            }
            st.background = merge(st.background, cell: row["background"], written: SetlistTSV.colour,
                                  where: at("background"), problems: &problems, parse: SetlistTSV.parseColour)
            out.append((js?.file ?? file, st))
        }
        return out
    }

    static func mergeDefaults(_ d: ShowDefaults, _ meta: [String: String], problems: inout [String]) -> ShowDefaults {
        var d = d
        let at = { (k: String) in "show.tsv, # \(k)" }
        d.length = merge(d.length, cell: meta["default_length"], written: SetlistTSV.number,
                         where: at("default_length"), problems: &problems) {
            let v = try SetlistTSV.parseNumber($0)
            guard v > 0 else { throw SetlistTSV.BadCell(text: $0) }
            return v
        } ?? d.length
        d.transition = merge(d.transition, cell: meta["default_transition"], written: SetlistTSV.transition,
                             where: at("default_transition"), problems: &problems,
                             parse: SetlistTSV.parseTransition) ?? d.transition
        d.panAndZoom = merge(d.panAndZoom, cell: meta["default_panzoom"], written: SetlistTSV.panAndZoomStart,
                           where: at("default_panzoom"), problems: &problems) {
            switch $0.lowercased() {
            case "off": return PanAndZoomSetting.off
            case "auto": return .auto
            default: throw SetlistTSV.BadCell(text: $0)
            }
        } ?? d.panAndZoom
        d.fit = merge(d.fit, cell: meta["default_fit"], written: { $0.rawValue },
                      where: at("default_fit"), problems: &problems, parse: SetlistTSV.parseFit) ?? d.fit
        d.background = merge(d.background, cell: meta["default_background"], written: SetlistTSV.colour,
                             where: at("default_background"), problems: &problems,
                             parse: SetlistTSV.parseColour) ?? d.background
        d.videoUsesClipLength = merge(d.videoUsesClipLength, cell: meta["video_clip_length"],
                                      written: { $0 ? "yes" : "no" }, where: at("video_clip_length"),
                                      problems: &problems, parse: SetlistTSV.parseYesNo) ?? d.videoUsesClipLength
        d.loop = merge(d.loop, cell: meta["loop"], written: { $0 ? "yes" : "no" }, where: at("loop"),
                       problems: &problems, parse: SetlistTSV.parseYesNo) ?? d.loop
        return d
    }

    // MARK: Into the library

    /// The files the library doesn't have yet, matched by the manifest's
    /// library hash first (a stripped copy hashes differently), then by the
    /// file's own. Import these, then call `makeShow`.
    public static func filesToImport(_ r: Reading, lib: Library) throws -> [URL] {
        var out: [URL] = []
        for ref in r.files.values.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            if try itemID(for: ref, in: lib) != nil { continue }
            if ref.fileHash != nil { out.append(ref.url) }
        }
        return out
    }

    static func itemID(for ref: FileRef, in lib: Library) throws -> Int64? {
        if let h = ref.libraryHash, !h.isEmpty, let id = try lib.itemID(forHash: h) { return id }
        if let h = ref.fileHash, let id = try lib.itemID(forHash: h) { return id }
        return nil
    }

    public struct Result: Sendable {
        public var show: Show
        /// Files the show uses that were already in the library.
        public var reused: Int
        /// What couldn't be read or found, including files that never made
        /// it into the library.
        public var problems: [String]
    }

    /// Builds the show once its files are in the library. `imported` is the
    /// items just brought in for it: they alone get the manifest's ratings
    /// and tags. The show and every file it uses go into `collectionID`.
    public static func makeShow(_ r: Reading, in lib: Library, collectionID: Int64?,
                                imported: Set<Int64>) throws -> Result {
        var problems = r.problems
        var ids: [String: Int64] = [:]
        for ref in r.files.values {
            if let id = try itemID(for: ref, in: lib) { ids[ref.path] = id }
            else { problems.append("\(ref.path) \(ref.fileHash == nil ? "isn't in the folder" : "couldn't be imported")") }
        }
        let items = Dictionary(uniqueKeysWithValues: try lib.allItems().map { ($0.id, $0) })

        var show = try lib.createShow(name: r.name, collectionID: collectionID)
        show.defaults = r.defaults
        show.slides = r.slides.compactMap { s in
            guard let id = ids[s.file], items[id]?.kind.isPicture == true else { return nil }
            return Slide(id: 0, itemID: id, settings: s.settings)
        }
        show.music = r.music.compactMap { c in
            guard let id = ids[c.file], items[id]?.kind == .audio else { return nil }
            var clip = c.clip; clip.itemID = id; return clip
        }
        show.overlays = r.overlays.compactMap { c in
            guard let id = ids[c.file], items[id]?.kind.isPicture == true else { return nil }
            var clip = c.clip; clip.itemID = id; return clip
        }
        show.markers = r.markers
        show.rows = TimelineRow.normalized(r.rows)
        show.editor = r.editor
        show = try lib.saveShow(show)

        for ref in r.files.values {
            guard let id = ids[ref.path], imported.contains(id),
                  let info = ref.libraryHash.flatMap({ r.fileInfo[$0] }) else { continue }
            if info.rating > 0 { try lib.setRating(info.rating, for: [id]) }
            if !info.tags.isEmpty { try lib.setTags(info.tags, for: id) }
        }
        let used = Set(ids.values)
        if let collectionID { try lib.addItems(Array(used).sorted(), toCollection: collectionID) }
        return Result(show: show, reused: used.subtracting(imported).count, problems: problems)
    }
}

