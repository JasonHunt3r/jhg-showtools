import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore

/// Types a drop onto the app can carry: files from Finder, file promises
/// (or data) from Photos.
let droppableTypes: [UTType] = [.fileURL, .image, .movie]

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
                Label("Library", systemImage: "photo.on.rectangle.angled")
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
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
            switch model.sidebar {
            case .show(let id) where model.show(id) != nil:
                ShowView(showID: id)
            case .collection(let id) where model.collection(id) != nil:
                LibraryGridView(collectionID: id)
            default:
                LibraryGridView()
            }
        }
        .overlay(alignment: .bottom) { ImportBanner() }
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
            Button("Delete Collection", role: .destructive) { model.deleteCollection(c.id) }
        } message: { c in
            let n = model.shows.filter { $0.collectionID == c.id }.count
            Text(n == 0 ? "The images stay in the library."
                 : "Its \(n == 1 ? "show" : "\(n) shows") will be deleted too. The images stay in the library.")
        }
        .alert(renamingTitle, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
            Button("Rename") {
                let name = draftName.trimmingCharacters(in: .whitespaces)
                switch renaming {
                case .collection(let id): model.renameCollection(id, to: name)
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
            Button("Delete Show", role: .destructive) { model.deleteShow(show.id) }
        } message: { _ in
            Text("The show's slide order and settings are deleted. The images stay in the library.")
        }
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
                Button("Play Full Screen") { Player.open(show: show, model: model, fullScreen: true) }
                Divider()
                Button("Rename…") { startRenaming(.show(show.id), current: show.name) }
                Button("Delete Show…") { confirmDelete = show }
            }
            // Dropping files on a show appends them to it (asking first about
            // any not in its collection).
            .onDrop(of: ItemDrag.accepted, isTargeted: nil) { providers in
                Task {
                    let ids = await model.itemIDs(from: providers)
                    model.append(ids, to: show.id)
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

/// The library's files, or one collection's.
struct LibraryGridView: View {
    /// Nil shows the whole library.
    var collectionID: Int64? = nil
    @Environment(AppModel.self) private var model
    @State private var selection: Set<Int64> = []
    @State private var anchor: Int64?
    @State private var dropTargeted = false
    @AppStorage("gridTileSize") private var tileSize: Double = 150

    private var collection: MediaCollection? { collectionID.flatMap(model.collection) }

    /// The files shown: the library's, or the collection's in the order they
    /// were added.
    private var visible: [MediaItem] {
        guard let c = collection else { return model.items }
        return c.itemIDs.compactMap { model.itemsByID[$0] }
    }

    var body: some View {
        Group {
            if let c = collection, visible.isEmpty {
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
                grid
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
        .onChange(of: collectionID) { selection = []; anchor = nil }
        .toolbar {
            ToolbarItemGroup {
                Slider(value: $tileSize, in: 90...320).frame(width: 100)
                    .help("Thumbnail size")
                Button { runImportPanel(model) } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import files or folders")
                addToShowMenu(ids: orderedSelection)
                    .disabled(selection.isEmpty)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.4), spacing: 10)],
                      spacing: 10) {
                ForEach(visible) { item in
                    tile(item)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { selection = [] }
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
        .contextMenu {
            let ids = selection.contains(item.id) ? orderedSelection : [item.id]
            Button("New Show from \(ids.count == 1 ? "Item" : "\(ids.count) Items")") {
                model.newShow(itemIDs: ids, in: collectionID)
            }
            addToShowMenu(ids: ids)
            Divider()
            Button("New Collection from \(ids.count == 1 ? "Item" : "\(ids.count) Items")") {
                model.newCollection(itemIDs: ids)
            }
            addToCollectionMenu(ids: ids)
            if let cid = collectionID {
                Button("Remove from Collection") {
                    model.removeFromCollection(ids, cid)
                    selection.subtract(ids)
                }
                .help("Take them out of this collection. They stay in the library and in any show that uses them.")
            }
            Divider()
            Button("Show in Finder") {
                let urls = ids.compactMap { model.itemsByID[$0] }.compactMap(model.url(for:))
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }

    private func addToShowMenu(ids: [Int64]) -> some View {
        Menu {
            Button("New Show…") { model.newShow(itemIDs: ids) }
            if !model.shows.isEmpty { Divider() }
            ForEach(model.shows) { show in
                Button(show.name) { model.append(ids, to: show.id) }
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
    }
}

@MainActor
func runImportPanel(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.image, .movie, .folder]
    panel.prompt = "Import"
    panel.message = "Files are copied into the ShowTools library. Folders are searched for images and videos."
    if panel.runModal() == .OK {
        let urls = panel.urls
        Task { await model.importFiles(urls) }
    }
}
