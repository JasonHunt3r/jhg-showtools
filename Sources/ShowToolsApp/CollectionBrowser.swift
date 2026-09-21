import SwiftUI
import ShowToolsCore

/// Edit Show's right-hand column: the show's collection, its files to build
/// the show from (plan, 2b; Final Cut's browser). The show's own order lives
/// in the storyline.
///
/// A bar at the top: the collection, a search field, a filter menu, and an
/// arrow that opens (→) or closes (←) the inspector column. Files already
/// used in the show carry an orange line, as Final Cut marks used media.
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
    @Environment(AppModel.self) private var model

    @State private var picked: Set<Int64> = []
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

    /// Files the show uses, slides and lane images alike.
    private var used: Set<Int64> { Set(show.slides.map(\.itemID) + show.overlays.map(\.itemID)) }

    private var files: [MediaItem] {
        guard let c = collection else { return [] }
        let used = used
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return c.itemIDs.compactMap { model.itemsByID[$0] }.filter { item in
            (needle.isEmpty || item.fileName.lowercased().contains(needle))
                && item.rating >= minRating
                && (use == .all || (use == .used) == used.contains(item.id))
        }
    }

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
        let used = used
        return List(selection: $picked) {
            ForEach(files) { item in
                row(item, used: used.contains(item.id)).tag(item.id)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            let chosen = ordered(ids)
            Button("Append to Show  (E)") { append(chosen) }
            Button("Insert at Playhead  (W)") { insertAtPlayhead(chosen) }
            Button("Place in Images Row at Playhead  (Q)") { placeAtPlayhead(chosen) }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    chosen.compactMap { model.itemsByID[$0] }.compactMap(model.url(for:)))
            }
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
    }

    private func row(_ item: MediaItem, used: Bool) -> some View {
        let aspect = CGFloat(item.pixelWidth) / CGFloat(max(item.pixelHeight, 1))
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
        }
    }

    /// The chosen files in the list's order.
    private func ordered(_ ids: Set<Int64>) -> [Int64] {
        (collection?.itemIDs ?? []).filter(ids.contains)
    }

    // MARK: Adding to the show

    private func append(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        mutate(ids.count == 1 ? "Append Slide" : "Append Slides") { s in
            s.slides += ids.map { Slide(id: 0, itemID: $0) }
        }
    }

    /// At the join nearest the playhead: before the slide under it if the
    /// playhead is in its first half, after it if in the second.
    private func insertAtPlayhead(_ ids: [Int64]) {
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
        guard let id = ids.first, model.itemsByID[id]?.kind != .video else { return }
        let t = timeline.wrap(engine.now)
        guard var clip = OverlayPlacement.place(itemID: id, at: t, length: ImagesRow.newLength,
                                                in: show.overlays, duration: timeline.duration,
                                                shortest: ImagesRow.shortest)
        else { NSSound.beep(); return }
        clip.transform.scale = 0.5
        mutate("Place Image") { $0.overlays.append(clip) }
    }
}
