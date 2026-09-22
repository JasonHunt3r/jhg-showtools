import SwiftUI
import ShowToolsCore

/// Edit Show's right-hand column: the show's collection, its files to build
/// the show from (plan, 2b; Final Cut's browser). The show's own order lives
/// in the storyline.
///
/// A bar at the top: the collection, a search field, a filter menu, and an
/// arrow that opens (→) or closes (←) the inspector column. Files the show
/// uses come first, in the order they first appear (so they reorder with
/// the storyline), then a divider and the rest of the collection. Used
/// files carry an orange line, as Final Cut marks used media. The top
/// section lists *uses*: a file used more than once has an entry at each
/// use, numbered (1, 2, 3…), because each use has its own settings.
/// Selecting a use selects it in the show (the slide in the storyline, with
/// its inspector, or the lane image with its bar), and the storyline's
/// selection shows here in turn.
/// With the list focused, Final Cut's keys add the selected files: **E**
/// appends them to the show, **W** inserts them at the join nearest the
/// playhead (splitting a still would only repeat it), **Q** places the first
/// in the lane's images row at the playhead.
struct CollectionBrowser: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    let mutate: ShowMutator
    @Binding var inspectorShown: Bool
    /// The show's own selections: slides (storyline) and lane images.
    @Binding var selection: Set<Int64>
    @Binding var selectedOverlay: UUID?
    @Environment(AppModel.self) private var model

    /// What's picked in the list: uses in the show, or files not in it.
    enum Pick: Hashable {
        case slide(Int64)
        case overlay(UUID)
        case song(UUID)
        case file(Int64)
    }
    @State private var picked: Set<Pick> = []
    @Environment(\.undoManager) private var undoManager
    /// ⌘Delete's question: files to delete from the library.
    @State private var confirmDelete: [Int64]?
    @FocusState private var listFocused: Bool
    @State private var search = ""
    @AppStorage("browserUse") private var use: UseFilter = .all
    @AppStorage("browserMinRating") private var minRating = 0

    enum UseFilter: String, CaseIterable {
        case all, used, unused
        var title: String {
            switch self {
            case .all: "All Files"
            case .used: "In This Show"
            case .unused: "Not in This Show"
            }
        }
    }

    private var collection: MediaCollection? { show.collectionID.flatMap(model.collection) }

    /// Files the show uses: slides, lane images and songs alike.
    private var used: Set<Int64> {
        Set(show.slides.map(\.itemID) + show.overlays.map(\.itemID) + show.music.map(\.itemID))
    }

    /// One use of a file in the show: a slide (at its join), a lane image or
    /// a song (at its start).
    struct Use: Identifiable {
        let item: MediaItem
        /// The slide or lane image this use is.
        let pick: Pick
        /// 1 for its first appearance, 2 for the next…
        let number: Int
        /// How many times the show uses this file in all.
        var of: Int
        let time: Double
        var id: Pick { pick }
    }

    /// Every use of every file, in the order they appear on screen.
    private var uses: [Use] {
        let songs = show.music.compactMap { c in model.itemsByID[c.itemID].map { ($0, Pick.song(c.id), c.start) } }
        let appearances = (timeline.slides.map { ($0.item, Pick.slide($0.slide.id), $0.start) }
                           + timeline.overlays.map { ($0.item, Pick.overlay($0.clip.id), $0.start) }
                           + songs)
            .sorted { $0.2 < $1.2 }
        var seen: [Int64: Int] = [:]
        var out: [Use] = appearances.map { item, pick, t in
            seen[item.id, default: 0] += 1
            return Use(item: item, pick: pick, number: seen[item.id]!, of: 0, time: t)
        }
        for i in out.indices { out[i].of = seen[out[i].item.id] ?? 1 }
        return out
    }

    private func passes(_ item: MediaItem) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return (needle.isEmpty || item.fileName.lowercased().contains(needle)) && item.rating >= minRating
    }

    /// The show's uses of this collection's files, in order of appearance.
    private var usedEntries: [Use] {
        guard use != .unused, let c = collection else { return [] }
        let inCollection = Set(c.itemIDs)
        return uses.filter { inCollection.contains($0.item.id) && passes($0.item) }
    }

    /// The show's files, once each, in the order they first appear.
    private var usedFiles: [MediaItem] { usedEntries.filter { $0.number == 1 }.map(\.item) }

    /// The rest of the collection, in the order the files were added.
    private var unusedFiles: [MediaItem] {
        guard use != .used, let c = collection else { return [] }
        let used = used
        return c.itemIDs.filter { !used.contains($0) }.compactMap { model.itemsByID[$0] }.filter(passes)
    }

    private var files: [MediaItem] { usedFiles + unusedFiles }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            if collection == nil {
                ContentUnavailableView("Not in a collection", systemImage: "rectangle.stack",
                                       description: Text("This show doesn't belong to a collection."))
            } else {
                list
            }
        }
    }

    // MARK: The bar

    private var bar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack").foregroundStyle(.secondary)
                Text(collection?.name ?? "No collection")
                    .fontWeight(.semibold)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(files.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 4)
                Button { inspectorShown.toggle() } label: {
                    Image(systemName: inspectorShown ? "chevron.backward.2" : "chevron.forward.2")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(inspectorShown ? "Close the inspector (⌥⌘I)" : "Open the inspector (⌥⌘I)")
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.6)))
                filterMenu
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var filterMenu: some View {
        let active = use != .all || minRating > 0
        return Menu {
            Picker("Show", selection: $use) {
                ForEach(UseFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("Rating", selection: $minRating) {
                Text("Any Rating").tag(0)
                ForEach(1...5, id: \.self) { n in
                    Text(String(repeating: "★", count: n) + (n < 5 ? " or more" : "")).tag(n)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .help("Filter the list")
    }

    // MARK: The list

    private var list: some View {
        let top = usedEntries, rest = unusedFiles
        return List(selection: $picked) {
            if !top.isEmpty {
                Section {
                    ForEach(top) { u in
                        row(u.item, used: true, use: u.of > 1 ? u.number : nil).tag(u.pick)
                            .itemProvider { ItemDrag.provider([u.item.id]) }
                    }
                } header: {
                    Text("In this show")
                }
            }
            if !rest.isEmpty {
                Section {
                    ForEach(rest) { item in
                        row(item, used: false).tag(Pick.file(item.id))
                            .itemProvider { ItemDrag.provider([item.id]) }
                    }
                } header: {
                    Text("Not in this show")
                }
            }
        }
        .contextMenu(forSelectionType: Pick.self) { picks in
            let chosen = ordered(picks)
            Button("Append to Show  (E)") { append(chosen) }
            Button("Insert at Playhead  (W)") { insertAtPlayhead(chosen) }
            Button("Place in Images Row at Playhead  (Q)") { placeAtPlayhead(chosen) }
            Divider()
            if let cid = collection?.id {
                Button("Remove from Collection") { model.removeFromCollection(chosen, cid, undo: undoManager) }
            }
            Button("Delete from Library…") { confirmDelete = chosen }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    chosen.compactMap { model.itemsByID[$0] }.compactMap(model.url(for:)))
            }
        } primaryAction: { picks in
            // Double-clicking a use toggles the inspector, as the order list
            // before this did. A file not in the show has nothing to inspect.
            if picks.contains(where: { if case .file = $0 { false } else { true } }) { inspectorShown.toggle() }
        }
        // Delete by context (plan, Phase 3b): Delete takes the picked files
        // out of this collection (undoable); ⌘Delete deletes them from the
        // library, and asks first.
        .onDeleteCommand {
            guard let cid = collection?.id else { return }
            let files = ordered(picked)
            guard !files.isEmpty else { return }
            model.removeFromCollection(files, cid, undo: undoManager)
        }
        .focused($listFocused)
        // ⌘Delete never reaches onKeyPress inside a List; take it before
        // AppKit does, as the Library grid does, while the list has the keys.
        .background(SingleKeys { event in
            guard listFocused, event.keyCode == 51, event.plainModifiers == [.command], !picked.isEmpty
            else { return false }
            confirmDelete = ordered(picked)
            return true
        }.opacity(0).allowsHitTesting(false))
        .confirmationDialog(deleteTitle,
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { ids in
            Button(ids.count == 1 ? "Move to Trash" : "Move \(ids.count) Items to Trash", role: .destructive) {
                model.deleteItems(ids, undo: undoManager)
                picked = []
            }
        } message: { ids in
            Text(deleteMessage(ids))
        }
        .onKeyPress(keys: ["e", "w", "q"]) { press in
            guard press.modifiers.isEmpty, !picked.isEmpty else { return .ignored }
            let chosen = ordered(picked)
            switch press.key {
            case "e": append(chosen)
            case "w": insertAtPlayhead(chosen)
            default: placeAtPlayhead(chosen)
            }
            return .handled
        }
        // Picking one use selects it in the show; the show's selection comes
        // back here. Each side only changes the other when they differ.
        .onChange(of: picked) { _, p in
            guard p.count == 1, let only = p.first else { return }
            switch only {
            case .slide(let id):
                if selection != [id] { selection = [id] }
                if !engine.isPlaying { engine.showSlide(id: id) }
            case .overlay(let id):
                if selectedOverlay != id { selectedOverlay = id }
            case .file, .song:
                break
            }
        }
        .onChange(of: selection, initial: true) { _, s in
            guard !s.isEmpty else { return }
            let want = Set(s.map { Pick.slide($0) })
            if picked != want { picked = want }
        }
        .onChange(of: selectedOverlay) { _, o in
            if let o, picked != [.overlay(o)] { picked = [.overlay(o)] }
        }
    }

    /// `use` is which use of the file this entry is, shown when it has more
    /// than one.
    private func row(_ item: MediaItem, used: Bool, use: Int? = nil) -> some View {
        // A song has no pixel size: its waveform tile is wide.
        let aspect = item.kind == .audio ? 16 / 9 : CGFloat(item.pixelWidth) / CGFloat(max(item.pixelHeight, 1))
        return HStack(spacing: 8) {
            ThumbnailView(item: item, url: model.url(for: item))
                .frame(width: aspect >= 1 ? 40 : 30 * aspect, height: aspect >= 1 ? 40 / aspect : 30)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(width: 40, height: 30)
                .overlay(alignment: .bottom) {
                    if used {
                        Rectangle().fill(Color.orange).frame(height: 3)
                            .help("Used in this show")
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName).lineLimit(1).truncationMode(.middle)
                if item.rating > 0 {
                    Text(String(repeating: "★", count: item.rating))
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            if let use {
                Spacer(minLength: 4)
                Text("\(use)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .help("Use \(use) of this file in the show")
            }
        }
    }

    private var deleteTitle: String {
        guard let ids = confirmDelete else { return "" }
        if ids.count == 1, let item = model.itemsByID[ids[0]] { return "Move “\(item.fileName)” to the Trash?" }
        return "Move \(ids.count) items to the Trash?"
    }

    private func deleteMessage(_ ids: [Int64]) -> String {
        let them = ids.count == 1 ? "it" : "them"
        let n = model.showsUsing(Set(ids)).count
        var text = "This deletes \(them) from the library, not just this collection. "
        if n > 0 {
            let shows = n == 1 ? "1 show" : "\(n) shows"
            text += "Used in \(shows): every slide and lane image using \(them) will be removed. "
        }
        return text + "You can undo this."
    }

    /// The files behind the picked entries, once each, in the order the list
    /// shows them (E, W and Q add files).
    private func ordered(_ picks: Set<Pick>) -> [Int64] {
        let ids = Set(picks.compactMap(itemID))
        return files.map(\.id).filter(ids.contains)
    }

    private func itemID(_ pick: Pick) -> Int64? {
        switch pick {
        case .file(let id): id
        case .slide(let id): show.slides.first { $0.id == id }?.itemID
        case .overlay(let id): show.overlays.first { $0.id == id }?.itemID
        case .song(let id): show.music.first { $0.id == id }?.itemID
        }
    }

    // MARK: Adding to the show

    private func append(_ ids: [Int64]) {
        let ids = model.pictures(ids)
        guard !ids.isEmpty else { return }
        mutate(ids.count == 1 ? "Append Slide" : "Append Slides") { s in
            s.slides += ids.map { Slide(id: 0, itemID: $0) }
        }
    }

    /// At the join nearest the playhead: before the slide under it if the
    /// playhead is in its first half, after it if in the second.
    private func insertAtPlayhead(_ ids: [Int64]) {
        let ids = model.pictures(ids)
        guard !ids.isEmpty else { return }
        var at = show.slides.count
        if !timeline.slides.isEmpty {
            let t = timeline.wrap(engine.now)
            let i = timeline.index(at: engine.now)
            let r = timeline.slides[i]
            let resolvedIndex = t - r.start < r.length / 2 ? i : i + 1
            // Timeline indices skip slides whose file is missing; map back.
            if resolvedIndex < timeline.slides.count,
               let j = show.slides.firstIndex(where: { $0.id == timeline.slides[resolvedIndex].slide.id }) {
                at = j
            }
        }
        mutate(ids.count == 1 ? "Insert Slide" : "Insert Slides") { s in
            s.slides.insert(contentsOf: ids.map { Slide(id: 0, itemID: $0) }, at: min(at, s.slides.count))
        }
    }

    private func placeAtPlayhead(_ ids: [Int64]) {
        guard let id = ids.first, let kind = model.itemsByID[id]?.kind, kind.isPicture, kind != .video else { return }
        let t = timeline.wrap(engine.now)
        guard var clip = OverlayPlacement.place(itemID: id, at: t, length: ImagesRow.newLength,
                                                in: show.overlays, duration: ImagesRow.open,
                                                shortest: ImagesRow.shortest)
        else { NSSound.beep(); return }
        clip.transform.scale = 0.5
        mutate("Place Image") { $0.overlays.append(clip) }
    }
}
