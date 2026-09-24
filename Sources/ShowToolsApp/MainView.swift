import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore
import ShowToolsPlayback

/// Types a drop onto the app can carry: files from Finder, file promises
/// (or data) from Photos.
let droppableTypes: [UTType] = [.fileURL, .image, .movie, .audio]

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var confirmDelete: Show?
    @State private var confirmDeleteCollection: MediaCollection?
    /// Collections folded shut in the sidebar (open by default).
    @State private var folded: Set<Int64> = []
    /// Renaming: what, and the name being typed.
    @State private var renaming: SidebarItem?
    @State private var draftName = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebar) {
                // An alternate library shows its own name here.
                Label(model.isOnMaster ? "Library" : model.libraryName,
                      systemImage: model.libraryIsPrivate || model.locked != nil
                          ? "lock.rectangle.stack" : "photo.on.rectangle.angled")
                    .badge(model.items.count)
                    .tag(SidebarItem.library)

                // Library → Collection → Show, as Final Cut's Library → Event → Project.
                Section("Collections") {
                    ForEach(model.collections) { c in
                        DisclosureGroup(isExpanded: Binding(get: { !folded.contains(c.id) },
                                                            set: { open in
                                                                if open { folded.remove(c.id) } else { folded.insert(c.id) }
                                                            })) {
                            ForEach(model.shows.filter { $0.collectionID == c.id }) { show in
                                showRow(show)
                            }
                        } label: {
                            collectionRow(c)
                        }
                    }
                    // Shows in no collection shouldn't exist after the
                    // upgrade, but if one does, it still has a place.
                    ForEach(model.shows.filter { s in !model.collections.contains { $0.id == s.collectionID } }) { show in
                        showRow(show)
                    }
                }
            }
            // The max is the point: without one, a double-click on the
            // divider took the sidebar to 1355pt in a 1374pt window and
            // pushed everything else off the right edge (2026-09-23).
            // A sidebar of names never needs more than this.
            .navigationSplitViewColumnWidth(min: 180, ideal: DefaultLayout.sidebarWidth, max: 360)
            // Delete asks first (D1); ⌘Delete skips the question, as the
            // grid's does (spec/conventions.md §Delete/⌘Delete). This
            // `onDeleteCommand` fires when the List genuinely has the
            // keyboard; the SingleKeys fallback for when it doesn't is
            // attached below the whole NavigationSplitView, not here — a
            // `.background(SingleKeys)` directly on this List (a real
            // NSTableView, not the grid's plain ScrollView) hit AppKit's
            // layout-loop guard and crashed on the very first check
            // (2026-09-24, `~/Library/Logs/DiagnosticReports/`, a run of
            // `NavigationPaneModifier`/`CellHostingView` layout frames).
            .onDeleteCommand {
                switch model.sidebar {
                case .show(let id): if let s = model.show(id) { confirmDelete = s }
                case .collection(let id): if let c = model.collection(id) { confirmDeleteCollection = c }
                default: break
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button("New Collection") { model.newCollection() }
                        Button("New Show") { model.newShow() }
                            .disabled(model.collections.isEmpty)
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("New collection, or a new show in the selected collection")
                    Spacer()
                }
                .padding(8)
            }
        } detail: {
            // A fresh detail for each library. Ids restart at 1 in every
            // library, so views kept across a switch (grid tiles, their
            // thumbnails, the selection) would show the old library's files
            // under the new one's names.
            ZStack {
                switch model.sidebar {
                case .show(let id) where model.show(id) != nil:
                    ShowView(showID: id)
                case .collection(let id) where model.collection(id) != nil:
                    LibraryGridView(collectionID: id)
                default:
                    LibraryGridView()
                }
            }
            .id(model.libraryGeneration)
        }
        // Another library's undo steps mean nothing here (see libraryGeneration).
        .onChange(of: model.libraryGeneration) { undoManager?.removeAllActions() }
        // The sidebar's Delete/⌘Delete fallback (D1), for when its List
        // doesn't have the keyboard (see the comment on `onDeleteCommand`
        // above). Attached to the whole split view, not the List itself.
        .background(SingleKeys { event in
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            if !(NSApp.keyWindow?.firstResponder is NSTableView), event.plainModifiers == [] {
                switch model.sidebar {
                case .show(let id): guard let s = model.show(id) else { return false }; confirmDelete = s
                case .collection(let id): guard let c = model.collection(id) else { return false }; confirmDeleteCollection = c
                default: return false
                }
                return true
            }
            guard event.plainModifiers == [.command] else { return false }
            switch model.sidebar {
            case .show(let id):
                guard let s = model.show(id) else { return false }
                model.deleteShow(s.id, undo: undoManager)
            case .collection(let id):
                guard let c = model.collection(id) else { return false }
                model.deleteCollection(c.id, undo: undoManager)
            default:
                return false
            }
            return true
        }.opacity(0).allowsHitTesting(false))
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                ExportBanner()
                MovieExportBanner()
                ImportBanner()
            }
        }
        .overlay {
            if let locked = model.locked {
                LockedLibraryView(name: locked.name)
            }
        }
        .overlay {
            if let err = model.loadError {
                ContentUnavailableView("Library problem", systemImage: "exclamationmark.triangle",
                                       description: Text(err))
                    .background(.background)
            }
        }
        .confirmationDialog("Delete “\(confirmDeleteCollection?.name ?? "")”?",
                            isPresented: Binding(get: { confirmDeleteCollection != nil },
                                                 set: { if !$0 { confirmDeleteCollection = nil } }),
                            presenting: confirmDeleteCollection) { c in
            Button("Delete Collection", role: .destructive) { model.deleteCollection(c.id, undo: undoManager) }
        } message: { c in
            let n = model.shows.filter { $0.collectionID == c.id }.count
            Text(n == 0 ? "The images stay in the library. You can undo this."
                 : "Its \(n == 1 ? "show" : "\(n) shows") will be deleted too. The images stay in the library. You can undo this.")
        }
        .alert(renamingTitle, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Rename") {
                let name = draftName.trimmingCharacters(in: .whitespaces)
                switch renaming {
                case .collection(let id): model.renameCollection(id, to: name, undo: undoManager)
                case .show(let id): model.renameShow(id, to: name, undo: undoManager)
                default: break
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete “\(confirmDelete?.name ?? "")”?",
                            isPresented: Binding(get: { confirmDelete != nil },
                                                 set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { show in
            Button("Delete Show", role: .destructive) { model.deleteShow(show.id, undo: undoManager) }
        } message: { _ in
            Text("The show's slide order and settings are deleted. The images stay in the library.")
        }
        .alert("Relink Missing Files",
              isPresented: Binding(get: { model.relinkResult != nil }, set: { if !$0 { model.relinkResult = nil } }),
              presenting: model.relinkResult) { _ in
            Button("OK") {}
        } message: { r in
            Text(relinkMessage(r))
        }
    }

    private func relinkMessage(_ r: RelinkSummary) -> String {
        if r.relinked == 0 && r.stillMissing == 0 { return "No missing files were found." }
        var parts: [String] = []
        if r.relinked > 0 { parts.append("\(r.relinked) file\(r.relinked == 1 ? "" : "s") relinked") }
        if r.stillMissing > 0 {
            parts.append("\(r.stillMissing) still missing — no file with a matching hash was found")
        }
        return parts.joined(separator: "; ") + "."
    }
}

extension MainView {
    private var renamingTitle: String {
        if case .collection = renaming { return "Rename Collection" }
        return "Rename Show"
    }

    private func startRenaming(_ item: SidebarItem, current: String) {
        draftName = current
        renaming = item
    }

    func collectionRow(_ c: MediaCollection) -> some View {
        Label(c.name, systemImage: "rectangle.stack")
            .badge(c.itemIDs.count)
            .tag(SidebarItem.collection(c.id))
            .contextMenu {
                Button("New Show in “\(c.name)”") { model.newShow(in: c.id) }
                Divider()
                Button("Rename…") { startRenaming(.collection(c.id), current: c.name) }
                Button("Delete Collection…") { confirmDeleteCollection = c }
            }
            // Dropping files on a collection puts them in it (imported first
            // if they come from Finder or Photos): no question, that's the ask.
            .onDrop(of: ItemDrag.accepted, isTargeted: nil) { providers in
                Task {
                    let ids = await model.itemIDs(from: providers)
                    model.addToCollection(ids, c.id)
                }
                return true
            }
    }

    func showRow(_ show: Show) -> some View {
        Label(show.name, systemImage: "play.rectangle")
            .badge(show.slides.count)
            .tag(SidebarItem.show(show.id))
            .contextMenu {
                Button("Play") { Player.open(show: show, model: model, fullScreen: false) }
                    .disabled(show.slides.isEmpty)
                Button("Play Full Screen") { Player.open(show: show, model: model, fullScreen: true) }
                    .disabled(show.slides.isEmpty)
                Divider()
                Button("Rename…") { startRenaming(.show(show.id), current: show.name) }
                Button("Delete Show…") { confirmDelete = show }
            }
            // Dropping files on a show appends them to it (asking first about
            // any not in its collection).
            .onDrop(of: ItemDrag.accepted, isTargeted: nil) { providers in
                Task {
                    let ids = await model.itemIDs(from: providers)
                    model.append(ids, to: show.id, undo: undoManager)
                }
                return true
            }
    }
}

/// Import progress, then a summary that stays until dismissed.
struct ImportBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.importStatus {
            HStack(spacing: 12) {
                if s.finished {
                    Image(systemName: s.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s.failures.isEmpty ? .green : .orange)
                    Text("Import finished — \(s.summary)")
                    if !s.failures.isEmpty {
                        Menu("Details") {
                            ForEach(Array(s.failures.enumerated()), id: \.offset) { _, f in
                                Text("\(f.0): \(f.1)")
                            }
                        }
                        .fixedSize()
                    }
                    Button("Done") { model.importStatus = nil }
                } else {
                    ProgressView(value: Double(s.done), total: Double(max(s.total, 1)))
                        .frame(width: 160)
                    Text("Importing \(s.done) of \(s.total)…")
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Library grid

/// The library's files, or one collection's, as a grid like Photos: a size
/// slider in the toolbar, a bar at the top to search, filter and sort, and
/// Finder-style selection. Selected files drag onto a collection or a show
/// in the sidebar.
struct LibraryGridView: View {
    /// Nil shows the whole library.
    var collectionID: Int64? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<Int64> = []
    @State private var search = ""
    @AppStorage("gridKind") private var kind: KindFilter = .all
    @AppStorage("gridMinRating") private var minRating = 0
    @AppStorage("gridUncollected") private var onlyUncollected = false
    @AppStorage("gridSort") private var sort: SortOrder = .added
    /// The grid takes the keyboard on a click, so Delete and ⌘Delete reach
    /// it even before anything's been clicked in this session.
    @FocusState private var focused: Bool
    /// What Delete is about to send to the Trash — nil until it's confirmed.
    @State private var confirmDeleteIDs: [Int64]?
    /// The batch-rename sheet's targets — nil while it's closed.
    @State private var renameIDs: [Int64]?

    enum KindFilter: String, CaseIterable {
        case all, stills, animations, videos, songs
        var title: String {
            switch self {
            case .all: "All Kinds"
            case .stills: "Photos"
            case .animations: "Animations"
            case .videos: "Videos"
            case .songs: "Audio"
            }
        }
        func matches(_ k: MediaKind) -> Bool {
            switch self {
            case .all: true
            case .stills: k == .image
            case .animations: k == .animatedImage
            case .videos: k == .video
            case .songs: k == .audio
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case added, addedNewest, name, rating
        var title: String {
            switch self {
            case .added: "Date Added, Oldest First"
            case .addedNewest: "Date Added, Newest First"
            case .name: "Name"
            case .rating: "Rating, Highest First"
            }
        }
    }
    @State private var anchor: Int64?
    @State private var dropTargeted = false
    // Find Similar (plan, Phase 3b).
    /// Group Similar: the grid shows look-alikes together, in groups.
    @State private var grouping = false
    /// Show Similar: this picture, then the ones like it, closest first.
    @State private var similarTo: Int64?
    /// The similarity slider: how far apart two pictures may be and still
    /// count, from close (copies, crops) to loose (a series, look-alikes).
    @AppStorage("similarWithin") private var within: Double = 0.45
    @State private var index: SimilarityIndex?
    /// Keep One's group, while its sheet is open.
    @State private var keepGroup: KeepGroup?
    struct KeepGroup: Identifiable {
        let items: [MediaItem]
        var id: Int64 { items.first?.id ?? 0 }
    }
    static let closest = 0.15, loosest = 0.75
    @AppStorage("gridTileSize") private var tileSize: Double = 150

    private var collection: MediaCollection? { collectionID.flatMap(model.collection) }

    /// Everything in view before the bar's search and filters: the library,
    /// or the collection in the order its files were added.
    private var all: [MediaItem] {
        guard let c = collection else { return model.items }
        return c.itemIDs.compactMap { model.itemsByID[$0] }
    }

    private var similarActive: Bool { grouping || similarTo != nil }

    /// The groups Group Similar shows, in the grid's order.
    private var similarGroups: [[MediaItem]] {
        guard grouping, let index else { return [] }
        let byID = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return index.groups(within: Float(within)).map { $0.compactMap { byID[$0] } }.filter { $0.count > 1 }
    }

    /// The files shown: the filtered ones, or with Find Similar on, the
    /// groups laid end to end, or one picture and those like it.
    private var visible: [MediaItem] {
        if let id = similarTo {
            guard let first = filtered.first(where: { $0.id == id }) ?? model.itemsByID[id] else { return [] }
            let byID = Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return [first] + (index?.similar(to: id, within: Float(within)).compactMap { byID[$0.id] } ?? [])
        }
        if grouping { return similarGroups.flatMap { $0 } }
        return filtered
    }

    /// The pictures Find Similar compares: the stills and animations in view.
    private var comparable: [MediaItem] { filtered.filter { Fingerprints.fingerprintable($0.kind) } }

    /// The files in view, searched, filtered and sorted.
    private var filtered: [MediaItem] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let collected = onlyUncollected && collection == nil
            ? Set(model.collections.flatMap(\.itemIDs)) : []
        let shown = all.filter { item in
            (needle.isEmpty || item.fileName.lowercased().contains(needle)
                || item.tags.contains { $0.lowercased().contains(needle) })
                && kind.matches(item.kind)
                && item.rating >= minRating
                && !(onlyUncollected && collection == nil && collected.contains(item.id))
        }
        switch sort {
        case .added: return shown
        case .addedNewest: return shown.reversed()
        case .name: return shown.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .rating: return shown.sorted { $0.rating > $1.rating }
        }
    }

    private var filtering: Bool {
        kind != .all || minRating > 0 || (onlyUncollected && collection == nil)
    }

    /// Search, filters and sort, over the grid.
    private var bar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
            .frame(maxWidth: 260)

            Menu {
                Picker("Kind", selection: $kind) {
                    ForEach(KindFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Rating", selection: $minRating) {
                    Text("Any Rating").tag(0)
                    ForEach(1...5, id: \.self) { n in
                        Text(String(repeating: "★", count: n) + (n < 5 ? " or more" : "")).tag(n)
                    }
                }
                .pickerStyle(.inline)
                if collection == nil {
                    Divider()
                    Toggle("Not in Any Collection", isOn: $onlyUncollected)
                }
            } label: {
                Label("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill"
                                                       : "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(filtering ? Color.accentColor : .primary)

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                grouping.toggle()
                similarTo = nil
            } label: {
                Label("Similar", systemImage: grouping ? "square.stack.3d.up.fill" : "square.stack.3d.up")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(grouping ? Color.accentColor : .primary)
            .help("Group Similar: look-alike pictures together")
            if similarActive { similarControls }

            Spacer()
            if visible.count != all.count {
                Text("\(visible.count) of \(all.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// The slider, what Show Similar is showing, and the fingerprints' progress.
    @ViewBuilder private var similarControls: some View {
        if let id = similarTo, let item = model.itemsByID[id] {
            HStack(spacing: 4) {
                Text("Like “\(item.fileName)”").lineLimit(1).truncationMode(.middle).frame(maxWidth: 160)
                Button { similarTo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Back to all")
            }
        }
        HStack(spacing: 4) {
            Text("Close").font(.caption).foregroundStyle(.secondary)
            Slider(value: $within, in: Self.closest...Self.loosest).frame(width: 110)
                .help("Left: only copies and crops. Right: a series, and pictures that look alike.")
            Text("Loose").font(.caption).foregroundStyle(.secondary)
        }
        if let p = Fingerprints.shared.progress {
            ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 60)
            Text("Reading \(p.done) of \(p.total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    var body: some View {
        Group {
            if let c = collection, visible.isEmpty, !similarActive {
                ContentUnavailableView {
                    Label("“\(c.name)” is empty", systemImage: "rectangle.stack")
                } description: {
                    Text("Drag photos here from Finder or Photos, or select files in the Library and choose Add to Collection.")
                }
            } else if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Your library is empty", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drag photos, animated GIFs or videos here — from Finder or Photos — or choose File ▸ Import. Files are copied into the library, so the originals can be deleted afterwards.")
                } actions: {
                    Button("Import…") { runImportPanel(model) }
                }
            } else {
                VStack(spacing: 0) {
                    bar
                    Divider()
                    grid
                }
            }
        }
        .onDrop(of: droppableTypes, isTargeted: $dropTargeted) { providers in
            let cid = collectionID
            Task {
                let ids = await model.importProviders(providers)
                if let cid { model.addToCollection(ids, cid) }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .navigationTitle(collection?.name ?? "Library")
        .navigationSubtitle(selection.isEmpty ? "\(visible.count) items" : "\(selection.count) selected")
        .onChange(of: collectionID) { selection = []; anchor = nil; similarTo = nil }
        // Fingerprints for what's in view, worked out once each.
        .task(id: similarActive ? comparable.map(\.id) : []) {
            guard similarActive else { return }
            Fingerprints.shared.prepare(comparable.compactMap { i in model.url(for: i).map { (i, $0) } })
        }
        // The index, rebuilt as fingerprints arrive or the view changes.
        .task(id: similarActive ? "\(Fingerprints.shared.revision) \(comparable.map(\.id))" : "") {
            guard similarActive else { index = nil; return }
            let prints = comparable.compactMap { i in Fingerprints.shared.print(i).map { (id: i.id, print: $0) } }
            let reach = Float(Self.loosest)
            index = await Task.detached(priority: .userInitiated) { SimilarityIndex(prints, reach: reach) }.value
        }
        .onChange(of: selection) { model.infoPanelSelection = orderedSelection }
        .toolbar {
            ToolbarItemGroup {
                Slider(value: $tileSize, in: 90...320).frame(width: 100)
                    .help("Thumbnail size")
                Button { runImportPanel(model) } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import files or folders")
                addToShowMenu(ids: orderedSelection)
                    .disabled(selection.isEmpty)
                Button { showGetInfo() } label: { Label("Get Info", systemImage: "info.circle") }
                    .help("Show info and tags for the selection (⌘I)")
                    .disabled(selection.isEmpty)
            }
        }
        // Delete by context (plan, Phase 3b; Photos' convention). In the
        // Library: Delete asks, then Trash; ⌘Delete skips the question. In a
        // collection: Delete takes them out of it (undoable); ⌘Delete deletes
        // them from the library, and asks first.
        // Delete, ⌘Delete and ⌘A (Select All, audit A1) are taken here,
        // before AppKit, rather than through SwiftUI focus: a click on a
        // tile never gave the grid the keyboard (Jason's click and axtool's
        // alike, 2026-09-22; setting the focus on click, and moving the
        // handlers, didn't change it).
        // Not while text is edited (SingleKeys), not while a list (the
        // sidebar) has the keyboard.
        .background(SingleKeys { event in
            guard !(NSApp.keyWindow?.firstResponder is NSTableView) else { return false }
            if event.keyCode == 0, event.plainModifiers == [.command] {
                guard !visible.isEmpty else { return false }
                selection = Set(visible.map(\.id))
                return true
            }
            guard event.keyCode == 51 || event.keyCode == 117, !selection.isEmpty else { return false }
            switch event.plainModifiers {
            case []:
                if let cid = collectionID { removeFromCollection(orderedSelection, cid) }
                else { requestDelete(orderedSelection, confirm: true) }
            case [.command]:
                requestDelete(orderedSelection, confirm: collectionID != nil)
            default:
                return false
            }
            return true
        }.opacity(0).allowsHitTesting(false))
        .confirmationDialog(deleteDialogTitle,
                            isPresented: Binding(get: { confirmDeleteIDs != nil },
                                                 set: { if !$0 { confirmDeleteIDs = nil } }),
                            presenting: confirmDeleteIDs) { ids in
            Button(ids.count == 1 ? "Move to Trash" : "Move \(ids.count) Items to Trash", role: .destructive) {
                model.deleteItems(ids, undo: undoManager)
                selection.subtract(ids)
            }
        } message: { ids in
            Text(deleteDialogMessage(ids))
        }
        .sheet(item: $keepGroup) { g in
            KeepOneSheet(group: g.items, collectionID: collectionID, undoManager: undoManager) { removed in
                selection.subtract(removed)
                keepGroup = nil
            }
        }
        .sheet(item: Binding(get: { renameIDs.map(IdentifiedIDs.init) },
                             set: { renameIDs = $0?.ids })) { wrapped in
            BatchRenameSheet(itemIDs: wrapped.ids, undoManager: undoManager)
        }
        .focusedSceneValue(\.librarySelectionCount, selection.count)
        .focusedSceneValue(\.requestLibraryRename, {
            guard !orderedSelection.isEmpty else { return }
            renameIDs = orderedSelection
        })
        .focusedSceneValue(\.requestLibraryGetInfo, showGetInfo)
    }

    private func showGetInfo() {
        guard !orderedSelection.isEmpty else { return }
        model.infoPanelSelection = orderedSelection
        InfoPanel.show(model: model, undoManager: undoManager)
    }

    private var deleteDialogTitle: String {
        guard let ids = confirmDeleteIDs else { return "" }
        if ids.count == 1, let item = model.itemsByID[ids[0]] { return "Move “\(item.fileName)” to the Trash?" }
        return "Move \(ids.count) items to the Trash?"
    }

    private func deleteDialogMessage(_ ids: [Int64]) -> String {
        let plural = ids.count == 1 ? "" : "s"
        let n = model.showsUsing(Set(ids)).count
        // In a collection, say plainly that this is more than leaving it.
        let scope = collectionID == nil ? "" : "This deletes \(ids.count == 1 ? "it" : "them") from the library, not just this collection. "
        guard n > 0 else { return scope + "The file\(plural) will be moved to the Trash." }
        return scope + "Used in \(n == 1 ? "1 show" : "\(n) shows"). Every slide and lane image using "
            + "\(ids.count == 1 ? "it" : "them") will be removed, and the file\(plural) moved to the Trash."
    }

    private func removeFromCollection(_ ids: [Int64], _ cid: Int64) {
        guard !ids.isEmpty else { return }
        model.removeFromCollection(ids, cid, undo: undoManager)
        selection.subtract(ids)
    }

    /// Delete asks first; ⌘Delete (above) skips straight to it.
    private func requestDelete(_ ids: [Int64], confirm: Bool) {
        guard !ids.isEmpty else { return }
        if confirm {
            confirmDeleteIDs = ids
        } else {
            model.deleteItems(ids, undo: undoManager)
            selection.subtract(ids)
        }
    }

    private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.4), spacing: 10)]
        return ScrollView {
            if grouping && similarTo == nil {
                let groups = similarGroups
                if groups.isEmpty {
                    similarEmpty
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(groups.enumerated()), id: \.element.first?.id) { n, group in
                            Section {
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(group) { item in tile(item) }
                                }
                            } header: {
                                HStack {
                                    Text("\(group.count) alike").font(.headline).foregroundStyle(.secondary)
                                        .accessibilityLabel("Group \(n + 1), \(group.count) alike")
                                    Button("Keep One…") { keepGroup = KeepGroup(items: group) }
                                        .controlSize(.small)
                                        .help("Choose one of these to keep; the others "
                                              + (collectionID == nil ? "go to the Trash" : "leave this collection"))
                                        .accessibilityLabel("Keep One of group \(n + 1)")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visible) { item in
                        tile(item)
                    }
                }
                .padding(12)
                if similarTo != nil, visible.count <= 1 { similarEmpty }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { selection = []; focused = true }
        // The grid, not the bar above it with Search, is what takes the
        // keyboard (by Tab; Delete itself is caught by SingleKeys, above).
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        // Edit ▸ Delete, when the grid has the keyboard.
        .onDeleteCommand {
            if let cid = collectionID {
                removeFromCollection(orderedSelection, cid)
            } else {
                requestDelete(orderedSelection, confirm: true)
            }
        }
    }

    /// Nothing alike at this setting (or not worked out yet).
    private var similarEmpty: some View {
        Text(Fingerprints.shared.progress != nil ? "Looking at the pictures…"
             : "Nothing alike at this setting. Slide toward Loose to find more.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(40)
    }

    private func tile(_ item: MediaItem) -> some View {
        let selected = selection.contains(item.id)
        return VStack(spacing: 4) {
            ThumbnailView(item: item, url: model.url(for: item))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
            Text(item.fileName)
                .font(.caption)
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { click(item.id) }
        // A selected tile drags the whole selection; any other, just itself.
        .onDrag { ItemDrag.provider(selection.contains(item.id) ? orderedSelection : [item.id]) }
        .contextMenu {
            let ids = selection.contains(item.id) ? orderedSelection : [item.id]
            Button("New Show from \(ids.count == 1 ? "Item" : "\(ids.count) Items")") {
                model.newShow(itemIDs: ids, in: collectionID)
            }
            addToShowMenu(ids: ids)
            if Fingerprints.fingerprintable(item.kind) {
                Button("Show Similar") {
                    grouping = false
                    similarTo = item.id
                    selection = [item.id]
                }
            }
            Divider()
            Button("New Collection from \(ids.count == 1 ? "Item" : "\(ids.count) Items")") {
                model.newCollection(itemIDs: ids)
            }
            addToCollectionMenu(ids: ids)
            if let cid = collectionID {
                Button("Remove from Collection") { removeFromCollection(ids, cid) }
                .help("Take them out of this collection. They stay in the library and in any show that uses them.")
            }
            Divider()
            Button("Show in Finder") {
                let urls = ids.compactMap { model.itemsByID[$0] }.compactMap(model.url(for:))
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            Button("Rename…") { renameIDs = ids }
            Button("Get Info") { model.infoPanelSelection = ids; InfoPanel.show(model: model, undoManager: undoManager) }
            Divider()
            Button("Move to Trash…", role: .destructive) { requestDelete(ids, confirm: true) }
        }
    }

    private func addToShowMenu(ids: [Int64]) -> some View {
        Menu {
            Button("New Show…") { model.newShow(itemIDs: ids) }
            if !model.shows.isEmpty { Divider() }
            ForEach(model.shows) { show in
                Button(show.name) { model.append(ids, to: show.id, undo: undoManager) }
            }
        } label: {
            Label("Add to Show", systemImage: "rectangle.stack.badge.plus")
        }
        .help("Add the selection to a show")
    }

    private func addToCollectionMenu(ids: [Int64]) -> some View {
        Menu("Add to Collection") {
            Button("New Collection…") { model.newCollection(itemIDs: ids) }
            if !model.collections.isEmpty { Divider() }
            ForEach(model.collections) { c in
                Button(c.name) { model.addToCollection(ids, c.id) }
                    .disabled(c.id == collectionID)
            }
        }
    }

    /// Selection in grid order, so a new show follows the grid.
    private var orderedSelection: [Int64] {
        visible.map(\.id).filter(selection.contains)
    }

    /// Finder-style clicking: plain replaces, ⌘ toggles, ⇧ extends a range.
    private func click(_ id: Int64) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if mods.contains(.shift), let a = anchor,
                  let i = visible.firstIndex(where: { $0.id == a }),
                  let j = visible.firstIndex(where: { $0.id == id }) {
            selection.formUnion(visible[min(i, j)...max(i, j)].map(\.id))
        } else {
            selection = [id]
            anchor = id
        }
        focused = true
    }
}

/// File ▸ Import… (into a collection) and File ▸ Add to Library… (the
/// library only). Many files and whole folders at once; folders are
/// searched all the way down.
///
/// With `intoCollection`, the panel has an "Import into:" menu: every
/// collection, New Collection, and Library Only, starting on the collection
/// the sidebar is in (Library Only when the sidebar is on the Library).
/// "Make a collection for each folder" (Jason, 2026-09-22) gives every
/// chosen folder a new collection of its own name instead; chosen files
/// still go where the menu says.
@MainActor
func runImportPanel(_ model: AppModel, intoCollection: Bool = true) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.image, .movie, .folder]
    panel.prompt = intoCollection ? "Import" : "Add to Library"
    panel.message = "Files are copied into the ShowTools library. Folders are searched for images and videos."

    enum Target { static let newCollection = -1, libraryOnly = -2 }
    var popup: NSPopUpButton?
    var perFolder: NSButton?
    if intoCollection {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for c in model.collections {
            p.addItem(withTitle: c.name)
            p.lastItem?.tag = Int(c.id)
        }
        p.menu?.addItem(.separator())
        p.addItem(withTitle: "New Collection")
        p.lastItem?.tag = Target.newCollection
        p.addItem(withTitle: "Library Only")
        p.lastItem?.tag = Target.libraryOnly
        let start: Int = model.sidebar == .library ? Target.libraryOnly : Int(model.currentCollectionID ?? -2)
        p.selectItem(withTag: start)
        let label = NSTextField(labelWithString: "Import into:")
        let row = NSStackView(views: [label, p])
        let box = NSButton(checkboxWithTitle: "Make a collection for each folder", target: nil, action: nil)
        box.toolTip = "Each folder you choose becomes a new collection named after it. Files chosen on their own go where “Import into” says."
        perFolder = box
        let stack = NSStackView(views: [row, box])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        panel.accessoryView = stack
        panel.isAccessoryViewDisclosed = true
        popup = p
    }
    guard panel.runModal() == .OK else { return }
    var urls = panel.urls
    let target = popup?.selectedTag() ?? Target.libraryOnly
    var folders: [URL] = []
    if perFolder?.state == .on {
        folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        urls.removeAll { folders.contains($0) }
    }
    Task {
        for folder in folders {
            let ids = await model.importFiles([folder])
            if !ids.isEmpty {
                model.newCollection(named: SetlistImport.showName(for: folder), itemIDs: ids, select: folder == folders.last && urls.isEmpty)
            }
        }
        guard !urls.isEmpty else { return }
        let ids = await model.importFiles(urls)
        guard !ids.isEmpty else { return }
        switch target {
        case Target.libraryOnly: break
        case Target.newCollection: model.newCollection(itemIDs: ids)
        default: model.addToCollection(ids, Int64(target))
        }
    }
}
