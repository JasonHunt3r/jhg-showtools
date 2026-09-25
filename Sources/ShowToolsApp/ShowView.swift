import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// Every edit to a show goes through one of these: an undo name, and the change.
typealias ShowMutator = (_ action: String, _ change: (inout Show) -> Void) -> Void

enum EditMode: String, CaseIterable {
    case slides, show
    var title: String { self == .slides ? "Edit Slides" : "Edit Show" }
}

struct ShowView: View {
    let showID: Int64
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("editMode") private var mode: EditMode = .slides

    private var show: Show { model.show(showID) ?? Show(id: showID, name: "") }
    /// The show's editing state, out of this view and into the model
    /// (`spec/windows.md`, `ShowSession`) — a fresh one whenever `showID`
    /// changes, so nothing here resets it by hand.
    private var session: ShowSession { model.session(for: showID) }
    private var selection: Binding<Set<Int64>> {
        Binding(get: { session.selection }, set: { session.selection = $0 })
    }

    private func mutate(_ action: String, _ change: (inout Show) -> Void) {
        var s = show
        change(&s)
        model.update(s, undo: undoManager, action: action)
    }

    var body: some View {
        let timeline = model.timeline(for: show)
        Group {
            switch mode {
            case .slides:
                // On PaneKit now (spec/panekit.md, step 3), the same
                // mechanism EditShowView's columns use — not SwiftUI's
                // `.inspector()`, which is the confirmed cause of the
                // layout-loop crash. See spec/edit-slides-inspector-port.md.
                TwoColumns(
                    inspectorShown: $inspectorShown, model: model, panes: model.editSlidesColumns,
                    main: EditSlidesView(show: show, timeline: timeline, selection: selection, mutate: mutate,
                                         inspectorShown: $inspectorShown),
                    inspector: SlideInspector(show: show, timeline: timeline, selection: session.selection,
                                              mutate: mutate, close: { inspectorShown = false }))
            case .show:
                // Lays its own inspector out itself, above the storyline —
                // no SwiftUI .inspector() column here at all.
                EditShowView(show: show, timeline: timeline, session: session, mutate: mutate,
                             inspectorShown: $inspectorShown)
            }
        }
        .navigationTitle(show.name)
        .navigationSubtitle("\(show.slides.count) slides · \(formatDuration(timeline.duration))")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(EditMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItemGroup {
                Button { Player.open(show: show, model: model, fullScreen: false, startAt: firstSelectedIndex) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .help("Play in a window (⌥⇧⌘P)")
                .disabled(show.slides.isEmpty)
                Button { Player.open(show: show, model: model, fullScreen: true, startAt: firstSelectedIndex) } label: {
                    Label("Play Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Play full screen (⌥⌘P)")
                .disabled(show.slides.isEmpty)
                // The shortcut lives on the View menu's own Toggle now
                // (F2, batch 5), not here too — one menu item, one shortcut.
                Button { inspectorShown.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help("Show or hide the inspector (⌥⌘I) — or double-click a slide")
            }
        }
        .focusedSceneValue(\.activeShowID, showID)
        .focusedSceneValue(\.activeSlideSelection, session.selection)
        .focusedSceneValue(\.requestDuplicateSlides, { SlideActions.duplicate(session.selection, mutate: mutate) })
        .focusedSceneValue(\.requestSlideGetInfo, requestSlideGetInfo)
        .onAppear {
            if let id = model.devSelection { session.selection = [id]; model.devSelection = nil }
        }
        .onDisappear { model.closeShowSession() }
    }

    private var firstSelectedIndex: Int? {
        show.slides.firstIndex { session.selection.contains($0.id) }
    }

    /// Get Info (⌘I, F4) on the selected slides: their files, as the
    /// Library grid's own Get Info already shows.
    private func requestSlideGetInfo() {
        let itemIDs = show.slides.filter { session.selection.contains($0.id) }.map(\.itemID)
        guard !itemIDs.isEmpty else { return }
        model.infoPanelSelection = itemIDs
        InfoPanel.show(model: model, undoManager: undoManager)
    }
}

// MARK: - Shared slide actions

@MainActor
enum SlideActions {
    /// Takes slides out of the show. The files stay in the library.
    static func remove(_ ids: Set<Int64>, selection: Binding<Set<Int64>>, mutate: ShowMutator) {
        guard !ids.isEmpty, SlideRemovalNotice.confirm(count: ids.count) else { return }
        mutate(ids.count == 1 ? "Remove Slide" : "Remove Slides") { $0.slides.removeAll { ids.contains($0.id) } }
        selection.wrappedValue.subtract(ids)
    }

    /// Copies go right after their originals, with their settings, as new uses.
    /// A copy's auto Pan and Zoom comes from its own new id, as it always has,
    /// so an imported slide's seed isn't copied.
    static func duplicate(_ ids: Set<Int64>, mutate: ShowMutator) {
        mutate("Duplicate") { s in
            var out: [Slide] = []
            for slide in s.slides {
                out.append(slide)
                if ids.contains(slide.id) {
                    var copy = Slide(id: 0, itemID: slide.itemID, settings: slide.settings)
                    copy.settings.panAndZoomSeed = nil
                    out.append(copy)
                }
            }
            s.slides = out
        }
    }

    /// Moves a set of slides, as a block in their current order, so the
    /// first of them lands at `index` among the slides not being moved.
    static func move(_ ids: Set<Int64>, toIndexAmongOthers index: Int, mutate: ShowMutator) {
        mutate(ids.count == 1 ? "Move Slide" : "Move Slides") { s in
            let moving = s.slides.filter { ids.contains($0.id) }
            var rest = s.slides.filter { !ids.contains($0.id) }
            rest.insert(contentsOf: moving, at: min(max(index, 0), rest.count))
            s.slides = rest
        }
    }

    /// Replace a slide's image (item 8, work order; plan.md, "Replace a
    /// slide's image"): only its `itemID` changes. Length, transition, Pan
    /// and Zoom, transform and effects carry over unchanged, since every
    /// position in a slide's settings is already a fraction of the image,
    /// not pixels — a picture of a different shape just frames a little
    /// differently.
    static func replaceImage(_ slideID: Int64, with itemID: Int64, mutate: ShowMutator) {
        mutate("Replace Image") { s in
            guard let i = s.slides.firstIndex(where: { $0.id == slideID }) else { return }
            s.slides[i].itemID = itemID
        }
    }
}

// MARK: - Edit Slides mode

struct EditSlidesView: View {
    let show: Show
    let timeline: ShowTimeline
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator
    /// So the quick-settings menu's Custom… can open it.
    @Binding var inspectorShown: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var dropTargeted = false
    /// "Add from Collection…" on an empty show (audit H2).
    @State private var addingFromCollection = false
    /// Replace Image… (item 8, work order), by the slide it's for.
    @State private var replacingImage: Int64?

    var body: some View {
        VStack(spacing: 0) {
            DefaultsBar(show: show, mutate: mutate)
            Divider()
            list
        }
    }

    private var list: some View {
        let byID = Dictionary(uniqueKeysWithValues: timeline.slides.map { ($0.slide.id, $0) })
        return List(selection: $selection) {
            ForEach(Array(show.slides.enumerated()), id: \.element.id) { i, slide in
                SlideRow(number: i + 1, slide: slide, item: model.itemsByID[slide.itemID],
                         resolved: byID[slide.id], url: model.itemsByID[slide.itemID].flatMap(model.url(for:)),
                         handleDrop: { zone, providers in handleRowDrop(slide.id, zone, providers) })
                    .tag(slide.id)
            }
            .onMove { from, to in
                mutate("Move Slides") { $0.slides.move(fromOffsets: from, toOffset: to) }
            }
        }
        .onDeleteCommand { SlideActions.remove(selection, selection: $selection, mutate: mutate) }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let id = ids.first {
                Button("Open in Slide Editor") { openSlideEditor(id) }
                Button("Show in Library") {
                    guard let itemID = show.slides.first(where: { $0.id == id })?.itemID else { return }
                    showInLibrary(itemID, model: model, undoManager: undoManager)
                }
                if ids.count == 1 { Button("Replace Image…") { replacingImage = id } }
            }
            Divider()
            Button("Play from Here") {
                let i = show.slides.firstIndex { ids.contains($0.id) }
                Player.open(show: show, model: model, fullScreen: false, startAt: i)
            }
            Button("Play Full Screen") {
                let i = show.slides.firstIndex { ids.contains($0.id) }
                Player.open(show: show, model: model, fullScreen: true, startAt: i)
            }
            Divider()
            // Copy Settings/Paste Settings are meant to appear only while ⌥
            // is held (settled design) — simplified to always-visible items
            // here; see SlideClipboard's own note on why.
            Button("Copy") { SlideClipboard.copy(ids, from: show) }
            Button("Paste") { SlideClipboard.paste(after: lastByOrder(ids), mutate: mutate) }
                .disabled(!SlideClipboard.canPaste)
            if ids.count == 1, let id = ids.first {
                Button("Copy Settings") { SlideClipboard.copySettings(id, from: show) }
            }
            Button("Paste Settings") { SlideClipboard.pasteSettings(onto: ids, mutate: mutate) }
                .disabled(!SlideClipboard.canPasteSettings)
            Divider()
            QuickSettingsMenu.length(Array(ids), mutate: mutate) { selection = ids; inspectorShown = true }
            QuickSettingsMenu.transition(Array(ids), mutate: mutate)
            QuickSettingsMenu.panAndZoom(Array(ids), mutate: mutate)
            Divider()
            Button("Duplicate") { SlideActions.duplicate(ids, mutate: mutate) }
            Button("Remove from Show") { SlideActions.remove(ids, selection: $selection, mutate: mutate) }
        } primaryAction: { ids in
            // Double-click: "go into it" (conventions.md, settled
            // 2026-09-24) — the Slide Editor, not the inspector.
            if let id = ids.first { openSlideEditor(id) }
        }
        .overlay {
            if show.slides.isEmpty {
                ContentUnavailableView {
                    Label("No slides yet", systemImage: "rectangle.stack")
                } description: {
                    Text("Select items in the Library and choose Add to Show, or drag files here.")
                } actions: {
                    Button("Add from Collection…") { addingFromCollection = true }
                        .disabled(collectionItems.isEmpty)
                    Button("Import…") { runImportIntoShowPanel(model, showID: show.id, undo: undoManager) }
                    Button("Paste") { SlideClipboard.paste(after: nil, mutate: mutate) }
                        .disabled(!SlideClipboard.canPaste)
                }
            }
        }
        .sheet(isPresented: $addingFromCollection) {
            MultiItemPicker(title: "Add from Collection", items: collectionItems) { ids in
                model.append(Array(ids), to: show.id, undo: undoManager)
            }
        }
        .sheet(isPresented: Binding(get: { replacingImage != nil }, set: { if !$0 { replacingImage = nil } })) {
            if let slideID = replacingImage, let itemID = show.slides.first(where: { $0.id == slideID })?.itemID {
                ReplaceImagePicker(show: show, currentItemID: itemID) { newItemID in
                    SlideActions.replaceImage(slideID, with: newItemID, mutate: mutate)
                }
            }
        }
        .onDrop(of: ItemDrag.accepted, isTargeted: $dropTargeted) { providers in
            Task {
                let ids = await model.itemIDs(from: providers)
                model.append(ids, to: show.id, undo: undoManager)
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
    }

    /// The show's own collection's pictures — songs can't be slides.
    private var collectionItems: [MediaItem] {
        guard let cid = show.collectionID, let ids = model.collection(cid)?.itemIDs else { return [] }
        return ids.compactMap { model.itemsByID[$0] }.filter { $0.kind.isPicture }
    }

    private func openSlideEditor(_ id: Int64) {
        SlideEditorWindow.show(slideID: id, show: show, model: model, mutate: mutate, undoManager: undoManager)
    }

    /// Paste lands after the last (by show order) of the ids the menu was
    /// opened on, so pasting onto a selection reads as "after what I had
    /// selected," not wherever the id set happens to iterate to.
    private func lastByOrder(_ ids: Set<Int64>) -> Int64? {
        show.slides.lastIndex { ids.contains($0.id) }.map { show.slides[$0].id }
    }

    /// A drop on a row of the list (item 8, work order; G2's own fix —
    /// this used to always append, wherever it landed). The middle band
    /// replaces the row's image, one picture only; the edge bands insert
    /// before or after it, like the timeline's own drop.
    private func handleRowDrop(_ slideID: Int64, _ zone: SlideRow.DropZone, _ providers: [NSItemProvider]) {
        let showID = show.id
        Task {
            let ids = model.pictures(await model.itemIDs(from: providers))
            guard !ids.isEmpty, model.bringIntoCollection(ids, forShow: showID) else { return }
            switch zone {
            case .replace where ids.count == 1:
                SlideActions.replaceImage(slideID, with: ids[0], mutate: mutate)
            case .replace, .insertAfter:
                guard let i = show.slides.firstIndex(where: { $0.id == slideID }) else { return }
                mutate(ids.count == 1 ? "Insert Slide" : "Insert Slides") { s in
                    s.slides.insert(contentsOf: ids.map { Slide(id: 0, itemID: $0) }, at: i + 1)
                }
            case .insertBefore:
                guard let i = show.slides.firstIndex(where: { $0.id == slideID }) else { return }
                mutate(ids.count == 1 ? "Insert Slide" : "Insert Slides") { s in
                    s.slides.insert(contentsOf: ids.map { Slide(id: 0, itemID: $0) }, at: i)
                }
            }
        }
    }
}

struct SlideRow: View {
    /// A drop landing on this row (item 8, work order; G2): the top and
    /// bottom bands insert before or after, like the timeline's own drop
    /// line; the middle replaces this slide's image, as Final Cut's
    /// replace edit does — one picture only, since replacing with several
    /// doesn't mean anything. Fixed pixel bands, not measured against the
    /// row's own height: a `GeometryReader` inside a `List` row measures
    /// during layout, which this app has a standing crash risk around
    /// (`spec/CLAUDE.md`), and every row here is the same height anyway.
    enum DropZone { case insertBefore, replace, insertAfter }

    let number: Int
    let slide: Slide
    let item: MediaItem?
    let resolved: ResolvedSlide?
    let url: URL?
    /// Nil: no drop handling (used nowhere today, but keeps `SlideRow`
    /// usable without it).
    var handleDrop: ((DropZone, [NSItemProvider]) -> Void)? = nil
    @State private var dropZone: DropZone?

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            if let item {
                ThumbnailView(item: item, url: url)
                    .frame(width: 72, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName).lineLimit(1).truncationMode(.middle)
                    if let r = resolved {
                        HStack(spacing: 6) {
                            setting(formatSeconds(r.length), custom: slide.settings.length != nil)
                            Text("·").foregroundStyle(.tertiary)
                            setting(r.transitionIn.style.title, custom: slide.settings.transition != nil)
                            if r.panAndZoom != nil {
                                Text("·").foregroundStyle(.tertiary)
                                setting("Pan and Zoom", custom: slide.settings.panAndZoom != nil)
                            }
                        }
                        .font(.caption)
                    }
                }
                Spacer()
                if let r = resolved {
                    Text(formatDuration(r.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Missing from library").foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .overlay {
            if let dropZone {
                switch dropZone {
                case .replace:
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2)
                case .insertBefore:
                    Rectangle().fill(Color.accentColor).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
                case .insertAfter:
                    Rectangle().fill(Color.accentColor).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .onDrop(of: ItemDrag.accepted, delegate: SlideRowDrop(
            update: { dropZone = $0 },
            perform: { zone, providers in handleDrop?(zone, providers) }))
    }

    /// Values the slide sets itself are shown stronger than inherited ones.
    private func setting(_ text: String, custom: Bool) -> some View {
        Text(text)
            .foregroundStyle(custom ? Color.accentColor : .secondary)
            .fontWeight(custom ? .medium : .regular)
    }
}

/// A drop's y within a `SlideRow`, fixed pixel bands (see `SlideRow.DropZone`).
struct SlideRowDrop: DropDelegate {
    let update: (SlideRow.DropZone?) -> Void
    let perform: (SlideRow.DropZone, [NSItemProvider]) -> Void

    private func zone(_ info: DropInfo) -> SlideRow.DropZone {
        let y = info.location.y
        if y < 12 { return .insertBefore }
        if y > 44 { return .insertAfter }
        return .replace
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: ItemDrag.accepted) }
    func dropEntered(info: DropInfo) { update(zone(info)) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(zone(info))
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { update(nil) }
    func performDrop(info: DropInfo) -> Bool {
        let z = zone(info)
        update(nil)
        perform(z, info.itemProviders(for: ItemDrag.accepted))
        return true
    }
}

// MARK: - Show defaults

struct DefaultsBar: View {
    let show: Show
    let mutate: ShowMutator

    var body: some View {
        // Two rows, always.
        //
        // This used to scroll sideways, which put Background, Loop and
        // "Videos play in full" past the right edge with nothing to say they
        // were there (measured in the app at x=1431, 1576 and 1645, with the
        // window ending at 1385). On one line the row needs about 1490pt,
        // and the whole window's minimum is 1100, so one line never fits:
        // there is nothing to choose between, and it wraps unconditionally.
        //
        // Deliberately **not `ViewThatFits`**, which was the first attempt:
        // it measures its candidates during layout, and this app has an
        // intermittent crash in exactly that area (an exception from
        // `-[NSWindow _postWindowNeedsUpdateConstraints]` during AppKit's
        // display cycle — see the handoff). Nothing proved ViewThatFits
        // caused it, and it wasn't ruled out either; since one line can
        // never fit there is nothing for it to choose, so the simpler
        // layout is the one to keep.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) { naming; timing }
            HStack(spacing: 18) { look; toggles }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var naming: some View {
        HStack(spacing: 18) {
            ShowNameField(show: show)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 140, maxWidth: 240)
            Divider().frame(height: 22)
        }
    }

    private var timing: some View {
        let d = show.defaults
        return HStack(spacing: 18) {
            labelled("Length") {
                SecondsField(value: d.length) { v in mutate("Change Default Length") { $0.defaults.length = v } }
            }
            labelled("Transition") {
                TransitionPicker(transition: d.transition) { t in mutate("Change Default Transition") { $0.defaults.transition = t } }
            }
        }
    }

    private var look: some View {
        let d = show.defaults
        return HStack(spacing: 18) {
            labelled("Pan and Zoom") {
                Picker("", selection: Binding(get: { d.panAndZoom == .auto },
                                              set: { on in mutate("Change Default Pan and Zoom") { $0.defaults.panAndZoom = on ? .auto : .off } })) {
                    Text("Off").tag(false)
                    Text("Auto").tag(true)
                }
                .labelsHidden().fixedSize()
            }
            labelled("Fit") {
                Picker("", selection: Binding(get: { d.fit }, set: { f in mutate("Change Default Fit") { $0.defaults.fit = f } })) {
                    ForEach(Fit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            labelled("Background") {
                // Behind every slide that hasn't its own, and after the
                // last slide while an image or song runs on (plan, Phase 3).
                SettledColorPicker(title: "", colour: d.background) { c in
                    mutate("Change Default Background") { $0.defaults.background = c }
                }
                .labelsHidden()
                .help("The show's background: behind slides that don't set their own, and after the last slide")
            }
        }
    }

    private var toggles: some View {
        let d = show.defaults
        return HStack(spacing: 18) {
            Toggle("Loop", isOn: Binding(get: { d.loop }, set: { v in mutate("Change Loop") { $0.defaults.loop = v } }))
            Toggle("Videos play in full", isOn: Binding(get: { d.videoUsesClipLength },
                                                        set: { v in mutate("Change Video Length") { $0.defaults.videoUsesClipLength = v } }))
                .help("Video slides use their clip's length unless given their own")
            defaultsMenu
        }
        .fixedSize()
    }

    /// Settled 2026-09-24 (`spec/conventions.md` §3, item 3), except Save as
    /// Preset…, which needs somewhere to keep presets — not designed yet,
    /// so left out rather than guessed at.
    private var defaultsMenu: some View {
        Menu {
            Button("Use Defaults for All Slides") {
                mutate("Use Show Defaults for All Slides") { s in
                    for i in s.slides.indices { s.slides[i].settings = SlideSettings() }
                }
            }
            Divider()
            Button("Reset to App Defaults") {
                mutate("Reset Show Defaults") { $0.defaults = ShowDefaults() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show defaults")
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            content()
        }
        .fixedSize()
    }
}

/// The show's name, saved once when editing ends (Return, or leaving the
/// field): one save and one undo step for a whole rename, not one per
/// keystroke. An empty name puts the old one back, as Rename… does. The
/// draft remembers its show, so switching shows mid-edit renames the show
/// it was typed for.
struct ShowNameField: View {
    let show: Show
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var draft: (showID: Int64, text: String)?
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: Binding(
            get: { draft?.showID == show.id ? draft!.text : show.name },
            set: { draft = (show.id, $0) }))
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onChange(of: show.id) { _, _ in commit() }
    }

    private func commit() {
        guard let d = draft else { return }
        draft = nil
        let name = d.text.trimmingCharacters(in: .whitespaces)
        if name != model.show(d.showID)?.name { model.renameShow(d.showID, to: name, undo: undoManager) }
    }
}

/// A seconds value with a stepper. Commits on Return or when focus leaves.
struct SecondsField: View {
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { set(max(0.1, $0)) }),
                      format: .number.precision(.fractionLength(0...2)))
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
            Text("s").foregroundStyle(.secondary)
            Stepper("", value: Binding(get: { value }, set: { set(max(0.5, ($0 * 2).rounded() / 2)) }),
                    step: 0.5)
                .labelsHidden()
        }
    }
}

struct TransitionPicker: View {
    let transition: ShowToolsCore.Transition
    let set: (ShowToolsCore.Transition) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { transition.style },
                                          set: { var t = transition; t.style = $0; set(t) })) {
                ForEach(TransitionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            if transition.style != .cut {
                SecondsField(value: transition.duration) { var t = transition; t.duration = $0; set(t) }
            }
            if transition.style.usesDirection {
                Picker("", selection: Binding(get: { transition.direction },
                                              set: { var t = transition; t.direction = $0; set(t) })) {
                    ForEach(Direction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}
