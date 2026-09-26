import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

@main
struct ShowToolsApp: App {
    @State private var model = AppModel()
    @State private var undoState = UndoMenuState()

    // Catches the reason string of the crash the app has been having
    // (ExceptionProbe). Remove with the probe.
    init() { ExceptionProbe.install(); LayoutLoopProbe.install() }

    var body: some Scene {
        Window("ShowTools", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { DevHooks.run(model); BGToolsHelper.launchAtShowToolsStartupIfEnabled() }
        }
        .defaultSize(width: 1320, height: 820)
        .commands { AppCommands(model: model, undoState: undoState) }

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

/// Tracks the key window's own `UndoManager`, so Edit ▸ Undo/Redo work
/// from any window a pane can pop out into. SwiftUI's own automatic
/// Undo/Redo commands are scoped to its `Scene` graph, which a PaneKit
/// pop-out sits outside of — found 2026-09-25 (`spec/panekit.md`, "Pane
/// ⇄ panel"): the popped-out Inspector's own edits weren't undoable from
/// its own window with SwiftUI's automatic commands, even though
/// `PanePanel.undoManager` correctly returned the same shared
/// `UndoManager` (checked by `ObjectIdentifier`). This replaces those
/// commands with ones that ask `NSApp.keyWindow?.undoManager` directly,
/// so it works the same in the main window, the Slide Editor, the
/// library panel and any future pop-out — they already share one
/// `UndoManager` per `spec/windows.md`'s "undo follows."
@MainActor @Observable
final class UndoMenuState {
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoName: String?
    private(set) var redoName: String?
    private weak var manager: UndoManager?
    private var tokens: [NSObjectProtocol] = []

    init() {
        // NotificationCenter hands these to a non-isolated closure even
        // though they always land on the main queue (matches the same
        // pattern EditShowView's KeyView uses for NSEvent monitors).
        let nc = NotificationCenter.default
        let onNotify: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        tokens = [
            // Reads `NSApp.keyWindow` rather than the notification's own
            // `.object`, which Swift 6 won't let a non-isolated closure
            // send across into `MainActor.assumeIsolated` here.
            nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.manager = NSApp.keyWindow?.undoManager
                    self?.refresh()
                }
            },
            // The ObjC constant names, unmangled: Swift's Foundation
            // overlay doesn't vend these as `NSUndoManager` statics.
            nc.addObserver(forName: Notification.Name("NSUndoManagerCheckpointNotification"),
                           object: nil, queue: .main, using: onNotify),
            nc.addObserver(forName: Notification.Name("NSUndoManagerDidUndoChangeNotification"),
                           object: nil, queue: .main, using: onNotify),
            nc.addObserver(forName: Notification.Name("NSUndoManagerDidRedoChangeNotification"),
                           object: nil, queue: .main, using: onNotify),
            // A group closed with its action already in it. Checkpoint
            // alone misses a step registered outside an event: its only
            // checkpoint comes before the action is registered (measured
            // 2026-09-25, the grid's drag-to-reorder).
            nc.addObserver(forName: Notification.Name("NSUndoManagerDidCloseUndoGroupNotification"),
                           object: nil, queue: .main, using: onNotify),
        ]
        manager = NSApp.keyWindow?.undoManager
        refresh()
    }

    private func refresh() {
        canUndo = manager?.canUndo ?? false
        canRedo = manager?.canRedo ?? false
        undoName = canUndo ? manager?.undoActionName : nil
        redoName = canRedo ? manager?.redoActionName : nil
    }

    func undo() { manager?.undo() }
    func redo() { manager?.redo() }

