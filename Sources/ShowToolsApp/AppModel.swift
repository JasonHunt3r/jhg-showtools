import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore

enum SidebarItem: Hashable {
    case library
    case collection(Int64)
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
    /// Library → Collection → Show (plan, 2b).
    private(set) var collections: [MediaCollection] = []

    var sidebar: SidebarItem? = .library
    /// Developer hook only: a slide for the show view to select on appearing.
    var devSelection: Int64?
    /// The Info panel's targets: kept here, not in the grid's own state,
    /// because the panel is a separate window and needs to live-update as
    /// the grid's selection changes while it's open.
    var infoPanelSelection: [Int64] = []

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

    /// A private library waiting to be unlocked: the master, at launch.
    private(set) var locked: Library?
    /// Open Recent, newest first. Private libraries never appear here.
    private(set) var recentLibraries: [URL] = []
    /// Whether the open library is private (kept here so views update).
    private(set) var libraryIsPrivate = false
    /// Bumped every time a library is loaded. Show and file ids restart at
    /// 1 in every library, so an undo step recorded in one would land on
    /// whatever has the same id in the next: undo steps check this, and the
    /// window clears its undo history when it changes.
    private(set) var libraryGeneration = 0
    private static let recentKey = "recentLibraries"

    /// The app always starts on the master library (plan, 2b). If the master
    /// is private, it waits, locked, for Unlock rather than asking before
    /// there's even a window.
    init() {
        recentLibraries = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let problem = LibraryLocation.testLaunchProblem() {
            loadError = problem
            return
        }
        if let scratch = ProcessInfo.processInfo.environment["SHOWTOOLS_LIBRARY"], !scratch.isEmpty {
            Self.noteTestLaunch(library: scratch)
        } else if let problem = TestLaunchRecord().crashRelaunchProblem() {
            loadError = problem
            return
        }
        do {
            let lib = try Library(root: masterURL)
            Self.removeLeftoverStaging(in: lib.root)
            if lib.isPrivate { locked = lib } else { load(lib) }
        } catch {
            loadError = "\(error)"
        }
    }

