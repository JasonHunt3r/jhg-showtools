import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore
import ShowToolsPlayback
import PaneKit

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
    /// Groups folded shut (their own id space, so a collection and a group
    /// that happen to share a number don't fold together).
    @State private var foldedGroups: Set<Int64> = []
    /// Renaming: what, and the name being typed.
    @State private var renaming: SidebarItem?
    @State private var draftName = ""
    /// New Collection, named before it's made (audit H1): nothing is ever
    /// called "Untitled" unless someone clicked OK on that name.
    @State private var creatingCollection = false
    @State private var newCollectionName = ""
    /// New Group, the same way: the collection (and parent group, if any)
    /// it's made in, and the name being typed.
    @State private var creatingGroup: (collectionID: Int64, parentID: Int64?)?
    @State private var newGroupName = ""

    var body: some View {
        // Split from the alerts/dialogs below: one expression this size is
        // over the type checker's budget (measured, 2026-09-24).
        layout
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
                case .group(let id): model.renameGroup(id, to: name, undo: undoManager)
                case .show(let id): model.renameShow(id, to: name, undo: undoManager)
                default: break
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New Collection", isPresented: $creatingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                model.newCollection(named: name)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Group", isPresented: Binding(get: { creatingGroup != nil }, set: { if !$0 { creatingGroup = nil } })) {
            TextField("Name", text: $newGroupName)
            Button("Create") {
                let name = newGroupName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let target = creatingGroup else { return }
                model.newGroup(named: name, collectionID: target.collectionID, parentID: target.parentID)
            }
            Button("Cancel", role: .cancel) {}
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

    /// PaneKit replaces NavigationSplitView (spec/panekit.md, step 2): the
    /// Library pane beside the detail. Content hosted across the AppKit
    /// boundary doesn't inherit the SwiftUI environment, so each pane gets
    /// what it needs passed in explicitly.
    private var layout: some View {
        // Each pane's undoManager comes from the window's own responder
        // chain (SwiftUI resolves it that way, not through the
        // environment), so only what's actually environment state — the
        // model — needs passing in.
        PaneLayoutView(controller: model.mainPanes, content: [
            "library": AnyView(libraryList.environment(model)),
            "detail": AnyView(detailView.environment(model)),
        ])
        // Another library's undo steps mean nothing here (see libraryGeneration).
        .onChange(of: model.libraryGeneration) { undoManager?.removeAllActions() }
        .focusedSceneValue(\.requestNewCollection, startCreatingCollection)
        // The sidebar's Delete/⌘Delete fallback (D1), for when its List
        // doesn't have the keyboard (see the comment on `onDeleteCommand`
        // above). Attached to the whole layout, not the List itself.
        .background(SingleKeys { event in
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            if !(NSApp.keyWindow?.firstResponder is NSTableView), event.plainModifiers == [] {
                switch model.sidebar {
                case .show(let id): guard let s = model.show(id) else { return false }; confirmDelete = s
                case .collection(let id): guard let c = model.collection(id) else { return false }; confirmDeleteCollection = c
                case .group(let id): guard let g = model.group(id) else { return false }; deleteGroupAsking(g)
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
    }

    /// The Library pane's content: PaneKit's "library" pane.
    private var libraryList: some View {
        List(selection: Binding(get: { model.sidebar }, set: { model.sidebar = $0 })) {
            // An alternate library shows its own name here.
            Label(model.isOnMaster ? "Library" : model.libraryName,
                  systemImage: model.libraryIsPrivate || model.locked != nil
                      ? "lock.rectangle.stack" : "photo.on.rectangle.angled")
                .badge(model.items.count)
                .tag(SidebarItem.library)
                .contextMenu {
                    Button("Import…") { runImportPanel(model) }
                    Button("New Collection…") { startCreatingCollection() }
                    // Not built (spec/windows.md, "the library panel");
                    // settled 2026-09-24 to go in greyed out until it is.
                    Button("Open Library Panel") {}.disabled(true)
                    Divider()
                    Button("Show in Finder") {
                        if let root = model.library?.root {
                            NSWorkspace.shared.activateFileViewerSelecting([root])
                        }
                    }
                }

            // Library → Collection → Show, as Final Cut's Library → Event → Project.
            // A collection's groups and its shows sit side by side, as
            // siblings (Jason, 2026-09-24, "Groups inside collections").
            Section("Collections") {
                ForEach(model.collections) { c in
                    DisclosureGroup(isExpanded: foldBinding(c.id, in: $folded)) {
                        collectionChildren(c)
                    } label: {
                        collectionRow(c)
                    }
                }
                // Shows in no collection shouldn't exist after the
                // upgrade, but if one does, it still has a place.
                ForEach(orphanShows) { show in showRow(show) }
            }
        }
        // Delete asks first (D1); ⌘Delete skips the question, as the
        // grid's does (spec/conventions.md §Delete/⌘Delete). This
        // `onDeleteCommand` fires when the List genuinely has the
        // keyboard; the SingleKeys fallback for when it doesn't is
        // attached to the whole PaneLayoutView, not here — a
        // `.background(SingleKeys)` directly on this List (a real
        // NSTableView, not the grid's plain ScrollView) hit AppKit's
        // layout-loop guard and crashed on the very first check
        // (2026-09-24, `~/Library/Logs/DiagnosticReports/`, a run of
        // `NavigationPaneModifier`/`CellHostingView` layout frames).
        .onDeleteCommand {
            switch model.sidebar {
            case .show(let id): if let s = model.show(id) { confirmDelete = s }
            case .collection(let id): if let c = model.collection(id) { confirmDeleteCollection = c }
            case .group(let id): if let g = model.group(id) { deleteGroupAsking(g) }
            default: break
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Button("New Collection…") { startCreatingCollection() }
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
    }

    /// The detail pane's content: PaneKit's "detail" pane. A fresh detail
    /// for each library. Ids restart at 1 in every library, so views kept
    /// across a switch (grid tiles, their thumbnails, the selection) would
    /// show the old library's files under the new one's names.
    private var detailView: some View {
        ZStack {
            switch model.sidebar {
            case .show(let id) where model.show(id) != nil:
                ShowView(showID: id)
            case .collection(let id) where model.collection(id) != nil:
                LibraryGridView(collectionID: id)
            case .group(let id) where model.group(id) != nil:
                LibraryGridView(collectionID: model.group(id)?.collectionID, groupID: id)
            default:
                LibraryGridView()
            }
        }
        .id(model.libraryGeneration)
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
        switch renaming {
        case .collection: "Rename Collection"
        case .group: "Rename Group"
        default: "Rename Show"
        }
    }

    private func startRenaming(_ item: SidebarItem, current: String) {
        draftName = current
        renaming = item
    }

    private func startCreatingCollection() {
        newCollectionName = model.nextName("Untitled Collection", taken: model.collections.map(\.name))
        creatingCollection = true
    }

    private func startCreatingGroup(collectionID: Int64, parentID: Int64? = nil) {
        let taken = model.groups.filter { $0.collectionID == collectionID && $0.parentID == parentID }.map(\.name)
        newGroupName = model.nextName("Untitled Group", taken: taken)
        creatingGroup = (collectionID, parentID)
    }

    /// Every group nested inside `id`, direct or not.
    private func subgroupCount(of id: Int64) -> Int {
        let children = model.groups.filter { $0.parentID == id }
        return children.count + children.reduce(0) { $0 + subgroupCount(of: $1.id) }
    }

    private func deleteGroupAsking(_ g: MediaGroup) {
        guard GroupDeleteNotice.confirm(name: g.name, subgroupCount: subgroupCount(of: g.id)) else { return }
        model.deleteGroup(g.id, undo: undoManager)
    }

    /// A disclosure's open/closed state, kept in a `Set` of folded ids
    /// (open by default) — its own function so the closures don't get
    /// re-type-checked as part of a bigger SwiftUI expression each time.
    private func foldBinding(_ id: Int64, in folded: Binding<Set<Int64>>) -> Binding<Bool> {
        Binding(get: { !folded.wrappedValue.contains(id) },
                set: { open in
                    if open { folded.wrappedValue.remove(id) } else { folded.wrappedValue.insert(id) }
                })
    }

    private var orphanShows: [Show] {
        let collectionIDs = Set(model.collections.map(\.id))
        return model.shows.filter { !collectionIDs.contains($0.collectionID ?? -1) }
    }

    /// A collection's groups and its shows, side by side, as siblings.
    private func collectionChildren(_ c: MediaCollection) -> some View {
        Group {
            ForEach(model.topGroups(inCollection: c.id)) { g in groupRow(g) }
            ForEach(model.shows.filter { $0.collectionID == c.id }) { show in showRow(show) }
        }
    }

    func collectionRow(_ c: MediaCollection) -> some View {
        Label(c.name, systemImage: "rectangle.stack")
            .badge(c.itemIDs.count)
            .tag(SidebarItem.collection(c.id))
            .contextMenu {
                Button("New Show in “\(c.name)”") { model.newShow(in: c.id) }
                Button("New Group in “\(c.name)”…") { startCreatingGroup(collectionID: c.id) }
                Divider()
                Button("Rename…") { startRenaming(.collection(c.id), current: c.name) }
                Button("Delete Collection…") { confirmDeleteCollection = c }
            }
            // Dropping files on a collection puts them in it (imported first
            // if they come from Finder or Photos): no question, that's the
            // ask. Dropping a group here can't move it (a group's
            // collection never changes) — its own collection, un-nest it to
            // the top; a different one, add its files there, after asking.
            .onDrop(of: ItemDrag.accepted + [GroupDrag.type], isTargeted: nil) { providers in
                Task {
                    if let gid = await GroupDrag.id(from: providers) { dropGroup(gid, onCollection: c); return }
                    let ids = await model.itemIDs(from: providers)
                    model.addToCollection(ids, c.id)
                }
                return true
            }
    }

    /// A group dropped on a collection row (see `collectionRow`'s `onDrop`).
    private func dropGroup(_ groupID: Int64, onCollection c: MediaCollection) {
        guard let g = model.group(groupID) else { return }
        if g.collectionID == c.id {
            model.moveGroup(g.id, toParent: nil, undo: undoManager)
        } else if GroupToCollectionNotice.confirm(groupName: g.name, count: g.itemIDs.count, collection: c.name) {
            model.addToCollection(g.itemIDs, c.id)
        }
    }

    /// A group's own row, and — recursively — the groups nested inside it
    /// (groups hold groups, like folders; plan, "Groups inside collections").
    /// Its right-click menu is minimal on purpose: the full set is "to
    /// settle with groups" (`spec/conventions.md` §3).
    /// `AnyView`, not `some View`: a recursive function can't otherwise
    /// define its own opaque return type in terms of itself.
    func groupRow(_ g: MediaGroup) -> AnyView {
        let children = model.groups.filter { $0.parentID == g.id }
        let label = Label(g.name, systemImage: "folder")
            .badge(g.itemIDs.count)
            .tag(SidebarItem.group(g.id))
            .contextMenu {
                Button("New Group in “\(g.name)”…") { startCreatingGroup(collectionID: g.collectionID, parentID: g.id) }
                Divider()
                Button("Rename…") { startRenaming(.group(g.id), current: g.name) }
                Button("Delete Group…") { deleteGroupAsking(g) }
            }
            // Draggable, so it can be dropped on another group to nest it
            // (plan, "groups hold groups, like folders") or on a collection
            // (see `collectionRow`).
            .onDrag { GroupDrag.provider(g.id) }
            // A file dropped here joins the group (the Library enforces the
            // membership rule — a group's files must be in its collection,
            // so anything not already there is silently left out). Another
            // group dropped here nests it — refused (silently; the drop is
            // still accepted visually) if that would make a group its own
            // descendant, or cross collections.
            .onDrop(of: ItemDrag.accepted + [GroupDrag.type], isTargeted: nil) { providers in
                Task {
                    if let dragged = await GroupDrag.id(from: providers) {
                        guard dragged != g.id else { return }
                        model.moveGroup(dragged, toParent: g.id, undo: undoManager)
                        return
                    }
                    let ids = await model.itemIDs(from: providers)
                    model.addToGroup(ids, g.id)
                }
                return true
            }
        if children.isEmpty {
            return AnyView(label)
        } else {
            return AnyView(DisclosureGroup(isExpanded: foldBinding(g.id, in: $foldedGroups)) {
                ForEach(children) { child in groupRow(child) }
            } label: {
                label
            })
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
                // Hands the show to BGTools (spec/bgtools.md); not built —
                // settled 2026-09-24 to go in greyed out until it is.
                Button("Play on Desktop") {}.disabled(true)
                Divider()
                Button("Duplicate Show") { model.duplicateShow(show.id, undo: undoManager) }
                Divider()
                Menu("Export") {
                    Button("Show…") { runExportPanel(model, showID: show.id) }
                        .disabled(show.slides.isEmpty || model.exportStatus?.finished == false)
                    Button("Movie…") { runMovieExportPanel(model, showID: show.id) }
                        .disabled(show.slides.isEmpty || model.movieExportStatus?.finished == false)
                }
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

/// New Group's naming alert, its own `ViewModifier` so its closures aren't
/// type-checked as part of `LibraryGridView`'s already-large body.
private struct GroupCreationAlert: ViewModifier {
    @Binding var creatingGroup: (ids: [Int64], collectionID: Int64)?
    @Binding var name: String
    let model: AppModel

    func body(content: Content) -> some View {
        content.alert("New Group", isPresented: Binding(get: { creatingGroup != nil },
                                                          set: { if !$0 { creatingGroup = nil } })) {
            TextField("Name", text: $name)
            Button("Create") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let target = creatingGroup else { return }
                model.newGroup(named: trimmed, collectionID: target.collectionID, itemIDs: target.ids)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Keep as Group with no collection open (plan, decided): explains that a
/// group lives in a collection, offers to make one, then hands off to the
/// group-naming step. Its own `ViewModifier`, same reason as the one above.
private struct GroupedCollectionAlert: ViewModifier {
    @Binding var creatingGroupedCollection: [Int64]?
    @Binding var name: String
    let model: AppModel
    let startGroup: (_ ids: [Int64], _ collectionID: Int64) -> Void

    func body(content: Content) -> some View {
        content.alert("A Group Needs a Collection",
                       isPresented: Binding(get: { creatingGroupedCollection != nil },
                                            set: { if !$0 { creatingGroupedCollection = nil } })) {
            TextField("Name", text: $name)
            Button("Create") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, let ids = creatingGroupedCollection else { return }
                if let cid = model.newCollection(named: trimmed, itemIDs: ids, select: false) {
                    startGroup(ids, cid)
                }
                creatingGroupedCollection = nil
            }
            Button("Cancel", role: .cancel) { creatingGroupedCollection = nil }
        } message: {
            Text("A group lives inside a collection, so this makes one to hold it first. The pictures stay in the library either way.")
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
    /// Set to filter to one group's files, inside `collectionID`.
    var groupID: Int64? = nil
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
    /// New Collection, named before it's made (audit H1): the item ids it
    /// starts with, and the name being typed.
    @State private var creatingCollection: [Int64]?
    @State private var newCollectionName = ""
    /// New Group from the grid's selection, the same way.
    @State private var creatingGroup: (ids: [Int64], collectionID: Int64)?
    @State private var newGroupName = ""
    /// Keep as Group with no collection open (plan): the items waiting on
    /// a collection to be made for them, and the name being typed.
    @State private var creatingGroupedCollection: [Int64]?
    @State private var newGroupedCollectionName = ""
    /// "Add from Library…" on an empty collection (audit H2).
    @State private var addingFromLibrary = false

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
    /// The selection at the moment `anchor` was last set by a plain or
    /// ⌘-click, and where a ⇧-click or step last landed — both feed
    /// `GridSelection`'s pure functions (batch 4, B3).
    @State private var selectionBase: Set<Int64> = []
    @State private var cursor: Int64?
    @State private var dropTargeted = false
    // Find Similar (plan, Phase 3b).
    /// Find Similar Images (was "Group Similar"; renamed 2026-09-24 so
    /// "group" means only a `MediaGroup`): the grid shows look-alikes
    /// together, in clusters.
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
    private var group: MediaGroup? { groupID.flatMap(model.group) }
    /// `collectionID`/`groupID` together, as one `onChange` identity — two
    /// separate `onChange`s tipped this view's body over the type-checker's
    /// budget (measured).
    private var navScope: String { "\(collectionID ?? -1)/\(groupID ?? -1)" }
    private var navigationName: String {
        if let g = group { return g.name }
        if let c = collection { return c.name }
        return "Library"
    }

    /// Everything in view before the bar's search and filters: a group's
    /// files, or the collection's, or the library's, each in the order its
    /// files were added.
    private var all: [MediaItem] {
        if let g = group { return g.itemIDs.compactMap { model.itemsByID[$0] } }
        guard let c = collection else { return model.items }
        return c.itemIDs.compactMap { model.itemsByID[$0] }
    }

    private var similarActive: Bool { grouping || similarTo != nil }

    /// The clusters Find Similar Images shows, in the grid's order.
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
            .help("Find Similar Images: look-alike pictures together")
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
            if let g = group, visible.isEmpty, !similarActive {
                ContentUnavailableView {
                    Label("“\(g.name)” is empty", systemImage: "folder")
                } description: {
                    Text("Drag photos here from the collection's grid, or from Finder or Photos (they'll join the collection too).")
                } actions: {
                    Button("Import…") { runImportPanel(model) }
                }
            } else if let c = collection, visible.isEmpty, !similarActive {
                ContentUnavailableView {
                    Label("“\(c.name)” is empty", systemImage: "rectangle.stack")
                } description: {
                    Text("Drag photos here from Finder or Photos, or select files in the Library and choose Add to Collection.")
                } actions: {
                    Button("Import…") { runImportPanel(model) }
                    Button("Add from Library…") { addingFromLibrary = true }
                        .disabled(model.items.isEmpty)
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
            let cid = collectionID, gid = groupID
            Task {
                let ids = await model.importProviders(providers)
                if let cid { model.addToCollection(ids, cid) }
                if let gid { model.addToGroup(ids, gid) }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .navigationTitle(navigationName)
        .navigationSubtitle(selection.isEmpty ? "\(visible.count) items" : "\(selection.count) selected")
        .onChange(of: navScope) { selection = []; anchor = nil; selectionBase = []; cursor = nil; similarTo = nil }
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
                selectionBase = selection
                return true
            }
            guard event.keyCode == 51 || event.keyCode == 117, !selection.isEmpty else { return false }
            switch event.plainModifiers {
            case []:
                if let gid = groupID { removeFromGroup(orderedSelection, gid) }
                else if let cid = collectionID { removeFromCollection(orderedSelection, cid) }
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
        .sheet(isPresented: $addingFromLibrary) {
            let inCollection = Set(collection?.itemIDs ?? [])
            MultiItemPicker(title: "Add from Library", items: model.items.filter { !inCollection.contains($0.id) }) { ids in
                if let cid = collectionID { model.addToCollection(Array(ids), cid) }
            }
        }
        .alert("New Collection", isPresented: Binding(get: { creatingCollection != nil },
                                                       set: { if !$0 { creatingCollection = nil } })) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let ids = creatingCollection else { return }
                model.newCollection(named: name, itemIDs: ids)
            }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(GroupCreationAlert(creatingGroup: $creatingGroup, name: $newGroupName, model: model))
        .modifier(GroupedCollectionAlert(creatingGroupedCollection: $creatingGroupedCollection,
                                         name: $newGroupedCollectionName, model: model,
                                         startGroup: startCreatingGroup(with:collectionID:)))
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

    private func startCreatingCollection(with ids: [Int64]) {
        newCollectionName = model.nextName("Untitled Collection", taken: model.collections.map(\.name))
        creatingCollection = ids
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

    private func removeFromGroup(_ ids: [Int64], _ gid: Int64) {
        guard !ids.isEmpty else { return }
        model.removeFromGroup(ids, gid, undo: undoManager)
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
                                // The Find Similar Images set header's menu
                                // (settled, spec/conventions.md §3): Select
                                // Group · Keep One…, Keep as Group · New Show
                                // from Group…, Add Group to Collection.
                                .contextMenu {
                                    Button("Select Group") { selection = Set(group.map(\.id)) }
                                    Divider()
                                    Button("Keep One…") { keepGroup = KeepGroup(items: group) }
                                    Button("Keep as Group") { keepAsGroup(group) }
                                    Divider()
                                    Button("New Show from Group…") { model.newShow(itemIDs: group.map(\.id), in: collectionID) }
                                    Menu("Add Group to Collection") {
                                        ForEach(model.collections) { c in
                                            Button(c.name) { model.addToCollection(group.map(\.id), c.id) }
                                                .disabled(c.id == collectionID)
                                        }
                                    }
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
            if let gid = groupID {
                removeFromGroup(orderedSelection, gid)
            } else if let cid = collectionID {
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
            Button("New Collection from \(ids.count == 1 ? "Item" : "\(ids.count) Items")…") {
                startCreatingCollection(with: ids)
            }
            addToCollectionMenu(ids: ids)
            addToGroupMenu(ids: ids)
            if let cid = collectionID {
                Button("Remove from Collection") { removeFromCollection(ids, cid) }
                .help("Take them out of this collection. They stay in the library and in any show that uses them.")
            }
            if let gid = groupID {
                Button("Remove from Group") { removeFromGroup(ids, gid) }
                    .help("Take them out of this group. They stay in the collection.")
            }
            Divider()
            // No Show in Finder here (settled, spec/conventions.md §3): the
            // library holds its own copies, and where the originals went is
            // unknown, so revealing a file would show nothing useful.
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
            Button("New Collection…") { startCreatingCollection(with: ids) }
            if !model.collections.isEmpty { Divider() }
            ForEach(model.collections) { c in
                Button(c.name) { model.addToCollection(ids, c.id) }
                    .disabled(c.id == collectionID)
            }
        }
    }

    /// Only offered inside a collection — a group's files must be in its
    /// collection (plan), so there's nowhere else to put them.
    @ViewBuilder private func addToGroupMenu(ids: [Int64]) -> some View {
        if let cid = collectionID {
            Menu("Add to Group") {
                Button("New Group…") { startCreatingGroup(with: ids, collectionID: cid) }
                let inCollection = model.groups(inCollection: cid)
                if !inCollection.isEmpty { Divider() }
                ForEach(inCollection) { g in
                    Button(g.name) { model.addToGroup(ids, g.id) }
                        .disabled(g.id == groupID)
                }
            }
        }
    }

    private func startCreatingGroup(with ids: [Int64], collectionID: Int64) {
        let taken = model.groups(inCollection: collectionID).map(\.name)
        newGroupName = model.nextName("Untitled Group", taken: taken)
        creatingGroup = (ids, collectionID)
    }

    /// Find Similar Images' Keep as Group (plan, decided): in a collection,
    /// goes straight to naming the group. In the Library view — no
    /// collection open — a group needs one first, so a dialog offers to
    /// make one (suggested name "Grouped Collection"), then the usual
    /// group-naming step follows.
    private func keepAsGroup(_ items: [MediaItem]) {
        let ids = items.map(\.id)
        if let cid = collectionID {
            startCreatingGroup(with: ids, collectionID: cid)
        } else {
            newGroupedCollectionName = model.nextName("Grouped Collection", taken: model.collections.map(\.name))
            creatingGroupedCollection = ids
        }
    }

    /// Selection in grid order, so a new show follows the grid.
    private var orderedSelection: [Int64] {
        visible.map(\.id).filter(selection.contains)
    }

    /// Finder-style clicking: plain replaces, ⌘ toggles, ⇧ selects the
    /// range from the anchor, replacing the previous ⇧-range rather than
    /// adding to it (batch 4, B3; `GridSelection`, unit-tested there).
    private func click(_ id: Int64) {
        let mods = NSEvent.modifierFlags
        let items = visible.map(\.id)
        let r: GridSelection.Result<Int64>
        if mods.contains(.command) {
            r = GridSelection.commandClick(id, selected: selection)
        } else if mods.contains(.shift) {
            r = GridSelection.shiftClick(id, anchor: anchor, base: selectionBase, in: items)
        } else {
            r = GridSelection.click(id)
        }
        selection = r.selected
        anchor = r.anchor
        selectionBase = r.base
        cursor = r.cursor
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
    panel.allowedContentTypes = [.image, .movie, .audio, .folder]
    panel.prompt = intoCollection ? "Import" : "Add to Library"
    panel.message = "Files are copied into the ShowTools library. Folders are searched for images, videos or audio."

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

/// Import files straight into a show (an empty Edit Slides list's
/// "Import…", audit H2): imported the same way as File ▸ Import…, then
/// appended as slides.
@MainActor
func runImportIntoShowPanel(_ model: AppModel, showID: Int64, undo: UndoManager?) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.image, .movie, .audio, .folder]
    panel.prompt = "Import"
    panel.message = "Files are copied into the ShowTools library and added to this show. Folders are searched for images, videos or audio."
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    Task {
        let ids = await model.importFiles(urls)
        guard !ids.isEmpty else { return }
        model.append(ids, to: showID, undo: undo)
    }
}
