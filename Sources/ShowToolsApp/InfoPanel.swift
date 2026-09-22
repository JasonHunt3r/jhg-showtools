import SwiftUI
import ShowToolsCore

/// The Info panel's "write tags as Finder tags too" setting (plan, 2b).
/// Off by default; tags always live in the database regardless.
enum FinderTagsSetting {
    static let key = "writeTagsAsFinderTags"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// A floating side panel, like ⌘I in Photos: metadata read fresh from the
/// file, and tags you add yourself. Follows the Library grid's selection —
/// see `AppModel.infoPanelSelection` for why that lives on the model rather
/// than in the grid's own state. Built from `spec/macos_panels_guide.md`
/// (a single panel, so no snapping is needed here).
@MainActor
final class InfoPanel: NSObject, NSWindowDelegate {
    private static var shared: InfoPanel?

    static func toggle(model: AppModel, undoManager: UndoManager?) {
        if let shared { shared.window.close(); return }
        show(model: model, undoManager: undoManager)
    }

    /// `undoManager` is the presenting window's (`LibraryGridView`'s own
    /// `\.undoManager`) — passed in rather than read inside the panel's own
    /// content, which is a separate window with its own (see the rename
    /// sheet's note; hit again here in testing before this fix).
    static func show(model: AppModel, undoManager: UndoManager?) {
        if let shared { shared.window.makeKeyAndOrderFront(nil); return }
        let panel = InfoPanel(model: model, undoManager: undoManager)
        shared = panel
        panel.present()
    }

    private let window: InfoPanelWindow

    private init(model: AppModel, undoManager: UndoManager?) {
        window = InfoPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Info"
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.sharedUndoManager = undoManager
        window.contentView = NSHostingView(
            rootView: InfoPanelContent(undoManager: undoManager).environment(model))
        window.setFrameAutosaveName("infoPanel")
    }

    private func present() {
        if window.frame.origin == .zero, let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 20,
                                          y: screen.visibleFrame.maxY - window.frame.height - 60))
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}

/// `canBecomeKey` must return true, or the panel can't take the keyboard —
/// needed here for the tag field. Overriding `undoManager` matters just as
/// much and is easy to miss: a window vends its own `UndoManager` by
/// default, so ⌘Z pressed while the *panel* is key (typical right after
/// typing a tag) would silently ask the wrong one — registering the step
/// on the right manager isn't enough by itself. Confirmed by hand: without
/// this override, undo right after adding a tag did nothing.
final class InfoPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    var sharedUndoManager: UndoManager?
    override var undoManager: UndoManager? { sharedUndoManager }
}

/// The panel's content: follows `model.infoPanelSelection`, which the
/// Library grid keeps current.
struct InfoPanelContent: View {
    /// Passed in explicitly — see the note on `InfoPanel.show`.
    let undoManager: UndoManager?
    @Environment(AppModel.self) private var model
    @State private var newTag = ""

    private var itemIDs: [Int64] { model.infoPanelSelection }
    private var items: [MediaItem] { itemIDs.compactMap { model.itemsByID[$0] } }

    /// Read fresh each time the selection changes — never cached — for a
    /// single selected file. Several files show only what's common (the
    /// count), not a merged metadata table.
    private var metadata: MediaMetadata? {
        guard items.count == 1, let item = items.first, let url = model.url(for: item) else { return nil }
        return MediaMetadata.read(url)
    }

    /// Tags shown for editing: the union across the selection, so adding
    /// one from here adds it to every selected file.
    private var unionTags: [String] { Array(Set(items.flatMap(\.tags))).sorted() }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No Selection", systemImage: "info.circle",
                                       description: Text("Select a file in the Library to see its info."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        Divider()
                        ratingRow
                        Divider()
                        tagsSection
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 260, idealWidth: 280, minHeight: 200)
    }

    // MARK: Header: thumbnail and metadata for one, a count for several

    @ViewBuilder private var header: some View {
        if items.count == 1, let item = items.first {
            VStack(alignment: .leading, spacing: 10) {
                ThumbnailView(item: item, url: model.url(for: item))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(item.fileName).font(.headline).lineLimit(2)
                singleFileMetadata(item)
            }
        } else {
            Text("\(items.count) Items Selected").font(.headline)
        }
    }

    @ViewBuilder
    private func singleFileMetadata(_ item: MediaItem) -> some View {
        let m = metadata
        VStack(alignment: .leading, spacing: 4) {
            row("Dimensions", "\(item.pixelWidth) × \(item.pixelHeight)")
            if let size = m?.fileSize { row("Size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            if let format = m?.format { row("Format", format) }
            if let date = m?.dateTaken { row("Date Taken", date.formatted(date: .abbreviated, time: .shortened)) }
            if let make = m?.cameraMake, let model = m?.cameraModel {
                row("Camera", model.hasPrefix(make) ? model : "\(make) \(model)")
            } else if let model = m?.cameraModel ?? m?.cameraMake {
                row("Camera", model)
            }
            if let lens = m?.lensModel { row("Lens", lens) }
            if let exposure = exposureSummary(m) { row("Exposure", exposure) }
            if let lat = m?.latitude, let lon = m?.longitude {
                row("Location") {
                    Link(String(format: "%.5f, %.5f", lat, lon),
                         destination: URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)")!)
                }
            }
        }
        .font(.caption)
    }

    private func exposureSummary(_ m: MediaMetadata?) -> String? {
        guard let m else { return nil }
        var parts: [String] = []
        if let f = m.fNumber { parts.append("ƒ/\(String(format: "%.1f", f))") }
        if let t = m.exposureTime {
            parts.append(t < 1 ? "1/\(Int((1 / t).rounded()))s" : "\(String(format: "%.1f", t))s")
        }
        if let iso = m.iso { parts.append("ISO \(iso)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Rating: the first selected file's; setting it applies to all

    private var ratingRow: some View {
        HStack {
            Text("Rating").font(.caption).foregroundStyle(.secondary)
            Spacer()
            StarRating(rating: items.first?.rating ?? 0) { r in
                model.setRating(r, for: Set(itemIDs), undo: undoManager)
            }
        }
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.caption).foregroundStyle(.secondary)
            if unionTags.isEmpty {
                Text("No tags").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(unionTags, id: \.self) { tag in
                    HStack {
                        Text(tag).font(.callout)
                        Spacer()
                        Button { removeTag(tag) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                TextField("Add a tag…", text: $newTag)
                    .textFieldStyle(.plain)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.6)))
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        newTag = ""
        var changes: [Int64: [String]] = [:]
        for item in items where !item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            changes[item.id] = item.tags + [tag]
        }
        guard !changes.isEmpty else { return }
        model.setTags(changes, undo: undoManager)
    }

    private func removeTag(_ tag: String) {
        var changes: [Int64: [String]] = [:]
        for item in items where item.tags.contains(tag) {
            changes[item.id] = item.tags.filter { $0 != tag }
        }
        guard !changes.isEmpty else { return }
        model.setTags(changes, undo: undoManager)
    }

    // MARK: A plain metadata row

    private func row(_ label: String, _ value: String) -> some View {
        row(label) { Text(value) }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
