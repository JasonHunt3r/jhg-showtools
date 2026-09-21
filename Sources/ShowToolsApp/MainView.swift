import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore

/// Types a drop onto the app can carry: files from Finder, file promises
/// (or data) from Photos.
let droppableTypes: [UTType] = [.fileURL, .image, .movie]

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete: Show?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebar) {
                Label("Library", systemImage: "photo.on.rectangle.angled")
                    .badge(model.items.count)
                    .tag(SidebarItem.library)

                Section("Shows") {
                    ForEach(model.shows) { show in
                        Label(show.name, systemImage: "play.rectangle")
                            .badge(show.slides.count)
                            .tag(SidebarItem.show(show.id))
                            .contextMenu {
                                Button("Play") { Player.open(show: show, model: model, fullScreen: false) }
                                Button("Play Full Screen") { Player.open(show: show, model: model, fullScreen: true) }
                                Divider()
                                Button("Delete Show…") { confirmDelete = show }
                            }
                            // Dropping files on a show imports them and appends them to it.
                            .onDrop(of: droppableTypes, isTargeted: nil) { providers in
                                Task {
                                    let ids = await model.importProviders(providers)
                                    model.append(ids, to: show.id)
                                }
                                return true
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { model.newShow() } label: { Label("New Show", systemImage: "plus") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(8)
            }
        } detail: {
            switch model.sidebar {
            case .show(let id) where model.show(id) != nil:
                ShowView(showID: id)
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

struct LibraryGridView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<Int64> = []
    @State private var anchor: Int64?
    @State private var dropTargeted = false
    @AppStorage("gridTileSize") private var tileSize: Double = 150

    var body: some View {
        Group {
            if model.items.isEmpty {
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
            Task { await model.importProviders(providers) }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .navigationTitle("Library")
        .navigationSubtitle(selection.isEmpty ? "\(model.items.count) items" : "\(selection.count) selected")
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
                ForEach(model.items) { item in
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
                model.newShow(itemIDs: ids)
            }
            addToShowMenu(ids: ids)
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

    /// Selection in library order, so a new show follows the grid.
    private var orderedSelection: [Int64] {
        model.items.map(\.id).filter(selection.contains)
    }

    /// Finder-style clicking: plain replaces, ⌘ toggles, ⇧ extends a range.
    private func click(_ id: Int64) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if mods.contains(.shift), let a = anchor,
                  let i = model.items.firstIndex(where: { $0.id == a }),
                  let j = model.items.firstIndex(where: { $0.id == id }) {
            selection.formUnion(model.items[min(i, j)...max(i, j)].map(\.id))
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