    isolated deinit {
        let nc = NotificationCenter.default
        for t in tokens { nc.removeObserver(t) }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    let undoState: UndoMenuState
    @FocusedValue(\.activeShowID) private var activeShowID
    @FocusedValue(\.librarySelectionCount) private var librarySelectionCount
    @FocusedValue(\.requestLibraryRename) private var requestLibraryRename
    @FocusedValue(\.requestLibraryGetInfo) private var requestLibraryGetInfo
    @FocusedValue(\.requestLibraryQuickLook) private var requestLibraryQuickLook
    @FocusedValue(\.requestNewCollection) private var requestNewCollection
    // Batch 5 (A2, F1–F4, G5): the open show's slide selection and its
    // Duplicate/Get Info, and Edit Show's transport and timeline commands —
    // absent whenever no show, or no Edit Show, has the window.
    @FocusedValue(\.activeSlideSelection) private var activeSlideSelection
    @FocusedValue(\.requestDuplicateSlides) private var requestDuplicateSlides
    @FocusedValue(\.requestSlideGetInfo) private var requestSlideGetInfo
    // Not `@FocusedValue` any more (found 2026-09-25, `spec/panekit.md`,
    // "The order," step 5): that's scoped to SwiftUI's own Scene graph,
    // so it never reached these menus while the Timeline pane's
    // popped-out window was key. `model.editShowCommands` is a plain
    // stored property, reachable regardless of which window is key.
    private var editShowCommands: EditShowCommandsValue? { model.editShowCommands }
    @AppStorage("frameStripShown") private var frameStripShown = true
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("editMode") private var mode: EditMode = .slides
    @AppStorage("snapping") private var snapping = true
    @AppStorage("storylineZoom") private var pps: Double = 24
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replaces SwiftUI's automatic Undo/Redo (`UndoMenuState`, above):
        // theirs is scoped to SwiftUI's own Scene graph, so a PaneKit
        // pop-out's window never registered with it.
        CommandGroup(replacing: .undoRedo) {
            Button(undoState.undoName.map { "Undo \($0)" } ?? "Undo") { undoState.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!undoState.canUndo)
            Button(undoState.redoName.map { "Redo \($0)" } ?? "Redo") { undoState.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!undoState.canRedo)
        }

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
            Button("Quick Look") { requestLibraryQuickLook?() }
                .keyboardShortcut("y")
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
            // Item 13: Edit Show's Browser is a drawer now, closing to its
            // own edge handle beside the inspector's (`EditColumnsLayout`).
            Toggle("Show Browser", isOn: Binding(
                get: { model.editShowColumns.isOpen(EditColumnsLayout.browserSplit) },
                set: { model.editShowColumns.setOpen(EditColumnsLayout.browserSplit, $0) }))
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(editShowCommands == nil)
            // Item 30, `ShowTools Feedback — Worklist for Next CC
            // Session.md`: the timeline pane could already collapse to its
            // own edge handle (every PaneKit split is collapsible by
            // default) — dragging its divider past half its floor, or
            // double-clicking it, already did it — but nothing discoverable
            // offered it, unlike Library/Frame Strip/Inspector just above,
            // which all get a View menu toggle. This is that toggle; the
            // handle it collapses to is PaneKit's own standard one, already
            // built (`PaneEdgeHandleView`).
            Toggle("Show Timeline", isOn: Binding(get: { model.mainPanes.isOpen("window") },
                                                  set: { model.mainPanes.setOpen("window", $0) }))
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(activeShowID == nil)
            // Step 4, third piece (`spec/windows.md`): the first detachable
            // area. `editShowCommands` gates it to Edit Show, same as the
            // zoom and Go Back/Forward items below — Edit Slides' own
            // inspector doesn't pop out yet.
            Toggle("Inspector in Its Own Window", isOn: Binding(
                get: { model.editShowColumns.isPoppedOut("inspector") },
                set: { _ in model.editShowColumns.togglePopOut("inspector") }))
                .disabled(editShowCommands == nil)
            // Step 4's last piece: the timeline pane (`spec/windows.md`,
            // "The timeline pane"). Lives in `model.mainPanes` now, full
            // width under the Library pane too, not `model.editShowColumns`
            // (`spec/panekit.md`, "The order," step 5's follow-up,
            // 2026-09-25). Pops out as an ordinary window, so it can go
            // behind — unlike the Inspector's panel, which floats.
            Toggle("Timeline in Its Own Window", isOn: Binding(
                get: { model.mainPanes.isPoppedOut("storyline") },
                set: { _ in model.mainPanes.togglePopOut("storyline") }))
                .disabled(editShowCommands == nil)
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
            Divider()
            // W8, item 7: the playhead's own history — out of ⌘Z on
            // purpose (plan, "Go Back, not undo"). ⌘[ / ⌘], as in Finder
            // and Safari.
            Button("Go Back") { editShowCommands?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(editShowCommands?.canGoBack ?? false))
            Button("Go Forward") { editShowCommands?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(editShowCommands?.canGoForward ?? false))
            Divider()
            Toggle("Snapping  (N)", isOn: $snapping)
                .disabled(editShowCommands == nil)
            Divider()
            Button("Restore Default Layout") {
                model.mainPanes.restoreDefaults()
                model.editShowColumns.restoreDefaults()
                model.editSlidesColumns.restoreDefaults()
                model.previewPanes.restoreDefaults()
                DefaultLayout.restore()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
        }

        // Item 21, `ShowTools Feedback — Worklist for Next CC Session.md`:
        // a dedicated menu for launching BGTools, more discoverable than
        // the toolbar group it lived in before. "Open at Login" stays in
        // BGTools' own window (View ▸ BGTools ▸ Desktop Show…, its
        // Settings tab) — this menu is only for launching it, and the new
        // "launch with ShowTools" setting, which lives in ShowTools'
        // own Settings alongside its other startup-time preferences.
        CommandMenu("BGTools") {
            // Phase 5: the desktop is BGTools' job, and it lives inside
            // this app (spec/bgtools.md, spec/xcode-port.md).
            Button("Desktop Show…") {
                do { try BGToolsHelper.openDesktop() } catch { NSAlert(error: error).runModal() }
            }
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
            // W7: modifier-clicks on the range button, restated here since a
            // modifier-click can't be seen (F1).
            Button("Set Range to View") { editShowCommands?.setRangeToView() }
                .disabled(editShowCommands == nil)
            Button("Set Range to Whole Show") { editShowCommands?.setRangeToWholeShow() }
                .disabled(editShowCommands == nil)
            Toggle("Lock Range", isOn: Binding(
                get: { editShowCommands?.rangeLocked ?? false },
                set: { _ in editShowCommands?.toggleRangeLock() }))
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
    @AppStorage("showSlideProgress") private var showSlideProgress = true
    @AppStorage(BGToolsHelper.launchWithShowToolsKey) private var launchBGToolsWithShowTools = false

    var body: some View {
        ScrollView {
            form
        }
        .frame(width: 520)
        .frame(maxHeight: Self.maxHeight)
    }

    /// Caps the window to fit under the screen's menu bar and dock rather
    /// than letting the Form grow past the bottom edge (item 9,
    /// `ShowTools Feedback — Worklist for Next CC Session.md`). A fixed
    /// margin below the visible frame, not the whole screen height, so it
    /// never touches the menu bar or dock even centered.
    private static var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 80
    }

    private var form: some View {
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
            Section("Playback") {
                Toggle("Show the slide progress line", isOn: $showSlideProgress)
                Text("The thin white line along the bottom of the picture that fills through each slide. Also in the viewer's own right-click menu.")
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
            // Item 21, `ShowTools Feedback — Worklist for Next CC
            // Session.md`. "Open BGTools at Login" already lives in
            // BGTools' own window (View ▸ BGTools ▸ Launch BGTools, then
            // its Settings tab) — this is the separate ask: BGTools
            // starting alongside ShowTools itself, not just at login.
            Section("BGTools") {
                Toggle("Launch BGTools when ShowTools launches", isOn: $launchBGToolsWithShowTools)
                Text("Starts the desktop background player in the background, without opening its window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
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