    /// A test launch notes itself (see `TestLaunchRecord`) and removes the
    /// note when it quits: normally, or by SIGTERM (`kill`, how Claude closes
    /// its test copies). Only a crash leaves the note.
    private static var sigterm: DispatchSourceSignal?
    private static func noteTestLaunch(library: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        TestLaunchRecord().begin(pid: pid, library: library)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in TestLaunchRecord().end(pid: pid) }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { TestLaunchRecord().end(pid: pid); exit(0) }
        source.resume()
        sigterm = source
    }

    /// The master library's folder (under either name, as Spotlight's
    /// setting leaves it).
    var masterURL: URL { LibraryLocation.resolve() }

    var isOnMaster: Bool {
        library?.root.standardizedFileURL == masterURL.standardizedFileURL
    }

    var libraryName: String { library?.name ?? locked?.name ?? "Library" }

    /// Opens another library in place of this one. A private one asks for
    /// Touch ID or the password first; if that fails, nothing changes.
    func openLibrary(at url: URL) async {
        let lib: Library
        do {
            lib = try Library(root: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open that library."
            alert.informativeText = "\(error)"
            alert.runModal()
            return
        }
        if lib.isPrivate, !(await DeviceOwner.confirm("open the private library “\(lib.name)”")) { return }
        switchTo(lib)
    }

    /// Open Recent: only a library that's still there. Opening a path
    /// creates a library at it, so a deleted or moved one would otherwise
    /// come back empty; instead it says so and leaves the menu.
    func openRecent(_ url: URL) async {
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Library.sqlite").path) else {
            forgetRecent(url)
            let alert = NSAlert()
            alert.messageText = "“\(url.deletingPathExtension().lastPathComponent)” isn't there any more."
            alert.informativeText = "It may have been moved, renamed or deleted: \(url.path). "
                + "It's been taken off Open Recent. Use File ▸ Open Library… to find it."
            alert.runModal()
            return
        }
        await openLibrary(at: url)
    }

    func unlock() async {
        guard let lib = locked, await DeviceOwner.confirm("open the private library “\(lib.name)”") else { return }
        switchTo(lib)
    }

    /// Turning privacy on needs nothing; turning it off asks.
    func setPrivate(_ on: Bool) async {
        guard let lib = library, on != libraryIsPrivate else { return }
        if !on, !(await DeviceOwner.confirm("stop “\(lib.name)” being private")) { return }
        do {
            try lib.setPrivate(on)
            libraryIsPrivate = on
            if on { forgetRecent(lib.root) } else if !isOnMaster { remember(lib.root) }
        } catch {
            loadError = "\(error)"
        }
    }

    func clearRecentLibraries() {
        recentLibraries = []
        UserDefaults.standard.set([String](), forKey: Self.recentKey)
    }

    /// Everything from the old library goes: player windows, and the
    /// thumbnail cache (its numbers only mean anything within one library).
    private func switchTo(_ lib: Library) {
        Player.closeAll()
        Thumbnails.shared.clear()
        sidebar = .library
        // Not when reopening the library that's open: an import into it may
        // be staging right now.
        if library?.root.standardizedFileURL != lib.root.standardizedFileURL {
            Self.removeLeftoverStaging(in: lib.root)
        }
        library = nil
        locked = nil
        load(lib)
        if !lib.isPrivate, !isOnMaster { remember(lib.root) }
    }

    private func remember(_ url: URL) {
        recentLibraries.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentLibraries.insert(url, at: 0)
        recentLibraries = Array(recentLibraries.prefix(10))
        UserDefaults.standard.set(recentLibraries.map(\.path), forKey: Self.recentKey)
    }

    private func forgetRecent(_ url: URL) {
        recentLibraries.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recentLibraries.map(\.path), forKey: Self.recentKey)
    }

    private func open(at url: URL) {
        do {
            load(try Library(root: url))
        } catch {
            library = nil
            loadError = "\(error)"
        }
    }

    private func load(_ lib: Library) {
        libraryGeneration += 1
        do {
            library = lib
            libraryIsPrivate = lib.isPrivate
            items = try lib.allItems()
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            shows = try lib.allShows()
            collections = try lib.allCollections()
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
        // The open library's own folder, renamed in place. (It used to build
        // the master's path, which would have moved an alternate library
        // into the master's place.)
        let to = indexed ? from.deletingPathExtension() : from.appendingPathExtension("noindex")
        library = nil      // closes the database before the move
        do {
            try FileManager.default.moveItem(at: from, to: to)
            // Open Recent follows the folder to its new name.
            if let i = recentLibraries.firstIndex(where: { $0.standardizedFileURL == from.standardizedFileURL }) {
                recentLibraries[i] = to
                UserDefaults.standard.set(recentLibraries.map(\.path), forKey: Self.recentKey)
            }
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
    ///
    /// Imports run one at a time, in the order they were asked for: one that
    /// arrives while another is running waits its turn rather than being
    /// dropped (or running alongside it and copying the same file twice).
    @discardableResult
    func importFiles(_ urls: [URL]) async -> [Int64] {
        guard let lib = library else { return [] }
        let previous = importQueue
        let this = Task { @MainActor in
            _ = await previous?.value
            return await self.runImport(urls, into: lib)
        }
        importQueue = this
        return await this.value
    }

    /// The import running or last run; the next one waits for it.
    private var importQueue: Task<[Int64], Never>?

    /// Into the library that was open when it was asked for; nothing, if
    /// that library has been closed since (its callers would otherwise add
    /// the ids to another library's collection or show).
    private func runImport(_ urls: [URL], into lib: Library) async -> [Int64] {
        guard library === lib else { return [] }
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
                    let item: MediaItem
                    do {
                        item = try lib.insertItem(relativePath: copied.relativePath, hash: hash,
                                                  probe: copied.probe, sourcePath: file.path)
                    } catch {
                        // No row, so nothing would ever find the copy: take it back out.
                        try? FileManager.default.removeItem(at: media.appendingPathComponent(copied.relativePath))
                        throw error
                    }
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
        return library === lib ? ids : []
    }

    /// Drops can carry file URLs (Finder) or file promises (Photos). Both end
    /// up as files on disk to import; promised files land in a temporary
    /// folder first and are deleted after they're copied in.
    func importProviders(_ providers: [NSItemProvider]) async -> [Int64] {
        // Staged inside the library's own folder, so copies from Photos never
        // pass through the system's temporary folder (matters for a private
        // library). Removed when the import is done.
        let staging = (library?.root ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(".staging-\(UUID().uuidString)")
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

    /// A new show in `collectionID`, or, if none is given, in the collection
    /// selected in the sidebar (or holding the selected show), or the first.
    func newShow(name: String? = nil, itemIDs: [Int64] = [], in collectionID: Int64? = nil) {
        guard let lib = library else { return }
        let n = name ?? nextShowName()
        do {
            let show = try lib.createShow(name: n, collectionID: collectionID ?? currentCollectionID,
                                          itemIDs: itemIDs)
            shows.append(show)
            collections = try lib.allCollections()
            sidebar = .show(show.id)
        } catch {
            loadError = "\(error)"
        }
    }

    /// The collection the sidebar is in: the selected one, or the selected
    /// show's; otherwise the first.
    var currentCollectionID: Int64? {
        switch sidebar {
        case .collection(let id): id
        case .show(let id): show(id)?.collectionID ?? collections.first?.id
        default: collections.first?.id
        }
    }

    func collection(_ id: Int64) -> MediaCollection? { collections.first { $0.id == id } }

    func newCollection(itemIDs: [Int64] = []) {
        guard let lib = library else { return }
        do {
            let c = try lib.createCollection(name: nextName("Untitled Collection", taken: collections.map(\.name)))
            if !itemIDs.isEmpty { try lib.addItems(itemIDs, toCollection: c.id) }
            collections = try lib.allCollections()
            sidebar = .collection(c.id)
        } catch {
            loadError = "\(error)"
        }
    }

    func renameCollection(_ id: Int64, to name: String) {
        guard let lib = library, !name.isEmpty else { return }
        do {
            try lib.renameCollection(id: id, to: name)
            collections = try lib.allCollections()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Its shows go with it; the files stay in the library.
    func deleteCollection(_ id: Int64) {
        guard let lib = library else { return }
        do {
            try lib.deleteCollection(id: id)
            collections = try lib.allCollections()
            shows = try lib.allShows()
            switch sidebar {
            case .collection(id): sidebar = .library
            case .show(let s) where show(s) == nil: sidebar = .library
            default: break
            }
        } catch {
            loadError = "\(error)"
        }
    }

    func removeFromCollection(_ itemIDs: [Int64], _ collectionID: Int64) {
        guard let lib = library else { return }
        do {
            try lib.removeItems(itemIDs, fromCollection: collectionID)
            collections = try lib.allCollections()
        } catch {
            loadError = "\(error)"
        }
    }

    func renameShow(_ id: Int64, to name: String, undo: UndoManager? = nil) {
        guard var s = show(id), !name.isEmpty else { return }
        s.name = name
        update(s, undo: undo, action: "Rename Show")
    }

    private func nextName(_ base: String, taken: [String]) -> String {
        let names = Set(taken)
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func nextShowName() -> String {
        let names = Set(shows.map(\.name))
        if !names.contains("Untitled Show") { return "Untitled Show" }
        var n = 2
        while names.contains("Untitled Show \(n)") { n += 1 }
        return "Untitled Show \(n)"
    }

    /// Saves a changed show. New slides come back with their ids.
    ///
    /// With an undo manager, the version being replaced is registered as the
    /// undo step (and undoing registers the redo). Restoring a snapshot puts
    /// removed slides back with their original ids and settings.
    func update(_ show: Show, undo: UndoManager? = nil, action: String? = nil) {
        guard let lib = library, let i = shows.firstIndex(where: { $0.id == show.id }) else { return }
        let before = shows[i]
        guard before != show else { return }
        do {
            shows[i] = try lib.saveShow(show)
        } catch {
            loadError = "\(error)"
            return
        }
        if let undo {
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.update(before, undo: undo, action: action)
                }
            }
            if let action { undo.setActionName(action) }
        }
    }

    func append(_ itemIDs: [Int64], to showID: Int64, undo: UndoManager? = nil) {
        guard var show = show(showID), !itemIDs.isEmpty,
              bringIntoCollection(itemIDs, forShow: showID) else { return }
        show.slides += itemIDs.map { Slide(id: 0, itemID: $0) }
        update(show, undo: undo, action: "Add Slides")
    }

    /// Files about to go into a show must be in its collection. Any that
    /// aren't are added, after asking (unless the preference says always).
    /// False if the answer was Cancel: the caller then adds nothing.
    func bringIntoCollection(_ itemIDs: [Int64], forShow showID: Int64) -> Bool {
        guard let cid = show(showID)?.collectionID, let c = collection(cid) else { return true }
        let have = Set(c.itemIDs)
        let missing = itemIDs.filter { !have.contains($0) }
        guard !missing.isEmpty else { return true }
        let first = itemsByID[missing[0]]?.fileName ?? "This file"
        guard CollectionAddNotice.confirm(count: Set(missing).count, firstName: first, collection: c.name)
        else { return false }
        addToCollection(missing, cid)
        return true
    }

    /// Files dropped on a show: ours from the Collection Browser as they
    /// are; anything from Finder or Photos imported first (both, if a drop
    /// somehow carries both).
    func itemIDs(from providers: [NSItemProvider]) async -> [Int64] {
        let isOurs = { (p: NSItemProvider) in p.hasItemConformingToTypeIdentifier(ItemDrag.type.identifier) }
        let theirs = providers.filter { !isOurs($0) }
        var ids = await ItemDrag.ids(from: providers.filter(isOurs)) ?? []
        if !theirs.isEmpty { ids += await importProviders(theirs) }
        return ids
    }

    /// `.staging-…` folders are only ever temporary (see `importProviders`):
    /// any found when a library opens were left by a crash mid-import, with
    /// copies of Photos originals in them. Only for a library that isn't
    /// already open: an import runs into the open library, so none can be
    /// staging in any other.
    private static func removeLeftoverStaging(in root: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.hasPrefix(".staging-") {
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
    }

    func addToCollection(_ itemIDs: [Int64], _ collectionID: Int64) {
        guard let lib = library else { return }
        do {
            try lib.addItems(itemIDs, toCollection: collectionID)
            collections = try lib.allCollections()
        } catch {
            loadError = "\(error)"
        }
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

    /// Star ratings belong to files, so this isn't a show edit; it has its
    /// own undo, which puts each file's previous rating back.
    func setRating(_ rating: Int, for itemIDs: Set<Int64>, undo: UndoManager?) {
        let r = min(max(rating, 0), 5)
        applyRatings(itemIDs.map { ($0, r) }, undo: undo)
    }

    private func applyRatings(_ changes: [(Int64, Int)], undo: UndoManager?) {
        guard let lib = library else { return }
        let before = changes.map { ($0.0, itemsByID[$0.0]?.rating ?? 0) }
        do {
            for (id, r) in changes { try lib.setRating(r, for: [id]) }
        } catch {
            loadError = "\(error)"
            return
        }
        for (id, r) in changes {
            itemsByID[id]?.rating = r
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].rating = r }
        }
        let generation = libraryGeneration
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.applyRatings(before, undo: undo)
            }
        }
        undo?.setActionName("Rate")
    }

    /// Sets each file's exact tag list (the Info panel works out the
    /// add/remove per file for tagging several at once). Belongs to the
    /// file, not a show, like rating — same symmetric undo.
    func setTags(_ changes: [Int64: [String]], undo: UndoManager?) {
        applyTags(changes, undo: undo)
    }

    private func applyTags(_ changes: [Int64: [String]], undo: UndoManager?) {
        guard let lib = library, !changes.isEmpty else { return }
        let before = Dictionary(uniqueKeysWithValues: changes.keys.map { ($0, itemsByID[$0]?.tags ?? []) })
        do {
            for (id, tags) in changes { try lib.setTags(tags, for: id) }
        } catch {
            loadError = "\(error)"
            return
        }
        for (id, tags) in changes {
            itemsByID[id]?.tags = tags
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].tags = tags }
        }
        if FinderTagsSetting.isOn {
            for (id, tags) in changes {
                guard let item = itemsByID[id], let url = url(for: item) else { continue }
                // The URLResourceValues.tagNames *setter* is unavailable at
                // our deployment target on this SDK; NSURL's older API sets
                // the same Finder tags without that restriction.
                try? (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
            }
        }
        let generation = libraryGeneration
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.applyTags(before, undo: undo)
            }
        }
        undo?.setActionName(changes.count == 1 ? "Set Tags" : "Set Tags on \(changes.count) Items")
    }

    /// Batch rename (2b): Finder's Rename Items sheet computes each new
    /// name (`BatchRename`); this applies them. Symmetric, like
    /// `deleteItems` — calling it again with what it hands back is both
    /// undo and (from there) redo.
    func renameItems(_ names: [Int64: String], undo: UndoManager?) {
        guard let lib = library, !names.isEmpty else { return }
        let previous: [Int64: String]
        do {
            previous = try lib.renameItems(names)
        } catch {
            loadError = "\(error)"
            return
        }
        guard !previous.isEmpty else { return }
        items = (try? lib.allItems()) ?? items
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let generation = libraryGeneration
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.renameItems(previous, undo: undo)
            }
        }
        undo?.setActionName(previous.count == 1 ? "Rename" : "Rename \(previous.count) Items")
    }

    /// Shows that use any of these files, in a slide or in the lane's
    /// images row — for the Delete prompt (and later, the Info panel).
    func showsUsing(_ itemIDs: Set<Int64>) -> [Show] {
        shows.filter { show in
            show.slides.contains { itemIDs.contains($0.itemID) }
                || show.overlays.contains { itemIDs.contains($0.itemID) }
        }
    }

    /// Library delete, the Photos convention: Delete asks first (naming how
    /// many shows use the file(s)); ⌘Delete skips the prompt (both in
    /// `LibraryGridView`). Either way the file goes to the macOS Trash, its
    /// library entry goes, and every slide (and lane image) using it is
    /// removed from every show that had it. ⌘Z undoes it while the file is
    /// still in the Trash.
    func deleteItems(_ itemIDs: [Int64], undo: UndoManager?) {
        guard let lib = library, !itemIDs.isEmpty else { return }
        let idSet = Set(itemIDs)

        // The lane's images aren't in the `slides` table (deleteItems below
        // only cleans that up), so they're stripped here, one show save
        // each, same as any other show edit — captured first, so undo can
        // put them back.
        var strippedOverlays: [Int64: [OverlayClip]] = [:]
        for show in shows where show.overlays.contains(where: { idSet.contains($0.itemID) }) {
            var s = show
            strippedOverlays[s.id] = s.overlays.filter { idSet.contains($0.itemID) }
            s.overlays.removeAll { idSet.contains($0.itemID) }
            do { s = try lib.saveShow(s) } catch { loadError = "\(error)"; return }
            if let i = shows.firstIndex(where: { $0.id == s.id }) { shows[i] = s }
        }

        var trashedURLs: [Int64: URL] = [:]
        for id in itemIDs {
            guard let item = itemsByID[id] else { continue }
            var placed: NSURL?
            if (try? FileManager.default.trashItem(at: lib.url(for: item), resultingItemURL: &placed)) != nil,
               let url = placed as URL? {
                trashedURLs[id] = url
            }
        }

        let deleted: [Library.DeletedItem]
        do {
            deleted = try lib.deleteItems(itemIDs)
        } catch {
            loadError = "\(error)"
            return
        }
        items.removeAll { idSet.contains($0.id) }
        for id in itemIDs { itemsByID[id] = nil }
        shows = (try? lib.allShows()) ?? shows
        collections = (try? lib.allCollections()) ?? collections

        let generation = libraryGeneration
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.restoreDeletedItems(deleted, overlays: strippedOverlays, trashedURLs: trashedURLs, undo: undo)
            }
        }
        undo?.setActionName(itemIDs.count == 1 ? "Delete Item" : "Delete Items")
    }

    /// `deleteItems`'s undo: the file back from the Trash, the database rows
    /// back with their original ids, and the lane images put back in each
    /// show's overlays. Registers a redo the same way `update` does — which,
    /// calling `deleteItems` again, re-derives what to strip from `shows` as
    /// it now stands, rather than needing it passed back in.
    private func restoreDeletedItems(_ deleted: [Library.DeletedItem], overlays: [Int64: [OverlayClip]],
                                     trashedURLs: [Int64: URL], undo: UndoManager?) {
        guard let lib = library else { return }
        for d in deleted {
            guard let trashed = trashedURLs[d.item.id] else { continue }
            let original = lib.url(for: d.item)
            try? FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: trashed, to: original)
        }
        do {
            try lib.restoreItems(deleted)
        } catch {
            loadError = "\(error)"
            return
        }
        items = (try? lib.allItems()) ?? items
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        shows = (try? lib.allShows()) ?? shows
        for (showID, clips) in overlays {
            guard var s = shows.first(where: { $0.id == showID }), !clips.isEmpty else { continue }
            s.overlays += clips
            do {
                s = try lib.saveShow(s)
                if let i = shows.firstIndex(where: { $0.id == showID }) { shows[i] = s }
            } catch { loadError = "\(error)" }
        }
        collections = (try? lib.allCollections()) ?? collections

        let generation = libraryGeneration
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.deleteItems(deleted.map(\.item.id), undo: undo)
            }
        }
        undo?.setActionName(deleted.count == 1 ? "Delete Item" : "Delete Items")
    }

    func timeline(for show: Show) -> ShowTimeline {
        ShowTimeline(show: show, items: itemsByID)
    }
}
