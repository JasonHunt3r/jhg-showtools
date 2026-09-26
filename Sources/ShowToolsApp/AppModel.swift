import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore
import ShowToolsPlayback
import PaneKit

enum SidebarItem: Hashable {
    case library
    case collection(Int64)
    case group(Int64)
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
    /// Sub-folders of a collection's files (plan, "Groups inside collections").
    private(set) var groups: [MediaGroup] = []
    /// Named rhythm patterns saved in the library (plan, Phase 3 step 7).
    private(set) var rhythmPatterns: [SavedRhythm] = []

    var sidebar: SidebarItem? = .library
    /// The main window's layout (`spec/panekit.md`, step 2, and the
    /// timeline pane's own move, step 5's follow-up, 2026-09-25): the
    /// Library pane beside the detail, with the timeline pane full width
    /// underneath both — `panekit.md`'s own original sketch
    /// (`split(top/bottom) { split(left|rest) { library, detail }, timeline }`),
    /// not nested inside Edit Show's own columns as first built (which
    /// only ever gave it the detail pane's width, not the window's).
    /// `MainView` renders "storyline" itself, reading the same
    /// `ShowSession`/`AppModel` state `EditShowView` does, rather than
    /// `EditShowView` handing it a built view — writing to `@Observable`
    /// state from one view's `body` for another view to read in the same
    /// update pass is the same class of trap SwiftUI's "don't mutate
    /// state during a view update" rule exists for. One controller for
    /// the window's lifetime, so `MainView` and the View menu's commands
    /// share it. **The inner split keeps the id `"main"`**, unchanged
    /// since step 2, so Jason's already-saved sidebar width keeps meaning
    /// what it always meant; the new outer split is `"window"`, a name
    /// nothing has used before.
    let mainPanes = PaneController(id: "main", root:
        .split("window", .vertical, sized: .second,
               size: StorylineView.fullHeight + 56 + 10,
               range: (StorylineView.fullHeight + 56)...(StorylineView.fullHeight + 456),
               // Item 15, `ShowTools Feedback — Worklist for Next CC
               // Session.md`: 180 read too wide as a floor. 140 still
               // shows an icon, a truncated name and the count badge on
               // the narrowest real row ("Untitled Collection").
               .split("main", .horizontal, sized: .first, size: DefaultLayout.sidebarWidth,
                      range: 140...360, title: "Library",
                      .pane("library", title: "Library", minSize: 140),
                      .pane("detail", title: "Detail", minSize: 240)),
               .pane("storyline", title: "Timeline", minSize: StorylineView.fullHeight + 56, popOut: .window)))
    /// Edit Show's and Edit Slides' columns (`spec/panekit.md`, step 3): one
    /// controller each, shared across every show (`ColumnsSplitView`'s own
    /// saved widths were shared the same way), so switching shows doesn't
    /// churn the layout. The timeline pane isn't part of this tree any
    /// more (above) — `EditColumnsLayout.threeColumns` is just the three
    /// columns now.
    let editShowColumns = PaneController(id: "EditShowColumns", root: EditColumnsLayout.threeColumns)
    let editSlidesColumns = PaneController(id: "EditSlidesColumns", root: EditColumnsLayout.twoColumns)
    /// Edit Show's picture and the frame strip under it: a drawer since
    /// 2026-09-25 (item 30, Jason), replacing a hand-made bar whose strip
    /// had a fixed floor and vanished entirely when hidden. Its starting
    /// height is the old bar's saved one (`frameStripHeight`), so the first
    /// launch looks the same.
    let previewPanes = PaneController(id: "EditShowPreview",
                                      root: PreviewLayout.tree(defaultStrip: PreviewLayout.savedStripHeight))
    /// The open show's editing state (`spec/windows.md`, `ShowSession`).
    /// One at a time: this app edits one show in the main window.
    private(set) var showSession: ShowSession?
    /// Developer hook only: a slide for the show view to select on appearing.
    var devSelection: Int64?
    /// Edit Show's transport/timeline commands, for the Show and View
    /// menus (`ShowToolsApp.swift`'s `AppCommands`). Was
    /// `@FocusedValue`/`.focusedSceneValue` until 2026-09-25: that's
    /// scoped to SwiftUI's own `Scene` graph, so it never reached the
    /// menus while the Timeline pane's popped-out window was key
    /// (`spec/panekit.md`, "The order," step 5) — a plain stored property
    /// here is reachable regardless of which window is key, matching
    /// `UndoMenuState`'s fix for Undo/Redo. `EditShowView` sets and
    /// clears it; absent outside Edit Show, same as before.
    var editShowCommands: EditShowCommandsValue?
    /// The Info panel's targets: kept here, not in the grid's own state,
    /// because the panel is a separate window and needs to live-update as
    /// the grid's selection changes while it's open.
    var infoPanelSelection: [Int64] = []
    /// Show in Library's target (`spec/windows.md`, "Jason's answers" 2):
    /// the library panel watches this and selects/scrolls to it. A fresh
    /// `LibraryFocusRequest` each time, even for the same item, so asking
    /// twice in a row still fires `onChange`.
    var libraryFocusRequest: LibraryFocusRequest?
    /// Set after File ▸ Relink Missing Files… runs, for MainView's alert.
    var relinkResult: RelinkSummary?

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
    /// File ▸ Export Show…'s progress and result (plan, Phase 4).
    var exportStatus: ExportStatus?
    /// File ▸ Export Movie…'s progress and result (spec/video-export.md).
    var movieExportStatus: MovieExportStatus?

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
            Waveforms.shared.cacheDir = lib.root.appendingPathComponent("Cache/Waveforms", isDirectory: true)
            Rhythms.shared.cacheDir = lib.root.appendingPathComponent("Cache/Rhythm", isDirectory: true)
            Fingerprints.shared.cacheDir = lib.root.appendingPathComponent("Cache/Prints", isDirectory: true)
            libraryIsPrivate = lib.isPrivate
            items = try lib.allItems()
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            shows = try lib.allShows()
            collections = try lib.allCollections()
            groups = try lib.allGroups()
            rhythmPatterns = try lib.allRhythmPatterns()
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
            for type in [UTType.movie, .image, .audio] where p.hasItemConformingToTypeIdentifier(type.identifier) {
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

    // MARK: Import Show (plan, Phase 4)

    /// Reads the folder off the main thread, imports the files the library
    /// lacks (through the ordinary import, with its banner), then builds the
    /// show and selects it. Anything that couldn't be read or found is
    /// listed in an alert afterwards.
    func importShow(from folder: URL, makeCollection: Bool) async {
        guard let lib = library else { return }
        var reading: SetlistImport.Reading
        do { reading = try await SetlistImport.read(folder) } catch {
            exportAlert("“\(folder.lastPathComponent)” couldn't be imported.", "\(error).")
            return
        }
        guard library === lib else { return }
        let urls: [URL]
        do { urls = try SetlistImport.filesToImport(reading, lib: lib) } catch {
            exportAlert("“\(folder.lastPathComponent)” couldn't be imported.", "\(error).")
            return
        }
        let before = Set(itemsByID.keys)
        let ids = urls.isEmpty ? [] : await importFiles(urls)
        // The library can change while files copy; the show belongs to the one asked.
        guard library === lib else { return }
        let imported = Set(ids).subtracting(before)

        reading.name = nextName(reading.name, taken: shows.map(\.name))
        let collectionID = makeCollection
            ? newCollection(named: reading.name, select: false)
            : currentCollectionID
        do {
            let result = try SetlistImport.makeShow(reading, in: lib, collectionID: collectionID, imported: imported)
            items = try lib.allItems()
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            shows = try lib.allShows()
            collections = try lib.allCollections()
            sidebar = .show(result.show.id)
            if !result.problems.isEmpty {
                let shown = result.problems.prefix(12).joined(separator: "\n")
                let more = result.problems.count > 12 ? "\n…and \(result.problems.count - 12) more." : ""
                exportAlert("“\(result.show.name)” was imported, with \(result.problems.count) problem\(result.problems.count == 1 ? "" : "s").",
                            shown + more)
            }
        } catch {
            exportAlert("“\(folder.lastPathComponent)” couldn't be imported.", "\(error).")
        }
    }

    // MARK: Show session

    /// The session for `showID`: the current one if it's already that
    /// show's, otherwise a fresh one, closing whatever was open first (its
    /// engine, if Edit Show made one). One per open show, not per view, so
    /// a window besides the main one could reach it (`spec/windows.md`).
    func session(for showID: Int64) -> ShowSession {
        if let s = showSession, s.showID == showID { return s }
        closeShowSession()
        let s = ShowSession(showID: showID)
        showSession = s
        return s
    }

    /// Shuts down the session's engine, if it made one, and clears the
    /// session. Called when the main window leaves the show entirely, not
    /// just when Edit Show's own mode does (that's `EditShowView`'s own
    /// `onDisappear`, unchanged).
    func closeShowSession() {
        if let engine = showSession?.engine {
            Player.closeWindows(for: engine)
            engine.shutdown()
        }
        showSession = nil
    }

    // MARK: Shows

    /// A new show in `collectionID`, or, if none is given, in the collection
    /// selected in the sidebar (or holding the selected show), or the first.
    func newShow(name: String? = nil, itemIDs: [Int64] = [], in collectionID: Int64? = nil) {
        guard let lib = library else { return }
        let n = name ?? nextShowName()
        do {
            let show = try lib.createShow(name: n, collectionID: collectionID ?? currentCollectionID,
                                          itemIDs: pictures(itemIDs))
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
    func group(_ id: Int64) -> MediaGroup? { groups.first { $0.id == id } }
    func groups(inCollection id: Int64) -> [MediaGroup] { groups.filter { $0.collectionID == id } }
    /// The top-level groups of a collection (`parentID` nil) — the Library
    /// pane's own siblings, alongside that collection's shows.
    func topGroups(inCollection id: Int64) -> [MediaGroup] { groups.filter { $0.collectionID == id && $0.parentID == nil } }

    /// A new collection, "Untitled Collection" unless named (a name already
    /// taken gets a number). Selected in the sidebar unless `select` is off.
    @discardableResult
    func newCollection(named name: String? = nil, itemIDs: [Int64] = [], select: Bool = true) -> Int64? {
        guard let lib = library else { return nil }
        do {
            let c = try lib.createCollection(name: nextName(name ?? "Untitled Collection", taken: collections.map(\.name)))
            if !itemIDs.isEmpty { try lib.addItems(itemIDs, toCollection: c.id) }
            collections = try lib.allCollections()
            if select { sidebar = .collection(c.id) }
            return c.id
        } catch {
            loadError = "\(error)"
            return nil
        }
    }

    func renameCollection(_ id: Int64, to name: String, undo: UndoManager? = nil) {
        guard let lib = library, !name.isEmpty,
              let before = collections.first(where: { $0.id == id })?.name, before != name else { return }
        do {
            try lib.renameCollection(id: id, to: name)
            collections = try lib.allCollections()
        } catch {
            loadError = "\(error)"
            return
        }
        guard let undo else { return }
        let generation = libraryGeneration
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.renameCollection(id, to: before, undo: undo)
            }
        }
        undo.setActionName("Rename Collection")
    }

    /// Saves a rhythm pattern by name; a name already used is replaced.
    func saveRhythmPattern(name: String, _ pattern: RhythmPattern, beatsPerQuarter: Double) {
        guard let lib = library, !name.isEmpty else { return }
        do {
            try lib.saveRhythmPattern(name: name, pattern, beatsPerQuarter: beatsPerQuarter)
            rhythmPatterns = try lib.allRhythmPatterns()
        } catch {
            loadError = "\(error)"
        }
    }

    func deleteRhythmPattern(_ id: Int64) {
        guard let lib = library else { return }
        do {
            try lib.deleteRhythmPattern(id: id)
            rhythmPatterns = try lib.allRhythmPatterns()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Its shows go with it; the files stay in the library.
    func deleteCollection(_ id: Int64, undo: UndoManager? = nil) {
        guard let lib = library else { return }
        do {
            let snap = try lib.snapshotCollection(id: id)
            try lib.deleteCollection(id: id)
            collections = try lib.allCollections()
            groups = try lib.allGroups()
            shows = try lib.allShows()
            switch sidebar {
            case .collection(id): sidebar = .library
            case .group(let g) where group(g) == nil: sidebar = .library
            case .show(let s) where show(s) == nil: sidebar = .library
            default: break
            }
            // Undo brings it back with its shows (Jason, Phase 3b).
            guard let undo, let snap else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.restoreCollection(snap, undo: undo)
                }
            }
            undo.setActionName("Delete Collection")
        } catch {
            loadError = "\(error)"
        }
    }

    private func restoreCollection(_ snap: Library.CollectionSnapshot, undo: UndoManager) {
        guard let lib = library else { return }
        do {
            try lib.restoreCollection(snap)
            collections = try lib.allCollections()
            groups = try lib.allGroups()
            shows = try lib.allShows()
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.deleteCollection(snap.id, undo: undo)
                }
            }
            undo.setActionName("Delete Collection")
        } catch {
            loadError = "\(error)"
        }
    }

    /// Takes files out of a collection; they stay in the library and in
    /// any show. Undo puts them back in their places.
    func removeFromCollection(_ itemIDs: [Int64], _ collectionID: Int64, undo: UndoManager? = nil) {
        guard let lib = library else { return }
        do {
            let removed = try lib.removeItems(itemIDs, fromCollection: collectionID)
            collections = try lib.allCollections()
            groups = try lib.allGroups()
            guard let undo, !removed.items.isEmpty else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation, let lib = model.library else { return }
                    do {
                        try lib.restoreItems(removed.items, toCollection: collectionID)
                        try lib.restoreGroupMemberships(removed.groupMemberships)
                        model.collections = try lib.allCollections()
                        model.groups = try lib.allGroups()
                    } catch {
                        model.loadError = "\(error)"
                    }
                    undo.registerUndo(withTarget: model) { model in
                        MainActor.assumeIsolated { model.removeFromCollection(removed.items.map(\.itemID), collectionID, undo: undo) }
                    }
                    undo.setActionName("Remove from Collection")
                }
            }
            undo.setActionName("Remove from Collection")
        } catch {
            loadError = "\(error)"
        }
    }

    // MARK: Groups (plan, "Groups inside collections")

    /// A new group, "Untitled Group" unless named. Its files must already
    /// be in `collectionID` — the Library enforces that. Not selected on
    /// creation (groups sit beside shows in the pane; nothing switches the
    /// detail to one yet).
    @discardableResult
    func newGroup(named name: String? = nil, collectionID: Int64, parentID: Int64? = nil,
                  itemIDs: [Int64] = []) -> Int64? {
        guard let lib = library else { return nil }
        do {
            let taken = groups.filter { $0.collectionID == collectionID && $0.parentID == parentID }.map(\.name)
            let g = try lib.createGroup(name: nextName(name ?? "Untitled Group", taken: taken),
                                         collectionID: collectionID, parentID: parentID)
            if !itemIDs.isEmpty { try lib.addItems(itemIDs, toGroup: g.id) }
            groups = try lib.allGroups()
            return g.id
        } catch {
            loadError = "\(error)"
            return nil
        }
    }

    func renameGroup(_ id: Int64, to name: String, undo: UndoManager? = nil) {
        guard let lib = library, !name.isEmpty,
              let before = group(id)?.name, before != name else { return }
        do {
            try lib.renameGroup(id: id, to: name)
            groups = try lib.allGroups()
        } catch {
            loadError = "\(error)"
            return
        }
        guard let undo else { return }
        let generation = libraryGeneration
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.renameGroup(id, to: before, undo: undo)
            }
        }
        undo.setActionName("Rename Group")
    }

    /// Nests a group inside another, or (nil) back to the top — groups hold
    /// groups, like folders. Both stay in the same collection. Silently
    /// does nothing if the move is refused (a cycle, or a different
    /// collection): the UI should already have ruled those out before
    /// offering the drop, so this is a last-resort guard, not feedback.
    func moveGroup(_ id: Int64, toParent newParentID: Int64?, undo: UndoManager? = nil) {
        guard let lib = library, let g = group(id) else { return }
        let before = g.parentID
        guard before != newParentID else { return }
        do {
            try lib.moveGroup(id: id, toParent: newParentID)
            groups = try lib.allGroups()
        } catch {
            return
        }
        guard let undo else { return }
        let generation = libraryGeneration
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.moveGroup(id, toParent: before, undo: undo)
            }
        }
        undo.setActionName("Move Group")
    }

    /// Its sub-groups go with it, as in Finder; the files stay in the
    /// collection.
    func deleteGroup(_ id: Int64, undo: UndoManager? = nil) {
        guard let lib = library else { return }
        do {
            let snap = try lib.snapshotGroupSubtree(id: id)
            try lib.deleteGroup(id: id)
            groups = try lib.allGroups()
            if case .group(let g) = sidebar, snap.contains(where: { $0.id == g }) { sidebar = .library }
            guard let undo, !snap.isEmpty else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.restoreGroupSubtree(snap, undo: undo)
                }
            }
            undo.setActionName("Delete Group")
        } catch {
            loadError = "\(error)"
        }
    }

    private func restoreGroupSubtree(_ snap: [Library.GroupSnapshot], undo: UndoManager) {
        guard let lib = library else { return }
        do {
            try lib.restoreGroupSubtree(snap)
            groups = try lib.allGroups()
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.deleteGroup(snap[0].id, undo: undo)
                }
            }
            undo.setActionName("Delete Group")
        } catch {
            loadError = "\(error)"
        }
    }

    /// Only files already in the group's own collection are added; the
    /// Library silently leaves out the rest (the membership rule).
    func addToGroup(_ itemIDs: [Int64], _ groupID: Int64) {
        guard let lib = library else { return }
        do {
            try lib.addItems(itemIDs, toGroup: groupID)
            groups = try lib.allGroups()
        } catch {
            loadError = "\(error)"
        }
    }

    /// The group version of `setOrder(_:inCollection:undo:)`.
    func setOrder(_ itemIDs: [Int64], inGroup groupID: Int64, undo: UndoManager? = nil) {
        guard let lib = library, let before = group(groupID)?.itemIDs, before != itemIDs else { return }
        do {
            try lib.setOrder(itemIDs, inGroup: groupID)
            groups = try lib.allGroups()
        } catch {
            loadError = "\(error)"
            return
        }
        guard let undo else { return }
        let generation = libraryGeneration
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.setOrder(before, inGroup: groupID, undo: undo)
            }
        }
        undo.setActionName("Reorder")
    }

    /// Takes files out of a group; they stay in the collection. Undo puts
    /// them back in their places.
    func removeFromGroup(_ itemIDs: [Int64], _ groupID: Int64, undo: UndoManager? = nil) {
        guard let lib = library else { return }
        do {
            let removed = try lib.removeItems(itemIDs, fromGroup: groupID)
            groups = try lib.allGroups()
            guard let undo, !removed.isEmpty else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation, let lib = model.library else { return }
                    do {
                        try lib.restoreItems(removed, toGroup: groupID)
                        model.groups = try lib.allGroups()
                    } catch {
                        model.loadError = "\(error)"
                    }
                    undo.registerUndo(withTarget: model) { model in
                        MainActor.assumeIsolated { model.removeFromGroup(removed.map(\.itemID), groupID, undo: undo) }
                    }
                    undo.setActionName("Remove from Group")
                }
            }
            undo.setActionName("Remove from Group")
        } catch {
            loadError = "\(error)"
        }
    }

    func renameShow(_ id: Int64, to name: String, undo: UndoManager? = nil) {
        guard var s = show(id), !name.isEmpty else { return }
        s.name = name
        update(s, undo: undo, action: "Rename Show")
    }

    func nextName(_ base: String, taken: [String]) -> String {
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
                    // Most of the editing state (loop, lines, which lock,
                    // the browser filter) isn't an edit: undo keeps it as it
                    // is now. The range's own points are the exception
                    // (W6, work order item 6): a drag, I/O or the range
                    // button is a deliberate edit, so ⌘Z should put them
                    // back like any other change.
                    var restore = before
                    if let now = model.show(before.id) {
                        var editor = now.editor
                        editor.rangeIn = restore.editor.rangeIn
                        editor.rangeOut = restore.editor.rangeOut
                        restore.editor = editor
                    }
                    model.update(restore, undo: undo, action: action)
                }
            }
            if let action { undo.setActionName(action) }
        }
    }

    /// Changes a show's editing state (range, loop, lines) and saves it,
    /// with no undo step (plan, Phase 3).
    func updateEditor(_ showID: Int64, _ change: (inout ShowEditorState) -> Void) {
        guard var s = show(showID) else { return }
        change(&s.editor)
        update(s)
    }

    /// The ones that can be slides or lane images: songs can't.
    func pictures(_ itemIDs: [Int64]) -> [Int64] {
        itemIDs.filter { itemsByID[$0]?.kind.isPicture ?? false }
    }

    /// The songs among them, for the music row.
    func songs(_ itemIDs: [Int64]) -> [Int64] {
        itemIDs.filter { itemsByID[$0]?.kind == .audio }
    }

    /// `undo` has no default on purpose: every show edit is one undo step,
    /// and a default of nil once left three ways of adding slides undoable
    /// by nothing (spec/hig-audit.md, G1).
    func append(_ itemIDs: [Int64], to showID: Int64, undo: UndoManager?) {
        let itemIDs = pictures(itemIDs)
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

    /// A drag-reorder of a collection's grid (Custom Order, `spec/plan.md`
    /// "Reordering"): `itemIDs` is the grid's own new order, dropped-into
    /// array and all — `Library.setOrder` renumbers `sort_key` to match.
    /// One undo step puts the collection's whole previous order back.
    func setOrder(_ itemIDs: [Int64], inCollection collectionID: Int64, undo: UndoManager? = nil) {
        guard let lib = library, let before = collection(collectionID)?.itemIDs, before != itemIDs else { return }
        do {
            try lib.setOrder(itemIDs, inCollection: collectionID)
            collections = try lib.allCollections()
        } catch {
            loadError = "\(error)"
            return
        }
        guard let undo else { return }
        let generation = libraryGeneration
        undo.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                guard model.libraryGeneration == generation else { return }
                model.setOrder(before, inCollection: collectionID, undo: undo)
            }
        }
        undo.setActionName("Reorder")
    }

    /// A copy of a show — its slides, rows, music, markers and editor
    /// state, none of it the same object as the original's — named "<name>
    /// copy" (numbered if that's taken too), in the same collection, right
    /// after it (work order, 2026-09-24).
    func duplicateShow(_ id: Int64, undo: UndoManager? = nil) {
        guard let lib = library, let show = shows.first(where: { $0.id == id }) else { return }
        do {
            let name = nextName("\(show.name) copy", taken: shows.map(\.name))
            var copy = try lib.createShow(name: name, collectionID: show.collectionID)
            copy.slides = show.slides.map { var s = $0; s.id = 0; return s }
            copy.defaults = show.defaults
            copy.overlays = show.overlays
            copy.rows = show.rows
            copy.music = show.music
            copy.markers = show.markers
            copy.editor = show.editor
            copy = try lib.saveShow(copy)
            shows.append(copy)
            collections = try lib.allCollections()
            sidebar = .show(copy.id)
            guard let undo else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.deleteShow(copy.id, undo: undo)
                }
            }
            undo.setActionName("Duplicate Show")
        } catch {
            loadError = "\(error)"
        }
    }

    func deleteShow(_ id: Int64, undo: UndoManager? = nil) {
        guard let lib = library else { return }
        do {
            let snap = try lib.snapshotShow(id: id)
            try lib.deleteShow(id: id)
            shows.removeAll { $0.id == id }
            if sidebar == .show(id) { sidebar = .library }
            guard let undo, let snap else { return }
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.restoreShow(snap, undo: undo)
                }
            }
            undo.setActionName("Delete Show")
        } catch {
            loadError = "\(error)"
        }
    }

    private func restoreShow(_ snap: Library.ShowSnapshot, undo: UndoManager) {
        guard let lib = library else { return }
        do {
            try lib.restoreShow(snap)
            shows = try lib.allShows()
            let generation = libraryGeneration
            undo.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated {
                    guard model.libraryGeneration == generation else { return }
                    model.deleteShow(snap.show.id, undo: undo)
                }
            }
            undo.setActionName("Delete Show")
        } catch {
            loadError = "\(error)"
        }
    }

    /// Star ratings belong to files, so this isn't a show edit; it has its
    /// own undo, which puts each file's previous rating back.
    func setRating(_ rating: Int, for itemIDs: Set<Int64>, undo: UndoManager?) {
        let r = Rating.clamped(rating)
        applyRatings(itemIDs.map { ($0, r) }, undo: undo)
    }

    /// A rating key (`Rating.Key`) on several files: each file steps from
    /// its own rating, as one undo step.
    func applyRatingKey(_ key: Rating.Key, to itemIDs: [Int64], undo: UndoManager?) {
        let changes = itemIDs.map { ($0, key.applied(to: itemsByID[$0]?.rating ?? 0)) }
            .filter { itemsByID[$0.0]?.rating != $0.1 }
        guard !changes.isEmpty else { return }
        applyRatings(changes, undo: undo)
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
    /// Keep One (plan, Phase 3b): keeps `keeper` of `group`. In a
    /// collection the others leave it; in the Library they go to the Trash
    /// and hand the keeper their tags and best rating. A file a show uses
    /// stays either way. One undo step. Returns the plan it carried out.
    @discardableResult
    func keepOne(_ keeper: MediaItem, of group: [MediaItem], collectionID: Int64?, undo: UndoManager?) -> KeepOne.Plan {
        let used = Set(group.map(\.id).filter { !showsUsing([$0]).isEmpty })
        let plan = KeepOne.plan(keeper: keeper, group: group, used: used, trashing: collectionID == nil)
        guard !plan.remove.isEmpty else { return plan }
        undo?.beginUndoGrouping()
        if let cid = collectionID {
            removeFromCollection(plan.remove, cid, undo: undo)
        } else {
            if let tags = plan.tags { setTags([keeper.id: tags], undo: undo) }
            if let rating = plan.rating { setRating(rating, for: [keeper.id], undo: undo) }
            deleteItems(plan.remove, undo: undo)
        }
        undo?.setActionName("Keep One")
        undo?.endUndoGrouping()
        return plan
    }

    func showsUsing(_ itemIDs: Set<Int64>) -> [Show] {
        shows.filter { show in
            show.slides.contains { itemIDs.contains($0.itemID) }
                || show.overlays.contains { itemIDs.contains($0.itemID) }
                || show.music.contains { itemIDs.contains($0.itemID) }
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

        // The lane's images and the songs aren't in the `slides` table
        // (deleteItems below only cleans that up), so they're stripped here,
        // one show save each, same as any other show edit — captured first,
        // so undo can put them back.
        var stripped: [Int64: StrippedClips] = [:]
        for show in shows where show.overlays.contains(where: { idSet.contains($0.itemID) })
                               || show.music.contains(where: { idSet.contains($0.itemID) }) {
            var s = show
            stripped[s.id] = StrippedClips(overlays: s.overlays.filter { idSet.contains($0.itemID) },
                                           music: s.music.filter { idSet.contains($0.itemID) })
            s.overlays.removeAll { idSet.contains($0.itemID) }
            s.music.removeAll { idSet.contains($0.itemID) }
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
                model.restoreDeletedItems(deleted, stripped: stripped, trashedURLs: trashedURLs, undo: undo)
            }
        }
        undo?.setActionName(itemIDs.count == 1 ? "Delete Item" : "Delete Items")
    }

    /// A show's lane images and songs that used deleted files, for undo.
    struct StrippedClips {
        var overlays: [OverlayClip]
        var music: [AudioClip]
    }

    /// `deleteItems`'s undo: the file back from the Trash, the database rows
    /// back with their original ids, and the lane images and songs put back
    /// in each show. Registers a redo the same way `update` does — which,
    /// calling `deleteItems` again, re-derives what to strip from `shows` as
    /// it now stands, rather than needing it passed back in.
    private func restoreDeletedItems(_ deleted: [Library.DeletedItem], stripped: [Int64: StrippedClips],
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
        for (showID, clips) in stripped {
            guard var s = shows.first(where: { $0.id == showID }) else { continue }
            s.overlays += clips.overlays
            s.music += clips.music
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

    func item(_ id: Int64) -> MediaItem? { itemsByID[id] }

    /// A repair, not a workflow (plan, 2b): finds files moved by hand in
    /// Finder and points their rows at the new location, by hash. Not
    /// undoable — it only ever repairs a broken reference back to a real
    /// file, which isn't a step worth reversing the way an edit is.
    func relinkMissingItems() {
        guard let lib = library else { return }
        do {
            let outcomes = try lib.relinkMissingItems()
            if !outcomes.isEmpty {
                items = try lib.allItems()
                itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            }
            let relinked = outcomes.filter { $0.newPath != nil }.count
            relinkResult = RelinkSummary(relinked: relinked, stillMissing: outcomes.count - relinked)
        } catch {
            loadError = "\(error)"
        }
    }
}

/// `AppModel.relinkResult`'s payload, for the alert that reports it.
struct RelinkSummary: Identifiable {
    let id = UUID()
    let relinked: Int
    let stillMissing: Int
}

/// The player (ShowToolsPlayback) reads shows and files through this.
extension AppModel: ShowSource {}
