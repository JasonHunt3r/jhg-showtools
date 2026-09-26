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
    /// Same key as `ShowView`'s own — governs the mode picker and which
    /// content `timelinePane` shows (real or greyed placeholder).
    @AppStorage("editMode") private var mode: EditMode = .slides
    @AppStorage("showRatings") private var showRatings = true

    var body: some View {
        // Split from the alerts/dialogs below: one expression this size is
        // over the type checker's budget (measured, 2026-09-24).
        layout
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
            "storyline": AnyView(timelinePane.environment(model)),
        ])
        // Another library's undo steps mean nothing here (see libraryGeneration).
        .onChange(of: model.libraryGeneration) { undoManager?.removeAllActions() }
        .focusedSceneValue(\.requestNewCollection, startCreatingCollection)
        // The timeline pane only means something while a show is open —
        // closed the rest of the time, rather than showing empty space
        // (`spec/panekit.md`, "The order," step 5's follow-up,
        // 2026-09-25). `initial: true` closes it on a launch that opens
        // straight into the Library, and opens it (to its last remembered
        // size) on a launch that reopens a show mid-edit. Doesn't fight a
        // manual close/open while `isShowOpen` itself hasn't changed —
        // this only runs when it does. Open in both edit modes now (item
        // 19, feedback worklist): Edit Slides shows the same bar, greyed
        // out (`EditShowTimelinePane.active`), instead of the split
        // closing and reopening every time the mode picker is clicked.
        // Leaving the show entirely while it's popped out puts it back
        // first — closing a split its pane has already left doesn't close
        // *that* window, which would otherwise sit open and blank
        // (measured with axtool: switching to Edit Slides left an empty
        // "Timeline" window on screen).
        .onChange(of: isShowOpen, initial: true) { _, open in
            if !open, model.mainPanes.isPoppedOut("storyline") { model.mainPanes.putBack("storyline") }
            model.mainPanes.setOpen("window", open)
        }
        // The sidebar's Delete/⌘Delete fallback (D1), for when its List
        // doesn't have the keyboard (see the comment on `onDeleteCommand`
        // above). Attached to the whole layout, not the List itself.
        // **Tries the timeline pane's own selection first** (found
        // 2026-09-25, moving the timeline pane to `model.mainPanes`,
        // `spec/panekit.md` step 5's follow-up): a slide/transition/
        // overlay/marker selected in the storyline used to be
        // `EditShowTimelinePane`'s own `.onDeleteCommand`, but that raced
        // this very handler for the same keypress once they were two
        // separate `SingleKeys` instances on the same window — which one
        // ran first was undefined, and "delete the whole show" sometimes
        // won. One handler, one priority order, settles it.
        .background(SingleKeys { event in
            // Item 20: U shows and hides the ratings, wherever the keyboard
            // is. Taken here, window-wide, so the sidebar never sees it:
            // its type-select jumped to "Untitled Collection" (Jason,
            // 2026-09-26: "it's not supposed to jump at all").
            if event.charactersIgnoringModifiers?.lowercased() == "u", event.plainModifiers == [] {
                showRatings.toggle()
                return true
            }
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            if case .show(let id) = model.sidebar, let show = model.show(id), mode == .show,
               SlideActions.removeSelected(session: model.session(for: id), mutate: { action, change in
                   var s = show
                   change(&s)
                   model.update(s, undo: undoManager, action: action)
               }) {
                return true
            }
            if !(NSApp.keyWindow?.firstResponder is NSTableView), event.plainModifiers == [] {
                switch model.sidebar {
                case .show(let id): guard let s = model.show(id) else { return false }; confirmDelete = s
                case .collection(let id): guard let c = model.collection(id) else { return false }; deleteCollectionAsking(c)
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
        // Item 3, `ShowTools Feedback — Worklist for Next CC Session.md`:
        // clicking the library pane's background shouldn't do anything — a
        // plain `List(selection:)` clears its selection to nil on a
        // background click, and `detailView`'s `default` case for a nil
        // sidebar is the plain Library grid, so a stray background click
        // was silently switching out of whatever the detail pane was
        // showing. There's always something to have selected here (the
        // Library row itself is selectable), so a nil write from that
        // background click is simply ignored rather than accepted.
        List(selection: Binding(get: { model.sidebar }, set: { if let s = $0 { model.sidebar = s } })) {
            // An alternate library shows its own name here.
            Label(model.isOnMaster ? "Library" : model.libraryName,
                  systemImage: model.libraryIsPrivate || model.locked != nil
                      ? "lock.rectangle.stack" : "photo.on.rectangle.angled")
                .badge(model.items.count)
                .tag(SidebarItem.library)
                .contextMenu {
                    Button("Import…") { runImportPanel(model) }
                    Button("New Collection…") { startCreatingCollection() }
                    Button("Open Library Panel") { LibraryPanel.show(model: model, undoManager: undoManager) }
                    Divider()
                    Button("Show in Finder") {
                        if let root = model.library?.root {
                            NSWorkspace.shared.activateFileViewerSelecting([root])
                        }
                    }
                    Divider()
                    // Item 28, `ShowTools Feedback — Worklist for Next CC
                    // Session.md`: the library header's own right-click had
                    // no way to switch libraries. Same action as File ▸
                    // Open Library….
                    Button("Change Library…") { runOpenLibraryPanel(model) }
                }

            // Library → Collection → Show, as Final Cut's Library → Event → Project.
            // A collection's groups and its shows sit side by side, as
            // siblings (Jason, 2026-09-24, "Groups inside collections").
            Section {
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
            } header: {
                Text("Collections")
                    .noMenuYet("Library pane › Collections heading")
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
            case .collection(let id): if let c = model.collection(id) { deleteCollectionAsking(c) }
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

    /// The timeline pane's content: PaneKit's "storyline" pane, full width
    /// under the Library pane too — not just the detail column, which is
    /// all `EditShowView`'s own three columns could ever give it
    /// (`EditShowTimelinePane`, `spec/panekit.md`, "The order," step 5's
    /// follow-up, 2026-09-25). Reads the same `ShowSession`/`AppModel`
    /// state `ShowView`/`EditShowView` do, rather than either of them
    /// handing this view something already built: writing to
    /// `@Observable` state from one view's `body` for another to read in
    /// the same update pass is the same class of trap SwiftUI's "don't
    /// mutate state during a view update" rule exists for.
    private var timelinePane: some View {
        Group {
            if case .show(let id) = model.sidebar, let show = model.show(id) {
                // Rendered in both modes now (feedback item 19): Edit Slides
                // shows the same bar, greyed out, rather than the pane
                // vanishing and the window reflowing under it.
                EditShowTimelinePane(show: show, timeline: model.timeline(for: show),
                                     session: model.session(for: id), active: mode == .show,
                                     mutate: { action, change in
                                         var s = show
                                         change(&s)
                                         model.update(s, undo: undoManager, action: action)
                                     })
            } else {
                Color.clear
            }
        }
    }

    /// Whether a show is open at all — `layout` uses this to open/close
    /// the timeline pane's split. Open for both edit modes now (item 19,
    /// feedback worklist): Edit Slides shows the same bar, greyed out
    /// (`timelinePane`, `EditShowTimelinePane.active`), rather than the
    /// split closing and reopening as the mode picker is clicked. Only
    /// leaving the show entirely — back to the Library or a collection —
    /// closes it.
    private var isShowOpen: Bool {
        if case .show(let id) = model.sidebar { return model.show(id) != nil }
        return false
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

    /// Item 32, `ShowTools Feedback — Worklist for Next CC Session.md`:
    /// ⌥-click a sidebar name to jump straight into its rename alert,
    /// skipping the right-click menu. A `.simultaneousGesture`, not
    /// `.onTapGesture` — the latter would steal the plain click a
    /// `List(selection:)` row needs for its own selection (the same class
    /// of trap `.onDrag` on a List row is, `showtools-gotchas`).
    private func renameOnOptionClick(_ item: SidebarItem, current: String) -> some Gesture {
        TapGesture().onEnded {
            if NSEvent.modifierFlags.contains(.option) { startRenaming(item, current: current) }
        }
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
        let (ok, alsoFromLibrary) = GroupDeleteNotice.confirm(name: g.name, subgroupCount: subgroupCount(of: g.id))
        guard ok else { return }
        if alsoFromLibrary { model.deleteItems(g.itemIDs, undo: undoManager) }
        model.deleteGroup(g.id, undo: undoManager)
    }

    /// Item 16, `ShowTools Feedback — Worklist for Next CC Session.md`:
    /// replaces the old `.confirmationDialog` (which can't carry a
    /// checkbox) with `CollectionDeleteNotice`'s NSAlert, the same
    /// synchronous shape `deleteGroupAsking` already uses.
    private func deleteCollectionAsking(_ c: MediaCollection) {
        let showCount = model.shows.filter { $0.collectionID == c.id }.count
        let (ok, alsoFromLibrary) = CollectionDeleteNotice.confirm(name: c.name, showCount: showCount)
        guard ok else { return }
        if alsoFromLibrary { model.deleteItems(c.itemIDs, undo: undoManager) }
        model.deleteCollection(c.id, undo: undoManager)
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
        // Solid folder for a collection, outline for a group inside it
        // (`groupRow`, below) — settled 2026-09-25, feedback item 12.
        Label(c.name, systemImage: "folder.fill")
            .badge(c.itemIDs.count)
            .tag(SidebarItem.collection(c.id))
            .contextMenu {
                Button("New Show in “\(c.name)”") { model.newShow(in: c.id) }
                Button("New Group in “\(c.name)”…") { startCreatingGroup(collectionID: c.id) }
                Divider()
                Button("Rename…") { startRenaming(.collection(c.id), current: c.name) }
                Button("Delete Collection…") { deleteCollectionAsking(c) }
            }
            .simultaneousGesture(renameOnOptionClick(.collection(c.id), current: c.name))
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
            .simultaneousGesture(renameOnOptionClick(.group(g.id), current: g.name))
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
            .simultaneousGesture(renameOnOptionClick(.show(show.id), current: show.name))
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
    /// Set when this grid is hosted outside the main window (`LibraryPanel`):
    /// `\.undoManager` isn't writable in the environment, and a separate
    /// window's own `undoManager` isn't the main window's (the same gotcha
    /// `InfoPanel`'s content works around), so the panel passes the shared
    /// one in directly instead.
    var undoManagerOverride: UndoManager? = nil
    /// Set only for the library panel's own instance (`LibraryPanel`): it
    /// shows the whole, unfiltered library, so it's the one place Show in
    /// Library's target is always visible. The main window's grid ignores
    /// `model.libraryFocusRequest` — it might be filtered to a collection
    /// that doesn't contain the file.
    var respondsToLibraryFocus: Bool = false
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var envUndoManager
    private var undoManager: UndoManager? { undoManagerOverride ?? envUndoManager }
    @State private var selection: Set<Int64> = []
    @State private var search = ""
    @AppStorage("gridKind") private var kind: KindFilter = .all
    @AppStorage("gridMinRating") private var minRating = 0
    /// View ▸ Show Ratings (U, Aperture's Browser key): every grid and the
    /// browser share it.
    @AppStorage("showRatings") private var showRatings = true
    @AppStorage("gridUncollected") private var onlyUncollected = false
    @AppStorage("gridSort") private var sort: SortOrder = .added
    /// The file(s) a drag picked up, set the moment the drag starts
    /// (`startDrag(from:)`) and cleared when `dragSource` says it ended.
    @State private var draggingIDs: [Int64] = []
    /// Starts drags as a flocking stack, and says when one ended
    /// (`StackDragSource`). One per grid, behind it.
    @State private var dragSource = StackDragSource()
    /// A drag has begun from this tile press; the gesture keeps reporting
    /// changes until the button comes up, so this stops a second start.
    @State private var dragStarted = false
    /// A drop was accepted and its reorder is about to be applied
    /// (`commitReorder`): the drag's end mustn't clear the gap first.
    @State private var commitPending = false
    /// Each visible tile's frame in the grid (`TileFramesKey`): where each
    /// dragged file's picture flies from, and the cell size for `slot(at:)`.
    @State private var tileFrames: [Int64: CGRect] = [:]
    /// Just-dropped files, drawn this far from their new slots — at the
    /// drop point — then sprung home: the stack spreading back out into
    /// the grid (Jason, 2026-09-25).
    @State private var landingOffsets: [Int64: CGSize] = [:]
    /// Where in the pile's top card the drag was grabbed: the pile is drawn
    /// that far from the pointer, so the landing starts from there too.
    @State private var grabOffset: CGSize = .zero
    /// The other files' pictures flying into the pile as a drag starts,
    /// and whether they've reached it (`startDrag(from:)`).
    @State private var flyers: [Flyer] = []
    @State private var landed = false
    /// Where a drag came from, to put its files back if it's cancelled or
    /// refused: the pressed file, each file's card, and the pile's home.
    @State private var dragHome: DragHome?
    struct DragHome {
        /// The files in pile order, the pressed one first.
        let order: [Int64]
        let cards: [Int64: NSImage]
        let card: CGSize
    }
    /// Files flying back to their tiles after a cancelled or refused drag:
    /// their tiles stay hidden until their cards arrive.
    @State private var returning: Set<Int64> = []
    /// Where the gap is while a drag-to-reorder is over the grid: the slot
    /// the dragged file(s) would land in, worked out from the cursor's
    /// position alone (`Reorder.slot`). Nil when no drag is over the grid.
    @State private var gapIndex: Int?
    /// The grid's own width, measured, for `slot(at:)`.
    @State private var gridContentWidth: CGFloat = 0
    /// The scroll area's height, so the drop area reaches its bottom even
    /// when there are only a few tiles.
    @State private var viewportHeight: CGFloat = 0
    /// Why a drag over this grid can't reorder it, shown while it's there.
    @State private var reorderBlockedReason: String?
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
        case custom, added, addedNewest, name, rating
        var title: String {
            switch self {
            case .custom: "Custom Order"
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
    /// The grid's own on-screen width, measured for `columnCount` (B2):
    /// `.adaptive` columns don't expose their count any other way.
    @State private var gridWidth: CGFloat = 0
    /// Which viewer drawer is this grid's (the main window's, or the
    /// library panel's), and its Side by Side / Stack choice.
    private let viewerPlace: ViewerPlace
    @AppStorage private var viewerMode: ViewerMode
    /// The tile size when a pinch began (`spec/conventions.md` §1).
    @State private var pinchStart: Double?
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
    /// The thumbnail-size slider's own range. At its smallest, the grid
    /// becomes a single-column list with a small icon per row (Jason,
    /// 2026-09-24) rather than a row of tiny tiles.
    static let tileSizeRange: ClosedRange<Double> = 90...320
    private var isListMode: Bool { tileSize <= Self.tileSizeRange.lowerBound }
    /// The grid's coordinate space for drag-to-reorder.
    static let gridSpace = "reorderGrid"

    /// A custom init only to give `tileSize` its own storage key per
    /// caller — every other property keeps the default it's declared
    /// with. Without this, the library panel's slider and the main
    /// window's grid shared one `@AppStorage` key, so dragging either
    /// moved both windows together; Jason wanted them independent
    /// (2026-09-24), e.g. list in the panel, medium in the main window.
    init(collectionID: Int64? = nil, groupID: Int64? = nil, undoManagerOverride: UndoManager? = nil,
         tileSizeKey: String = "gridTileSize", respondsToLibraryFocus: Bool = false) {
        let place: ViewerPlace = tileSizeKey == "gridTileSize.panel" ? .libraryPanel : .library
        self.viewerPlace = place
        _viewerMode = AppStorage(wrappedValue: .sideBySide, place.modeKey)
        self.collectionID = collectionID
        self.groupID = groupID
        self.undoManagerOverride = undoManagerOverride
        self.respondsToLibraryFocus = respondsToLibraryFocus
        _tileSize = AppStorage(wrappedValue: 150, tileSizeKey)
    }

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

    /// `visible`, while a drag-to-reorder is over the grid: the dragged
    /// file(s) moved to `gapIndex`, where `tile(_:)` draws them as empty
    /// space. That gap is the "here's where it lands" signal (Jason's
    /// design, 2026-09-25), and a drop saves exactly this order.
    private var displayed: [MediaItem] {
        guard let gap = gapIndex, !draggingIDs.isEmpty else { return visible }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Reorder.moving(Set(draggingIDs), in: visible.map(\.id), to: gap).compactMap { byID[$0] }
    }

    /// Why this grid can't be reordered by dragging right now, or nil if it can.
    private var reorderBlocked: String? {
        if collectionID == nil && groupID == nil {
            return "To reorder, open a collection or group. The Library itself has no order of its own."
        }
        if similarActive { return "Reordering is off while Show Similar is on." }
        return nil
    }

    /// The slot under a point in the drop area (`scrollingGrid`'s padded
    /// grid), for a block of `draggingIDs` — geometry only (`Reorder.slot`).
    private func slot(at p: CGPoint) -> Int? {
        guard let g = gridGeometry else { return nil }
        let block = visible.filter { draggingIDs.contains($0.id) }.count
        return Reorder.slot(x: p.x - g.pad, y: p.y - g.pad, columns: g.columns, pitchX: g.pitch.width,
                            pitchY: g.pitch.height, count: visible.count, blockSize: block)
    }

    /// The grid's layout, from a measured tile: its columns, the distance
    /// from one cell to the next, a cell's size, and the padding round it.
    private var gridGeometry: (columns: Int, pitch: CGSize, cell: CGSize, pad: CGFloat)? {
        guard let cell = tileFrames.values.first?.size, cell.width > 0, cell.height > 0 else { return nil }
        let spacing: CGFloat = 10
        let pitch = CGSize(width: cell.width + spacing, height: cell.height + spacing)
        let columns = isListMode ? 1 : max(1, Int(((gridContentWidth + spacing) / pitch.width).rounded()))
        return (columns, pitch, cell, 12)
    }

    /// The top-left corner of slot `k`, in the grid's space.
    private func slotOrigin(_ k: Int, _ g: (columns: Int, pitch: CGSize, cell: CGSize, pad: CGFloat)) -> CGPoint {
        CGPoint(x: g.pad + CGFloat(k % g.columns) * g.pitch.width,
                y: g.pad + CGFloat(k / g.columns) * g.pitch.height)
    }

    /// A tile press became a drag: the file, or the whole selection if it's
    /// selected, as a tidy pile under the pointer (`StackDragSource`), the
    /// pressed file on top. The other files' pictures fly from their own
    /// tiles into the pile (`flyers`); one scrolled out of view just joins
    /// it. In list mode each card is a short row, not the full width, kept
    /// under the pointer. Only plain state changes here — rebuilding the
    /// grid as a drag starts (switching the sort, tried 2026-09-25) tore it down.
    private func startDrag(from id: Int64) {
        guard !dragStarted, let event = NSApp.currentEvent,
              let pressed = tileFrames[id] else { return }
        dragStarted = true
        let ids = selection.contains(id) ? orderedSelection : [id]
        let order = [id] + ids.filter { $0 != id }
        let grab = dragSource.convert(event.locationInWindow, from: nil)
        let card = CGSize(width: isListMode ? min(pressed.width, 320) : pressed.width, height: pressed.height)
        let cardOrigin = CGPoint(x: isListMode ? max(pressed.minX, grab.x - (card.width - 40)) : pressed.minX,
                                 y: pressed.minY)
        let images = order.map { i in model.itemsByID[i].map { dragImage($0, size: card) } ?? NSImage(size: card) }

        let layers = min(order.count, StackDragSource.pileDepth)
        let step = StackDragSource.pileStep(layers: layers)
        var flying: [Flyer] = []
        for (k, i) in order.enumerated() where k > 0 {
            guard let from = tileFrames[i] else { continue }
            let depth = CGFloat(min(k, layers - 1)) * step
            flying.append(Flyer(id: i, image: images[k],
                                from: CGRect(origin: CGPoint(x: isListMode ? cardOrigin.x : from.minX, y: from.minY), size: card),
                                to: CGRect(origin: CGPoint(x: cardOrigin.x + depth, y: cardOrigin.y + depth), size: card)))
        }

        let pile = StackDragSource.pileImage(images, size: card, count: order.count)
        let badge = StackDragSource.badgeRoom(count: order.count)
        let writer = NSPasteboardItem()
        writer.setData((try? JSONEncoder().encode(ids)) ?? Data(),
                       forType: NSPasteboard.PasteboardType(ItemDrag.type.identifier))

        draggingIDs = ids
        dragHome = DragHome(order: order, cards: Dictionary(uniqueKeysWithValues: zip(order, images)),
                            card: card)
        grabOffset = CGSize(width: grab.x - cardOrigin.x, height: grab.y - cardOrigin.y)
        dragSource.onEnd = { end in
            dragStarted = false
            let home = dragHome, ids = draggingIDs
            dragHome = nil
            guard !commitPending else { return }
            endReorderDrag()
            // Nothing took the files (cancelled, refused, let go nowhere):
            // put them back where they were (`putBack`).
            guard end.operation.isEmpty else { return }
            if let home { putBack(ids, from: home, at: end.point) }
            // Let go over the plain Library's own grid, where there's no
            // order to set: say why nothing moved (`LibraryOrderNotice`),
            // once the files are back. Not for Escape — nothing was let go
            // anywhere, so there's nothing to explain (Jason, 2026-09-25).
            if end.overView, !end.escaped, collectionID == nil, groupID == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { LibraryOrderNotice.show() }
            }
        }
        // Edge scrolling moves the grid under a still pointer: the gap
        // follows, while the drag is over the grid at all.
        dragSource.onAutoscroll = { p in
            guard gapIndex != nil, reorderBlocked == nil, let s = slot(at: p), s != gapIndex else { return }
            gapIndex = s
        }
        dragSource.begin(image: pile, frame: CGRect(x: cardOrigin.x, y: cardOrigin.y - badge,
                                                    width: pile.size.width, height: pile.size.height),
                         writer: writer, event: event)
        // The fly-in: each picture glides from its tile to its place in
        // the pile, and is gone as it arrives — the pile the pointer is
        // carrying already shows it.
        landed = false
        flyers = flying
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) { landed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { flyers = [] }
        }
    }

    /// One picture flying into the drag's pile as the drag starts.
    struct Flyer: Identifiable {
        let id: Int64
        let image: NSImage
        let from: CGRect
        let to: CGRect
        /// Fades as it arrives (the fly-in, into a pile that already shows
        /// it) or stays solid (the put-back, where its tile takes over).
        var fades = true
    }

    /// A drag nothing took (cancelled, refused, let go nowhere): the pile
    /// comes apart where it was let go and each card flies to its own
    /// file's tile, while the grid closes the gap — the landing in reverse
    /// ("you realize you didn't mean to drag these", Jason, 2026-09-25).
    /// Their tiles show again as the cards land. Files scrolled out of view
    /// just reappear.
    private func putBack(_ ids: [Int64], from home: DragHome, at point: CGPoint) {
        guard let g = gridGeometry else { return }
        let order = visible.map(\.id)
        let pileOrigin = CGPoint(x: point.x - grabOffset.width, y: point.y - grabOffset.height)
        let layers = min(home.order.count, StackDragSource.pileDepth)
        let step = StackDragSource.pileStep(layers: layers)
        var flying: [Flyer] = []
        for (n, id) in home.order.enumerated() where ids.contains(id) {
            guard let k = order.firstIndex(of: id), let image = home.cards[id] else { continue }
            let depth = CGFloat(min(n, layers - 1)) * step
            flying.append(Flyer(id: id, image: image,
                                from: CGRect(origin: CGPoint(x: pileOrigin.x + depth, y: pileOrigin.y + depth),
                                             size: home.card),
                                to: CGRect(origin: slotOrigin(k, g), size: home.card),
                                fades: false))
        }
        guard !flying.isEmpty else { return }
        returning = Set(flying.map(\.id))
        landed = false
        flyers = flying
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.28)) { landed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                flyers = []
                returning = []
            }
        }
    }

    /// A dragged file's picture: its thumbnail as the tile shows it, or in
    /// list mode a row with the name.
    private func dragImage(_ item: MediaItem, size: CGSize) -> NSImage {
        let thumb = Thumbnails.shared.cached(item.id)
        let list = isListMode
        return NSImage(size: size, flipped: true) { r in
            func fit(_ img: NSImage, in box: CGRect) -> CGRect {
                let s = min(box.width / max(img.size.width, 1), box.height / max(img.size.height, 1))
                let w = img.size.width * s, h = img.size.height * s
                return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
            }
            // Solid cards: in a pile, a see-through card shows the name on
            // the one beneath it through its own.
            let card = NSBezierPath(roundedRect: list ? r : CGRect(x: 0, y: 0, width: r.width, height: min(r.width, r.height)),
                                    xRadius: 4, yRadius: 4)
            NSColor.windowBackgroundColor.setFill()
            card.fill()
            if list {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                card.fill()
                let box = CGRect(x: 6, y: (r.height - 28) / 2, width: 28, height: 28)
                if let thumb {
                    thumb.draw(in: fit(thumb, in: box), from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
                }
                (item.fileName as NSString).draw(
                    at: CGPoint(x: box.maxX + 8, y: (r.height - 15) / 2),
                    withAttributes: [.font: NSFont.preferredFont(forTextStyle: .callout),
                                     .foregroundColor: NSColor.labelColor])
            } else {
                let box = CGRect(x: 0, y: 0, width: r.width, height: min(r.width, r.height))
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
                if let thumb {
                    thumb.draw(in: fit(thumb, in: box), from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
                }
            }
            return true
        }
    }

    /// A drop: saves what's on screen (`displayed`) as the collection's or
    /// group's Custom Order. Files a search or filter is hiding keep their
    /// places (`Reorder.merge`). Switches the sort to Custom Order, so the
    /// order that was just made is what shows, and says so once
    /// (`CustomOrderNotice`). Applied a moment later, all in one go, so
    /// nothing is rebuilt inside the drag's own callback and the gap holds
    /// until the new order replaces it. The dropped files then spring from
    /// the drop point into their slots — the stack spreading back out.
    private func commitReorder(at point: CGPoint) {
        let shown = displayed.map(\.id)
        let order = Reorder.merge(shown, into: all.map(\.id))
        let gid = groupID, cid = collectionID, undo = undoManager
        // Each dropped file starts where the stack was drawn — the pointer,
        // less where the tile was grabbed — and springs to its slot.
        var offsets: [Int64: CGSize] = [:]
        if let g = gridGeometry {
            let stackOrigin = CGPoint(x: point.x - grabOffset.width, y: point.y - grabOffset.height)
            for (k, id) in shown.enumerated() where draggingIDs.contains(id) {
                let slot = slotOrigin(k, g)
                offsets[id] = CGSize(width: stackOrigin.x - slot.x, height: stackOrigin.y - slot.y)
            }
        }
        commitPending = true
        dragSource.hideImages()
        DispatchQueue.main.async {
            let switched = sort != .custom
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { landingOffsets = offsets }
            sort = .custom
            // Its own undo group: registered outside any event (this runs
            // after the drop), the step would sit in an automatic group
            // that stays open until the next event, so Edit ▸ Undo stayed
            // disabled and the first ⌘Z only closed the group (measured
            // 2026-09-25). Closing it here tells `UndoMenuState` now.
            undo?.beginUndoGrouping()
            if let gid {
                model.setOrder(order, inGroup: gid, undo: undo)
            } else if let cid {
                model.setOrder(order, inCollection: cid, undo: undo)
            }
            undo?.endUndoGrouping()
            commitPending = false
            endReorderDrag()
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { landingOffsets = [:] }
                if switched { CustomOrderNotice.show() }
            }
        }
    }

    private func endReorderDrag() {
        if !draggingIDs.isEmpty { draggingIDs = [] }
        if gapIndex != nil { gapIndex = nil }
        if reorderBlockedReason != nil { reorderBlockedReason = nil }
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
                && Rating.Filter.matches(item.rating, filter: minRating)
                && !(onlyUncollected && collection == nil && collected.contains(item.id))
        }
        switch effectiveSort {
        case .custom: return shown
        case .added: return shown.sorted { addedAt($0.id) < addedAt($1.id) }
        case .addedNewest: return shown.sorted { addedAt($0.id) > addedAt($1.id) }
        case .name: return shown.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        case .rating: return shown.sorted { $0.rating > $1.rating }
        }
    }

    /// The sort actually in use. `sort` is shared by every grid, and Custom
    /// Order is only a collection's or group's own (schema 14): the plain
    /// Library has no order of its own and shows its files in the order
    /// they were added, so there Custom Order reads as Date Added — in the
    /// strip and the Sort menu's checkmark alike (it read "Custom Order"
    /// before, 2026-09-25).
    private var effectiveSort: SortOrder {
        sort == .custom && collection == nil && group == nil ? .added : sort
    }

    /// When a file joined the group or collection in view — a group's or
    /// collection's own `addedAt`, kept apart from `itemIDs`' drag order
    /// (schema 14) so reordering by hand doesn't also rewrite Date Added.
    /// The plain Library has no such membership, so it falls back to the
    /// file's own `ingestedAt` (`allItems()` is already in that order).
    private func addedAt(_ id: Int64) -> Double {
        if let g = group { return g.addedAt[id] ?? 0 }
        if let c = collection { return c.addedAt[id] ?? 0 }
        return model.itemsByID[id]?.ingestedAt.timeIntervalSince1970 ?? 0
    }

    private var filtering: Bool {
        kind != .all || Rating.Filter.isActive(minRating) || (onlyUncollected && collection == nil)
    }

    /// Search, filters and sort, and the tools, over the grid (and under
    /// the viewer drawer, whose handle it is). One row where there's room;
    /// in a narrow window (the library panel) two, with the filters as
    /// icons — the first layout that fits (Jason, 2026-09-26, after the
    /// tools moved down from the toolbar and overflowed the panel).
    private var bar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                barFinding(compact: false)
                Spacer(minLength: 10)
                barTools
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { barFinding(compact: true) }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    barTools
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// Search, Filter, Sort and Similar; `compact` shows the last three as icons.
    @ViewBuilder private func barFinding(compact: Bool) -> some View {
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
        .frame(minWidth: 120, maxWidth: 260)

        Menu {
            Picker("Kind", selection: $kind) {
                ForEach(KindFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            RatingFilterPicker(selection: $minRating)
            if collection == nil {
                Divider()
                Toggle("Not in Any Collection", isOn: $onlyUncollected)
            }
        } label: {
            Label("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill"
                                                   : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .fixedSize()
        .foregroundStyle(filtering ? Color.accentColor : .primary)

        Menu {
            // Custom Order is a group's or collection's own drag order
            // (schema 14) — the plain Library has no such thing to show.
            Picker("Sort", selection: Binding(get: { effectiveSort }, set: { sort = $0 })) {
                ForEach(SortOrder.allCases.filter { $0 != .custom || group != nil || collection != nil },
                        id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .fixedSize()

        Button {
            grouping.toggle()
            similarTo = nil
        } label: {
            Label("Similar", systemImage: grouping ? "square.stack.3d.up.fill" : "square.stack.3d.up")
        }
        .buttonStyle(.borderless)
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .foregroundStyle(grouping ? Color.accentColor : .primary)
        .help("Find Similar Images: look-alike pictures together")
        if similarActive { similarControls }
    }

    /// The count, the tools once in the toolbar, and the tile size.
    @ViewBuilder private var barTools: some View {
        if visible.count != all.count {
            Text("\(visible.count) of \(all.count)").foregroundStyle(.secondary).monospacedDigit()
        }
        // The toolbar's tools and the tile size, here under the viewer
        // drawer rather than in the toolbar (Jason, 2026-09-26: "move
        // the whole set of tools down"). Controls keep their own clicks
        // and drags; only the bar's empty space moves the drawer.
        Button { runImportPanel(model) } label: { Image(systemName: "square.and.arrow.down") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Import")
            .help("Import files or folders")
        addToShowMenu(ids: orderedSelection)
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(selection.isEmpty)
        Button { showGetInfo() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Get Info")
            .help("Show info and tags for the selection (⌘I)")
            .disabled(selection.isEmpty)
        Slider(value: $tileSize, in: Self.tileSizeRange).frame(width: 100)
            .help(isListMode ? "Thumbnail size (list view)" : "Thumbnail size")
    }

    /// Its own strip, separate from `bar`'s Sort menu (Jason, 2026-09-25):
    /// which sort is active — Custom Order most of all, since dragging to
    /// reorder switches to it on its own (`commitReorder`) and it's easy to
    /// lose track of which view you're in without opening the menu to check.
    ///
    /// Also the viewer drawer's second handle, with the edge handles' pill
    /// drawn in its middle (Jason, 2026-09-26: the darker strip read as
    /// the grip). It moves with the bar above it, as the drawer's edge.
    /// The handle sits above the strip's colour, which would otherwise
    /// take the clicks.
    private var sortStatusBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down").imageScale(.small)
            Text(effectiveSort.title)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 4)
        // Nothing here is clickable, and SwiftUI's text takes the mouse
        // (measured: a double-click on "Date Added…" did nothing), so the
        // whole strip is the handle.
        .allowsHitTesting(false)
        .overlay {
            Capsule()
                .fill(Color(nsColor: .secondaryLabelColor).opacity(0.7))
                .frame(width: 40, height: 3)
                .allowsHitTesting(false)
        }
        .paneHandle(model.viewer(viewerPlace), split: ViewerLayout.split)
        .background(Color(nsColor: .controlBackgroundColor))
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
                // The viewer drawer above the grid, its handle the bar
                // (`spec/plan.md`, "The viewer drawer"): closed, the bar
                // sits at the top as it always has.
                let viewer = model.viewer(viewerPlace)
                PaneLayoutView(controller: viewer, content: [
                    "viewer": AnyView(SelectionViewer(
                        items: orderedSelection.compactMap { model.itemsByID[$0] },
                        primary: cursor, mode: $viewerMode, model: model)),
                    "grid": AnyView(VStack(spacing: 0) {
                        bar.paneHandle(viewer, split: ViewerLayout.split)
                        Divider()
                        sortStatusBar
                        Divider()
                        grid
                    }
                    .environment(model)),
                ])
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
        .onChange(of: navScope) {
            selection = []; anchor = nil; selectionBase = []; cursor = nil; similarTo = nil
            endReorderDrag()
        }
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
        // Delete by context (plan, Phase 3b; Photos' convention). In the
        // Library: Delete asks, then Trash; ⌘Delete skips the question. In a
        // collection: Delete takes them out of it (undoable); ⌘Delete deletes
        // them from the library, and asks first.
        // Delete, ⌘Delete, ⌘A (Select All, audit A1), the arrow keys (B2)
        // and Return (rename, B6) are all taken here, before AppKit,
        // rather than through SwiftUI focus: a click on a tile never gave
        // the grid the keyboard (Jason's click and axtool's alike,
        // 2026-09-22; setting the focus on click, and moving the handlers,
        // didn't change it). ⌘Y (Quick Look, B5) is a real menu shortcut
        // instead — see `requestLibraryQuickLook`, below — since it still
        // has to work while the Quick Look panel itself, a different
        // window, is key.
        // Not while text is edited (SingleKeys), not while a list (the
        // sidebar) has the keyboard.
        .background(SingleKeys { event in
            // Item 20: the rating keys rate the selected tiles even while
            // the sidebar has the keyboard (a tile click doesn't take it),
            // rather than going to the sidebar's type-select.
            if event.plainModifiers == [], let c = event.charactersIgnoringModifiers,
               let key = Rating.Key(c), !orderedSelection.isEmpty {
                model.applyRatingKey(key, to: orderedSelection, undo: undoManager)
                return true
            }
            // The viewer drawer: Y opens and closes it, ⇧Y switches Side by
            // Side / Stack — ahead of the sidebar check, like the rating
            // keys, so the sidebar's type-select never takes them. With it
            // open and several selected, ← / → move the outline within the
            // selection instead of changing it (Jason, Aperture's multi-up).
            if event.charactersIgnoringModifiers?.lowercased() == "y" {
                switch event.plainModifiers {
                case []: model.viewer(viewerPlace).toggle(ViewerLayout.split); return true
                case [.shift]: viewerMode = viewerMode.other; return true
                default: break
                }
            }
            if model.viewer(viewerPlace).isOpen(ViewerLayout.split), selection.count > 1,
               event.plainModifiers == [], event.keyCode == 123 || event.keyCode == 124 {
                cursor = Viewer.step(orderedSelection, from: cursor, by: event.keyCode == 123 ? -1 : 1)
                return true
            }
            guard !(NSApp.keyWindow?.firstResponder is NSTableView) else { return false }
            if event.keyCode == 0, event.plainModifiers == [.command] {
                guard !visible.isEmpty else { return false }
                selection = Set(visible.map(\.id))
                selectionBase = selection
                return true
            }
            switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased(), event.plainModifiers) {
            case (51, _, []), (117, _, []):
                guard !selection.isEmpty else { return false }
                if let gid = groupID { removeFromGroup(orderedSelection, gid) }
                else if let cid = collectionID { removeFromCollection(orderedSelection, cid) }
                else { requestDelete(orderedSelection, confirm: true) }
            case (51, _, [.command]), (117, _, [.command]):
                guard !selection.isEmpty else { return false }
                requestDelete(orderedSelection, confirm: collectionID != nil)
            case (123, _, []): guard moveSelection(-1, extend: false) else { return false }        // ←
            case (123, _, [.shift]): guard moveSelection(-1, extend: true) else { return false }
            case (124, _, []): guard moveSelection(1, extend: false) else { return false }          // →
            case (124, _, [.shift]): guard moveSelection(1, extend: true) else { return false }
            case (126, _, []): guard moveSelection(-columnCount, extend: false) else { return false } // ↑
            case (126, _, [.shift]): guard moveSelection(-columnCount, extend: true) else { return false }
            case (125, _, []): guard moveSelection(columnCount, extend: false) else { return false }  // ↓
            case (125, _, [.shift]): guard moveSelection(columnCount, extend: true) else { return false }
            case (36, _, []):
                guard !orderedSelection.isEmpty else { return false }
                renameIDs = orderedSelection
            // Item 20: U, for the library panel's own window (the main
            // window's is MainView's, window-wide). The rating keys are
            // above, ahead of the sidebar check.
            case (_, "u"?, []):
                showRatings.toggle()
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
        .focusedSceneValue(\.requestLibraryQuickLook, {
            guard let first = orderedSelection.first else { return }
            quickLook(startingAt: first)
        })
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
        let columns = isListMode
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.4), spacing: 10)]
        return ScrollViewReader { proxy in scrollingGrid(columns: columns, proxy: proxy) }
    }

    private func scrollingGrid(columns: [GridItem], proxy: ScrollViewProxy) -> some View {
        ScrollView {
            // One space for the tiles' frames, the drag source and the
            // reorder drop's location, so all three agree. Around both
            // layouts: a Find Similar tile still drags onto a collection
            // or a show.
            VStack(spacing: 0) { gridContent(columns: columns) }
                .coordinateSpace(name: Self.gridSpace)
                .background(StackDragAnchor(source: dragSource))
                .overlay(alignment: .topLeading) { flyerLayer }
                .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .background(GeometryReader { g in
            Color.clear.onAppear { gridWidth = g.size.width; viewportHeight = g.size.height }
                .onChange(of: g.size.width) { _, w in gridWidth = w }
                .onChange(of: g.size.height) { _, h in viewportHeight = h }
        })
        .overlay(alignment: .bottom) {
            if let reason = reorderBlockedReason {
                Text(reason)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        // Item 4, `ShowTools Feedback — Worklist for Next CC Session.md`:
        // no right-click response anywhere in the main window's background
        // areas. The near-invisible background above already makes this
        // whole scroll area hit-testable (it's what the background tap-to-
        // deselect gesture below uses); a plain `.contextMenu` on it gives
        // a right-click on empty grid space something to answer with.
        .contextMenu {
            Button("Import…") { runImportPanel(model) }
            Button("New Collection…") { startCreatingCollection(with: []) }
            if collectionID != nil {
                Button("Add from Library…") { addingFromLibrary = true }
            }
        }
        .onChange(of: cursor) { _, id in
            guard let id else { return }
            withAnimation { proxy.scrollTo(id, anchor: nil) }
        }
        .onTapGesture { selection = []; focused = true }
        // Pinch changes the tile size, the same as the size slider, down
        // to its list view (Jason, 2026-09-25). Simultaneous, so the
        // scroll view still scrolls.
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                let start = pinchStart ?? tileSize
                pinchStart = start
                tileSize = min(max(start * v.magnification, Self.tileSizeRange.lowerBound),
                               Self.tileSizeRange.upperBound)
            }
            .onEnded { _ in pinchStart = nil })
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
        // Show in Library (spec/conventions.md §3): only the library
        // panel's own instance answers — see `respondsToLibraryFocus`.
        // `onAppear` too: the request is set, then the panel is opened
        // (`showInLibrary`), so this view often mounts *after* the value
        // it needs to react to has already changed — `onChange` alone
        // never fires for a change that happened before the view existed.
        .onAppear { respondToLibraryFocus(model.libraryFocusRequest, proxy: proxy) }
        .onChange(of: model.libraryFocusRequest) { _, request in respondToLibraryFocus(request, proxy: proxy) }
    }

    /// The pictures flying into a drag's pile (`flyers`), over the grid.
    private var flyerLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(flyers) { f in
                let r = landed ? f.to : f.from
                Image(nsImage: f.image)
                    .frame(width: r.width, height: r.height)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: r.minX, y: r.minY)
                    .opacity(landed && f.fades ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// The grid's two layouts: Find Similar's clusters, or the plain grid
    /// with drag-to-reorder.
    @ViewBuilder private func gridContent(columns: [GridItem]) -> some View {
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
                ForEach(displayed) { item in
                    tile(item)
                }
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { gridContentWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in gridContentWidth = w }
            })
            .animation(.easeInOut(duration: 0.2), value: displayed.map(\.id))
            .padding(12)
            // The drop area for reordering: the whole grid, down to the
            // bottom of the scroll area, so dropping below the last row
            // means "at the end".
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
            .contentShape(Rectangle())
            .onDrop(of: [ItemDrag.type], delegate: ReorderDrop(
                type: ItemDrag.type,
                isOurs: { !draggingIDs.isEmpty },
                update: { p in
                    if let reason = reorderBlocked {
                        reorderBlockedReason = reason
                        return false
                    }
                    if let s = slot(at: p), s != gapIndex { gapIndex = s }
                    return true
                },
                exit: { gapIndex = nil; reorderBlockedReason = nil },
                perform: { p in commitReorder(at: p) }
            ))
            if similarTo != nil, visible.count <= 1 { similarEmpty }
        }
    }

    private func respondToLibraryFocus(_ request: LibraryFocusRequest?, proxy: ScrollViewProxy) {
        guard respondsToLibraryFocus, let id = request?.itemID else { return }
        selection = [id]
        focused = true
        withAnimation { proxy.scrollTo(id, anchor: .center) }
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
        return Group {
            if isListMode {
                HStack(spacing: 8) {
                    ThumbnailView(item: item, url: model.url(for: item))
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(item.fileName)
                        .font(.callout)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(selected ? .primary : .secondary)
                    Spacer(minLength: 0)
                    if showRatings { RatingBadge(rating: item.rating, font: .caption) }
                }
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
            } else {
                VStack(spacing: 4) {
                    ThumbnailView(item: item, url: model.url(for: item))
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
                    Text(item.fileName)
                        .font(.caption)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(selected ? .primary : .secondary)
                    // Its own line, a fixed height whether rated or not,
                    // so a row of tiles stays level.
                    // (A frame on the badge alone collapses when it draws
                    // nothing, so the line is a clear spacer it sits on.)
                    if showRatings {
                        Color.clear.frame(height: 11).overlay { RatingBadge(rating: item.rating) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        // A file being dragged to reorder is the gap: plain empty space
        // where it would land (Jason, 2026-09-25). It stays in the grid,
        // only invisible, so the drag it started from is never torn down.
        .opacity((gapIndex != nil && draggingIDs.contains(item.id)) || returning.contains(item.id) ? 0 : 1)
        .background(GeometryReader { g in
            Color.clear.preference(key: TileFramesKey.self, value: [item.id: g.frame(in: .named(Self.gridSpace))])
        })
        // Just dropped: starts where the pile was, springs into its slot.
        .offset(landingOffsets[item.id] ?? .zero)
        // Double-click: "go into it" (conventions.md), settled as Quick
        // Look for a Library tile (B5, B6) now that Space is play/pause.
        .onTapGesture(count: 2) { click(item.id); quickLook(startingAt: item.id) }
        .onTapGesture { click(item.id) }
        // A selected tile drags the whole selection, as a stack; any other,
        // just itself (`startDrag(from:)`). Not `.onDrag`: it carries one
        // picture, so several files couldn't gather into a stack.
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in startDrag(from: item.id) }
            .onEnded { _ in dragStarted = false })
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

    /// How many tiles fit per row: `.adaptive(minimum: tileSize, maximum:
    /// tileSize * 1.4)` doesn't expose its own column count, so this works
    /// it out the same way SwiftUI does (B2) — fit as many `tileSize`-plus-
    /// spacing tiles as the measured width allows. A mismatch against
    /// SwiftUI's own rounding only changes which tile ↑ / ↓ lands on, not
    /// whether ← / → work.
    private var columnCount: Int {
        guard !isListMode else { return 1 }
        let spacing: CGFloat = 10
        return max(1, Int((gridWidth + spacing) / (tileSize + spacing)))
    }

    /// An arrow key (B2): steps the cursor by `delta` positions in the
    /// grid's own order, extending from the anchor with ⇧ exactly as a
    /// ⇧-click would (`GridSelection.step`). Returns false (so the event
    /// isn't swallowed) when there's nothing to move over.
    @discardableResult
    private func moveSelection(_ delta: Int, extend: Bool) -> Bool {
        let items = visible.map(\.id)
        guard !items.isEmpty else { return false }
        let r = GridSelection.step(from: cursor, by: delta, anchor: anchor, base: selectionBase,
                                    in: items, extend: extend)
        selection = r.selected
        anchor = r.anchor
        selectionBase = r.base
        cursor = r.cursor
        focused = true
        return true
    }

    /// Quick Look (B5, B6): ⌘Y, and double-clicking a tile. Steps through
    /// the current selection, starting on the one that was double-clicked
    /// or, from ⌘Y, the first of it.
    private func quickLook(startingAt id: Int64) {
        let ids = orderedSelection.isEmpty ? [id] : orderedSelection
        let urls = ids.compactMap { model.itemsByID[$0].flatMap { model.url(for: $0) } }
        guard !urls.isEmpty else { return }
        QuickLookController.shared.toggle(urls: urls, startAt: ids.firstIndex(of: id) ?? 0)
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

/// A label style chosen at run time (`LibraryGridView.bar`'s compact form).
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
