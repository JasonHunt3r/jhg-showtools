import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

@main
struct ShowToolsApp: App {
    @State private var model = AppModel()

    // Catches the reason string of the crash the app has been having
    // (ExceptionProbe). Remove with the probe.
    init() { ExceptionProbe.install(); LayoutLoopProbe.install() }

    var body: some Scene {
        Window("ShowTools", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { DevHooks.run(model) }
        }
        .defaultSize(width: 1320, height: 820)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        // Help ▸ Keyboard Shortcuts (F3): SwiftUI's default Help menu item
        // says help isn't available, which is worse than nothing.
        Window("Keyboard Shortcuts", id: "shortcuts") {
            KeyboardShortcutsView()
        }
        .defaultSize(width: 480, height: 560)
        .windowResizability(.contentSize)
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.activeShowID) private var activeShowID
    @FocusedValue(\.librarySelectionCount) private var librarySelectionCount
    @FocusedValue(\.requestLibraryRename) private var requestLibraryRename
    @FocusedValue(\.requestLibraryGetInfo) private var requestLibraryGetInfo
    @FocusedValue(\.requestNewCollection) private var requestNewCollection
    // Batch 5 (A2, F1–F4, G5): the open show's slide selection and its
    // Duplicate/Get Info, and Edit Show's transport and timeline commands —
    // absent whenever no show, or no Edit Show, has the window.
    @FocusedValue(\.activeSlideSelection) private var activeSlideSelection
    @FocusedValue(\.requestDuplicateSlides) private var requestDuplicateSlides
    @FocusedValue(\.requestSlideGetInfo) private var requestSlideGetInfo
    @FocusedValue(\.editShowCommands) private var editShowCommands
    @AppStorage("frameStripShown") private var frameStripShown = true
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("editMode") private var mode: EditMode = .slides
    @AppStorage("snapping") private var snapping = true
    @AppStorage("storylineZoom") private var pps: Double = 24
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Show") { model.newShow() }
                .keyboardShortcut("n")
                .disabled(model.collections.isEmpty)
            Button("New Collection…") { requestNewCollection?() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Import…") { runImportPanel(model) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Add to Library…") { runImportPanel(model, intoCollection: false) }
                .keyboardShortcut("i", modifiers: [.command, .shift, .option])
            Button("Import Show…") { runImportShowPanel(model) }
                .disabled(model.library == nil)
            // The show in the window, or the one selected in the sidebar (plan, Phase 4).
            Menu("Export") {
                Button("Show…") { if let id = exportShowID { runExportPanel(model, showID: id) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(exportShowID == nil || model.exportStatus?.finished == false)
                Button("Movie…") { if let id = exportShowID { runMovieExportPanel(model, showID: id) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                    .disabled(exportShowID == nil || model.movieExportStatus?.finished == false)
            }
            Divider()
            // The Library grid publishes these while it has a selection
            // (2b); a show's slide selection publishes Get Info too (F4) —
            // whichever's in view answers, since only one is ever focused
            // at once.
            Button("Get Info") {
                if let requestSlideGetInfo, !(activeSlideSelection ?? []).isEmpty { requestSlideGetInfo() }
                else { requestLibraryGetInfo?() }
            }
            .keyboardShortcut("i")
            .disabled((librarySelectionCount ?? 0) == 0 && (activeSlideSelection ?? []).isEmpty)
            Button("Rename…") { requestLibraryRename?() }
                .disabled((librarySelectionCount ?? 0) == 0)
            Divider()
            // Whole-library maintenance, not scoped to a selection (2b).
            Button("Relink Missing Files…") { model.relinkMissingItems() }
                .disabled(model.library == nil)
            Divider()
            // Libraries switch one at a time, as Photos does (plan, 2b).
            Button("Open Library…") { runOpenLibraryPanel(model) }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Menu("Open Recent Library") {
                ForEach(model.recentLibraries, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        Task { await model.openRecent(url) }
                    }
                }
                if !model.recentLibraries.isEmpty { Divider() }
                Button("Clear Menu") { model.clearRecentLibraries() }
                    .disabled(model.recentLibraries.isEmpty)
            }
            Button("New Library…") { runNewLibraryPanel(model) }
            Button("Open Master Library") { Task { await model.openLibrary(at: model.masterURL) } }
                .disabled(model.isOnMaster)
        }

        // A2: Duplicate, for the slides selected in whichever mode has the
        // window (not lane images yet — no Duplicate action exists for one).
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") { requestDuplicateSlides?() }
                .keyboardShortcut("d")
                .disabled((activeSlideSelection ?? []).isEmpty)
        }

        // F2: the inspector toggle and the Edit Slides/Edit Show switch,
        // both really global AppStorage already (one window's change is
        // every window's), so they need no focused value.
        CommandGroup(before: .toolbar) {
            Toggle("Show Library", isOn: Binding(get: { model.mainPanes.isOpen("main") },
                                                 set: { model.mainPanes.setOpen("main", $0) }))
                .keyboardShortcut("l", modifiers: [.command, .option])
            Toggle("Show Frame Strip", isOn: $frameStripShown)
                .keyboardShortcut("f", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: $inspectorShown)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(activeShowID == nil)
            Divider()
            Button("Edit Slides") { mode = .slides }
                .keyboardShortcut("1")
                .disabled(activeShowID == nil)
            Button("Edit Show") { mode = .show }
                .keyboardShortcut("2")
                .disabled(activeShowID == nil)
            Divider()
            // F1: Edit Show's zoom and snapping — `pps` and `snapping` are
            // both plain AppStorage (one storyline's zoom is every
            // storyline's), so, like the toggles above, these need no
            // focused value; `editShowCommands` gates them to Edit Show,
            // where they mean something.
            Button("Zoom In") { pps = min(pps * 1.5, 400) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(editShowCommands == nil)
            Button("Zoom Out") { pps = max(pps / 1.5, 2) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editShowCommands == nil)
            Button("Zoom to Fit") { editShowCommands?.zoomToFit() }
                .keyboardShortcut("z", modifiers: .shift)
                .disabled(editShowCommands == nil)
            Toggle("Snapping  (N)", isOn: $snapping)
                .disabled(editShowCommands == nil)
            Divider()
            Button("Restore Default Layout") {
                model.mainPanes.restoreDefaults()
                DefaultLayout.restore()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
        }

        CommandGroup(after: .toolbar) {
            // Phase 5: the desktop is BGTools' job, and it lives inside
            // this app (spec/bgtools.md, spec/xcode-port.md).
            Button("Desktop Show…") {
                do { try BGToolsHelper.openDesktop() } catch { NSAlert(error: error).runModal() }
            }
            Divider()
        }

        CommandMenu("Show") {
            // G5: starts at the selected slide, like the toolbar's own
            // Play and Play Full Screen already do.
            Button("Play") { play(fullScreen: false) }
                .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                .disabled(activeShow == nil)
            Button("Play Full Screen") { play(fullScreen: true) }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(activeShow == nil)
            Divider()
            // F1: Edit Show's transport and range, published as
            // `editShowCommands` — absent (so these disable themselves) in
            // Edit Slides, which has no viewer or timeline to act on.
            // Play/Pause, Add Marker, Set Range In/Out are bare keys
            // (Space, M, I, O) — never `.keyboardShortcut`, which would
            // steal them from a focused text field (audit M4); the key is
            // named in the title instead, as the browser's E/W/Q already
            // are (C8).
            Button("Play/Pause  (Space)") { editShowCommands?.togglePlay() }
                .disabled(editShowCommands == nil)
            Button("Add Marker  (M)") { editShowCommands?.addMarker() }
                .disabled(editShowCommands == nil)
            Button("Set Range In  (I)") { editShowCommands?.setRangeIn() }
                .disabled(editShowCommands == nil)
            Button("Set Range Out  (O)") { editShowCommands?.setRangeOut() }
                .disabled(editShowCommands == nil)
            Button("Clear Range") { editShowCommands?.clearRange() }
                .keyboardShortcut("x", modifiers: .option)
                .disabled(editShowCommands == nil)
            Toggle("Loop Playback", isOn: Binding(
                get: { editShowCommands?.loopOn ?? false },
                set: { _ in editShowCommands?.toggleLoop() }))
                .keyboardShortcut("l", modifiers: .command)
                .disabled(editShowCommands == nil)
            Divider()
            Button("Rhythm…") { openRhythm() }
                .keyboardShortcut("r")
                .disabled(activeShowID.flatMap { model.show($0) } == nil)
        }

        // F3: replaces SwiftUI's default item, which just says help isn't
        // available, with the single-key commands that have nowhere else
        // to show themselves.
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
        }
    }

    private var exportShowID: Int64? {
        if let id = activeShowID, model.show(id) != nil { return id }
        if case .show(let id) = model.sidebar, model.show(id) != nil { return id }
        return nil
    }

    private var activeShow: Show? {
        activeShowID.flatMap { model.show($0) }.flatMap { $0.slides.isEmpty ? nil : $0 }
    }

    /// The Rhythm tool (plan, Phase 3 step 7), on the show in the window.
    @MainActor private func openRhythm() {
        guard let id = activeShowID else { return }
        RhythmTool.shared.open(showID: id, model: model, undoManager: NSApp.mainWindow?.undoManager)
    }

    /// G5: starts at the selected slide, matching the toolbar's own Play
    /// and Play Full Screen (`ShowView.firstSelectedIndex`) — before this
    /// fix the two ⌥⇧⌘P/⌥⌘P shortcuts always started from the top.
    @MainActor private func play(fullScreen: Bool) {
        guard let show = activeShow else { return }
        let startAt = show.slides.firstIndex { (activeSlideSelection ?? []).contains($0.id) }
        Player.open(show: show, model: model, fullScreen: fullScreen, startAt: startAt)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SlideRemovalNotice.suppressKey) private var suppressRemovalNotice = false
    @AppStorage(CollectionAddNotice.autoAddKey) private var autoAddToCollection = false
    @AppStorage(FinderTagsSetting.key) private var writeFinderTags = false
    @AppStorage(ExportSettings.stripKey) private var stripOnExport = true

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Name", value: model.libraryName)
                LabeledContent("Location") {
                    HStack {
                        Text(model.library?.root.path(percentEncoded: false) ?? "—")
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Show in Finder") {
                            if let root = model.library?.root {
                                NSWorkspace.shared.activateFileViewerSelecting([root])
                            }
                        }
                    }
                }
                Toggle("Let Spotlight index the library", isOn: Binding(
                    get: { !model.libraryHiddenFromSpotlight },
                    set: { model.setSpotlightIndexing($0) }))
                Text(model.libraryHiddenFromSpotlight
                     ? "Hidden: the library folder ends in “.noindex”, so Spotlight skips its file names, image details and the text in pictures."
                     : "Searchable: Spotlight can find library files by name, image details and the text in pictures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Private library", isOn: Binding(
                    get: { model.libraryIsPrivate },
                    set: { on in Task { await model.setPrivate(on) } }))
                    .disabled(model.library == nil)
                Text("Opening a private library asks for Touch ID or your Mac's password, and it's never listed in Open Recent. Turning this off asks too. It locks ShowTools' door only: the photos are still ordinary files to anyone using this Mac account. To lock the files themselves, keep the library in an encrypted disk image (Disk Utility can make one).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Tags") {
                Toggle("Also write tags as Finder tags", isOn: $writeFinderTags)
                Text("Tags always live in the library's database, whether or not this is on. With it on, they're also set as macOS Finder tags on the library files themselves.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Collections") {
                Toggle("Add files to the collection automatically", isOn: $autoAddToCollection)
                Text("When a file that isn't in a show's collection goes into the show, add it to the collection without asking. Off: ShowTools asks first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Export") {
                Toggle("Strip metadata from exported files", isOn: $stripOnExport)
                Text(stripOnExport
                     ? "File ▸ Export Show… removes location, camera, dates and other details from the copies it makes. Audio files keep their title, artist and album; only the buyer's details come off. The files in the library are never changed."
                     : "Exported copies are exact copies of the library's files, with their location, camera and date still in them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Alerts") {
                Toggle("Explain what removing a slide does", isOn: Binding(
                    get: { !suppressRemovalNotice },
                    set: { suppressRemovalNotice = !$0 }))
                Text("The notice that a slide removed from a show isn't moved to the Trash.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Developer-only: lets a script open a show and start the player without
/// clicking, so the app can be checked from the command line. Inert unless
/// the environment variable is set.
///
///   SHOWTOOLS_DEV_PLAY="<showID>:<slideIndex>[:full]"
///   SHOWTOOLS_DEV_SHOW="<showID>[:<slideIndex>]"   select a show (and a slide)
@MainActor
enum DevHooks {
    static func run(_ model: AppModel) {
        if let spec = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_SHOW"] {
            let parts = spec.split(separator: ":")
            if let id = parts.first.flatMap({ Int64($0) }), let show = model.show(id) {
                model.sidebar = .show(id)
                if parts.count > 1, let i = Int(parts[1]), show.slides.indices.contains(i) {
                    model.devSelection = show.slides[i].id
                }
            }
        }
        guard let spec = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_PLAY"] else { return }
        let parts = spec.split(separator: ":")
        guard let id = parts.first.flatMap({ Int64($0) }), let show = model.show(id) else { return }
        model.sidebar = .show(id)
        let index = parts.count > 1 ? Int(parts[1]) : nil
        Player.open(show: show, model: model, fullScreen: parts.contains("full"), startAt: index)
    }
}
