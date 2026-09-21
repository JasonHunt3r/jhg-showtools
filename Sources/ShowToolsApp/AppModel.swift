import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore

enum SidebarItem: Hashable {
    case library
    case show(Int64)
}

/// Everything the windows share: the open library, its items and shows,
/// and import progress. Main actor only; heavy file work is sent elsewhere.
@MainActor
@Observable
final class AppModel {
    private(set) var library: Library?
    private(set) var loadError: String?

    private(set) var items: [MediaItem] = []
    private(set) var itemsByID: [Int64: MediaItem] = [:]
    var shows: [Show] = []

    var sidebar: SidebarItem? = .library

    struct ImportStatus {
        var total = 0
        var done = 0
        var added = 0
        var duplicates = 0
        var failures: [(String, String)] = []
        var finished = false

        var summary: String {
            var parts = ["\(added) added"]
            if duplicates > 0 { parts.append("\(duplicates) already in library") }
            if !failures.isEmpty { parts.append("\(failures.count) failed") }
            return parts.joined(separator: " · ")
        }
    }
    var importStatus: ImportStatus?

    init() {
        open(at: LibraryLocation.resolve())
    }

    private func open(at url: URL) {
        do {
            let lib = try Library(root: url)
            library = lib
            items = try lib.allItems()
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            shows = try lib.allShows()
            loadError = nil
        } catch {
            library = nil
            loadError = "\(error)"
        }
    }

    func url(for item: MediaItem) -> URL? { library?.url(for: item) }

    func show(_ id: Int64) -> Show? { shows.first { $0.id == id } }

    // MARK: Spotlight

    var libraryHiddenFromSpotlight: Bool { library?.isHidden ?? true }

    /// Renames the library folder in or out of `.noindex`.
    func setSpotlightIndexing(_ indexed: Bool) {
        guard let lib = library, lib.isHidden == indexed else { return }
        let from = lib.root
        let to = indexed ? LibraryLocation.visibleURL : LibraryLocation.hiddenURL
        library = nil      // closes the database before the move
        do {
            try FileManager.default.moveItem(at: from, to: to)
            open(at: to)
        } catch {
            open(at: from)
            loadError = "Couldn't rename the library folder: \(error.localizedDescription)"
        }
    }

    // MARK: Import

    /// Imports files and folders. Returns the library item for every file,
    /// including ones that were already in the library, in order — so a drop
    /// onto a show can append exactly what was dropped.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> [Int64] {
        guard let lib = library, importStatus == nil || importStatus?.finished == true else { return [] }
        let files = await Task.detached { Ingest.collect(urls) }.value
        importStatus = ImportStatus(total: files.count)
        var ids: [Int64] = []

        for file in files {
            do {
                let hash = try await Task.detached { try Ingest.sha256(of: file) }.value
                if let existing = try lib.itemID(forHash: hash) {
                    importStatus?.duplicates += 1
                    ids.append(existing)
                } else {
                    let media = lib.mediaURL
                    let copied = try await Task.detached {
                        try await Ingest.copyIn(file, expectedHash: hash, mediaDir: media)
                    }.value
                    let item = try lib.insertItem(relativePath: copied.relativePath, hash: hash,
                                                  probe: copied.probe, sourcePath: file.path)
                    items.append(item)
                    itemsByID[item.id] = item
                    importStatus?.added += 1
                    ids.append(item.id)
                }
            } catch {
                importStatus?.failures.append((file.lastPathComponent, "\(error)"))
            }
            importStatus?.done += 1
        }
        importStatus?.finished = true
        return ids
    }

    /// Drops can carry file URLs (Finder) or file promises (Photos). Both end
    /// up as files on disk to import; promised files land in a temporary
    /// folder first and are deleted after they're copied in.
    func importProviders(_ providers: [NSItemProvider]) async -> [Int64] {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShowTools-drop-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var urls: [URL] = []
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadFileURL(p) {
                urls.append(url)
                continue
            }
            for type in [UTType.movie, .image] where p.hasItemConformingToTypeIdentifier(type.identifier) {
                if let url = await loadFileCopy(p, type: type, into: staging) { urls.append(url) }
                break
            }
        }
        return await importFiles(urls)
    }

    private func loadFileURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = p.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }

    private func loadFileCopy(_ p: NSItemProvider, type: UTType, into dir: URL) async -> URL? {
        let name = p.suggestedName
        return await withCheckedContinuation { cont in
            _ = p.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                // The provided file is deleted when this block returns: copy it now.
                guard let url else { return cont.resume(returning: nil) }
                var fileName = url.lastPathComponent
                if let name, !name.isEmpty {
                    fileName = (name as NSString).pathExtension.isEmpty
                        ? name + "." + url.pathExtension : name
                }
                let dest = dir.appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent(fileName)
                do {
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Shows

    func newShow(name: String? = nil, itemIDs: [Int64] = []) {
        guard let lib = library else { return }
        let n = name ?? nextShowName()
        do {
            let show = try lib.createShow(name: n, itemIDs: itemIDs)
            shows.append(show)
            sidebar = .show(show.id)
        } catch {
            loadError = "\(error)"
        }
    }

    private func nextShowName() -> String {
        let names = Set(shows.map(\.name))
        if !names.contains("Untitled Show") { return "Untitled Show" }
        var n = 2
        while names.contains("Untitled Show \(n)") { n += 1 }
        return "Untitled Show \(n)"
    }

    /// Saves a changed show. New slides come back with their ids.
    func update(_ show: Show) {
        guard let lib = library, let i = shows.firstIndex(where: { $0.id == show.id }) else { return }
        do {
            shows[i] = try lib.saveShow(show)
        } catch {
            loadError = "\(error)"
        }
    }

    func append(_ itemIDs: [Int64], to showID: Int64) {
        guard var show = show(showID) else { return }
        show.slides += itemIDs.map { Slide(id: 0, itemID: $0) }
        update(show)
    }

    func deleteShow(_ id: Int64) {
        guard let lib = library else { return }
        do {
            try lib.deleteShow(id: id)
            shows.removeAll { $0.id == id }
            if sidebar == .show(id) { sidebar = .library }
        } catch {
            loadError = "\(error)"
        }
    }

    func timeline(for show: Show) -> ShowTimeline {
        ShowTimeline(show: show, items: itemsByID)
    }
}
