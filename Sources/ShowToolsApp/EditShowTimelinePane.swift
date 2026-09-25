import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// The timeline pane: the transport and the storyline, full width under
/// the Library pane, not just the detail column (`spec/windows.md`, "The
/// timeline pane"; `spec/panekit.md`, "The order," step 5's follow-up,
/// 2026-09-25). Built the first time as one of Edit Show's own three
/// columns' siblings, nested inside `model.editShowColumns` — which only
/// ever gave it the detail pane's width, not the window's, missing the
/// original sketch in `spec/panekit.md`, "What it is": `split(top/bottom)
/// { split(left|rest) { library, detail }, timeline }`. Moved to live in
/// `model.mainPanes` instead (`AppModel.swift`), rendered by `MainView`
/// independently of `EditShowView` — both read the same `ShowSession`, so
/// they stay in sync with no explicit synchronization needed, and neither
/// has to mutate `@Observable` state for the other to read mid-render.
///
/// Owns everything about the transport and storyline that isn't the show
/// session or the engine itself (both `EditShowView`'s, still): the range,
/// arrow-key and row-navigation logic, Go Back/Forward, and the Show/View
/// menu commands (`AppModel.editShowCommands`). `EditShowView` keeps the
/// engine's own lifecycle (`.task(id: show.id)`, `.onDisappear`) — this
/// view just reads `session.engine`.
struct EditShowTimelinePane: View {
    let show: Show
    let timeline: ShowTimeline
    let session: ShowSession
    /// Whether Edit Show is the current mode. False while Edit Slides has
    /// the show open: the bar still occupies its place (item 19, feedback
    /// worklist), greyed out rather than gone, since the engine that drives
    /// it only exists while Edit Show is on screen (`EditShowView`'s own
    /// `.task`/`.onDisappear`). The drag-and-drop question a greyed bar
    /// raises (item 33) is still open — Jason wants a working copy to play
    /// with before deciding, so this stays a plain visual state for now.
    let active: Bool
    let mutate: ShowMutator
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @AppStorage("snapping") private var snapping = true
    @AppStorage("storylineZoom") private var pps: Double = 24
    @State private var visibleWidth: CGFloat = 800

    var body: some View {
        @Bindable var session = session
        Group {
            if active, let engine = session.engine, engine.showID == show.id {
                VStack(spacing: 0) {
                    TransportRow(engine: engine, show: show, pps: $pps, fit: fitStoryline,
                                 setRangeToView: setRangeToView, setRangeToWholeShow: setRangeToWholeShow,
                                 clearRange: clearRange, toggleRangeLock: { toggleRangeLock(engine) })
                    Divider()
                    StorylineView(show: show, timeline: timeline, engine: engine, session: session,
                                  selection: $session.selection, selectedTransition: $session.selectedTransition,
                                  selectedOverlay: $session.selectedOverlay, selectedSong: $session.selectedSong,
                                  selectedMarkers: $session.selectedMarkers,
                                  pps: $pps, scrollOffset: $session.storylineOffset, mutate: mutate,
                                  openSlideEditor: { id in
                                      SlideEditorWindow.show(slideID: id, show: show, model: model,
                                                             mutate: mutate, undoManager: undoManager)
                                  })
                }
                .background(shortcuts(engine))
            } else {
                TimelinePanePlaceholder()
            }
        }
        .onDisappear {
            // Matches the old FocusedValue's own absence outside Edit
            // Show (spec/hig-audit.md, "G"): leaving this view — by
            // switching to Edit Slides or away from the show entirely —
            // disables the Show/View menu's editShowCommands items again.
            model.editShowCommands = nil
        }
    }

    /// M, while listening: a marker at the playhead, on the show's clock.
    /// Not a second one on top of one already there.
    private func addMarker(_ engine: PlaybackEngine) {
        let t = (engine.timeline.wrap(engine.now) * 100).rounded() / 100
        guard !show.markers.contains(where: { abs($0.time - t) < 0.05 }) else { return }
        mutate("Add Marker") { $0.markers.append(Marker(time: t)) }
    }

    private func fitStoryline() {
        guard timeline.duration > 0 else { return }
        pps = min(max(Double(visibleWidth - StorylineView.inset * 2 - 40) / timeline.duration, 2), 400)
    }

    // MARK: Range (W6/W7, work order item 6)

    /// I: the range's start at the playhead. O: its end. Both undoable now
    /// — a deliberate edit, like any other — so they go through `mutate`,
    /// not `engine.updateEditor`. Locked ends still take the keys (a key
    /// is a deliberate act; only a drag or a modifier-click is refused).
    private func setRangeIn(_ engine: PlaybackEngine) {
        let t = engine.roundedNow
        mutate("Set Range In") { s in
            s.editor.rangeIn = t
            if let o = s.editor.rangeOut, o <= t { s.editor.rangeOut = nil }
            s.editor.rangeOn = true
        }
    }

    private func setRangeOut(_ engine: PlaybackEngine) {
        let t = engine.roundedNow
        mutate("Set Range Out") { s in
            s.editor.rangeOut = t
            if let i = s.editor.rangeIn, i >= t { s.editor.rangeIn = nil }
            s.editor.rangeOn = true
        }
    }

    /// ⌥X: also takes a locked range, like I and O.
    private func clearRange() {
        guard show.editor.rangeIn != nil || show.editor.rangeOut != nil else { return }
        mutate("Clear Range") { $0.editor.rangeIn = nil; $0.editor.rangeOut = nil }
    }

    /// A plain click on the range button with no range set, ⌥⌘-click, and
    /// the Show menu's "Set Range to View": the range becomes the stretch
    /// of the timeline in view. Refuses a locked range, with a beep.
    private func setRangeToView() {
        guard !show.editor.rangeLocked else { NSSound.beep(); return }
        guard timeline.duration > 0 else { return }
        let lo = max((Double(session.storylineOffset) - StorylineView.inset) / pps, 0)
        let hi = min(lo + Double(visibleWidth) / pps, timeline.duration)
        guard hi > lo + 0.05 else { return }
        mutate("Set Range") { s in
            s.editor.rangeIn = (lo * 100).rounded() / 100
            s.editor.rangeOut = (hi * 100).rounded() / 100
            s.editor.rangeOn = true
        }
    }

    /// ⇧⌥⌘-click and the Show menu's "Set Range to Whole Show": the range
    /// becomes the whole show, even where it's out of view. Refuses a
    /// locked range, with a beep.
    private func setRangeToWholeShow() {
        guard !show.editor.rangeLocked else { NSSound.beep(); return }
        guard timeline.duration > 0 else { return }
        mutate("Set Range") { s in
            s.editor.rangeIn = 0
            s.editor.rangeOut = (timeline.duration * 100).rounded() / 100
            s.editor.rangeOn = true
        }
    }

    /// The lock itself is a mode, like `rangeOn`, not an edit: not undone.
    private func toggleRangeLock(_ engine: PlaybackEngine) {
        engine.updateEditor { $0.rangeLocked.toggle() }
    }

    // MARK: Arrow keys (item 7, work order; spec/conventions.md §2, settled
    // 2026-09-24): ← → move through the items in the current row, ↑ ↓ move
    // between rows, and with nothing selected, ← → nudge the playhead
    // instead, as in the ruler.

    /// Whichever selection is active names the current row — they're kept
    /// mutually exclusive in `EditShowView`'s own `onChange` handlers.
    /// Nil means nothing's selected: ← → falls back to the playhead, and
    /// ↑ ↓ starts from the slides row.
    private var currentRow: TimelineRow.Kind? {
        if !session.selection.isEmpty { return .slides }
        if session.selectedTransition != nil { return .transitions }
        if session.selectedOverlay != nil { return .images }
        if session.selectedSong != nil { return .music }
        return nil
    }

    /// The time whatever's selected sits at, for ↑ ↓ to land near when it
    /// switches rows; the playhead's, with nothing selected.
    private func currentTime(_ engine: PlaybackEngine) -> Double {
        if let id = session.slideCursor ?? session.selection.first,
           let r = timeline.slides.first(where: { $0.slide.id == id }) { return r.start }
        if let id = session.selectedTransition, let r = timeline.slides.first(where: { $0.slide.id == id }) {
            return r.start
        }
        if let id = session.selectedOverlay, let o = show.overlays.first(where: { $0.id == id }) { return o.start }
        if let id = session.selectedSong, let c = show.music.first(where: { $0.id == id }) { return c.start }
        return engine.timeline.wrap(engine.now)
    }

    /// ← → within the current row (batch 4's `GridSelection`): the slides
    /// row supports ⇧ to extend, like a ⇧-click; the others are
    /// single-selection in this UI, so ⇧ has no effect there. Nothing
    /// selected: nudge the playhead instead.
    private func moveSelection(_ delta: Int, extend: Bool, engine: PlaybackEngine) {
        guard let row = currentRow else { nudgePlayhead(delta, engine: engine); return }
        switch row {
        case .slides:
            let items = timeline.slides.map(\.slide.id)
            let r = GridSelection.step(from: session.slideCursor, by: delta, anchor: session.slideAnchor,
                                       base: session.slideAnchorBase, in: items, extend: extend)
            session.selection = r.selected
            session.slideAnchor = r.anchor
            session.slideAnchorBase = r.base
            session.slideCursor = r.cursor
            if let id = r.cursor { engine.showSlide(id: id) }
        case .transitions:
            let items = timeline.slides.map(\.slide.id)
            session.selectedTransition = GridSelection.step(from: session.selectedTransition, by: delta,
                                                             anchor: nil, base: [], in: items, extend: false).cursor
        case .images:
            let items = show.overlays.sorted { $0.start < $1.start }.map(\.id)
            session.selectedOverlay = GridSelection.step(from: session.selectedOverlay, by: delta,
                                                          anchor: nil, base: [], in: items, extend: false).cursor
        case .music:
            let items = show.music.sorted { $0.start < $1.start }.map(\.id)
            session.selectedSong = GridSelection.step(from: session.selectedSong, by: delta,
                                                       anchor: nil, base: [], in: items, extend: false).cursor
        }
    }

    /// ↑ ↓ between rows, in the show's own row order (a live drag of a
    /// row's handle isn't in play while a key is being pressed, so
    /// `show.rows` — not the storyline's own `displayRows` — is enough).
    /// Lands on whichever item in the new row sits nearest the old
    /// selection's time; nothing selected starts at the slides row,
    /// nearest the playhead.
    private func moveRow(_ delta: Int, engine: PlaybackEngine) {
        let kinds = show.rows.map(\.kind)
        guard !kinds.isEmpty else { return }
        let time = currentTime(engine)
        if let row = currentRow, let i = kinds.firstIndex(of: row) {
            let to = min(max(i + delta, 0), kinds.count - 1)
            guard to != i else { return }
            selectNearest(in: kinds[to], to: time, engine: engine)
        } else {
            selectNearest(in: kinds.contains(.slides) ? .slides : kinds[0], to: time, engine: engine)
        }
    }

    private func selectNearest(in kind: TimelineRow.Kind, to time: Double, engine: PlaybackEngine) {
        session.selection = []; session.selectedTransition = nil
        session.selectedOverlay = nil; session.selectedSong = nil
        switch kind {
        case .slides:
            guard let r = timeline.slides.min(by: { abs($0.start - time) < abs($1.start - time) }) else { return }
            let res = GridSelection.click(r.slide.id)
            session.selection = res.selected; session.slideAnchor = res.anchor
            session.slideAnchorBase = res.base; session.slideCursor = res.cursor
            engine.showSlide(id: r.slide.id)
        case .transitions:
            session.selectedTransition = timeline.slides.min { abs($0.start - time) < abs($1.start - time) }?.slide.id
        case .images:
            session.selectedOverlay = show.overlays.min { abs($0.start - time) < abs($1.start - time) }?.id
        case .music:
            session.selectedSong = show.music.min { abs($0.start - time) < abs($1.start - time) }?.id
        }
    }

    /// One frame (item 7, work order: "← → nudge the playhead"). A
    /// deliberate nudge, so it's its own Go Back step (W8).
    private func nudgePlayhead(_ delta: Int, engine: PlaybackEngine) {
        recordPlayheadJump(engine)
        if engine.isPlaying { engine.pause() }
        let t = engine.timeline.wrap(engine.now) + Double(delta) / 30
        engine.seek(min(max(t, 0), max(engine.duration - 0.001, 0)))
    }

    // MARK: Go Back / Go Forward (W8, item 7; plan, "Go Back, not undo")

    /// Push the position as it is right now, before a jump changes it —
    /// called at a ruler click/drag's start (`StorylineView`) and before
    /// each keyboard nudge. Clears Go Forward: a genuinely new jump isn't
    /// a redo of one just undone by Go Back.
    private func recordPlayheadJump(_ engine: PlaybackEngine) {
        session.goBackHistory.append(.current(engine: engine, timeline: timeline, pps: pps,
                                              scrollOffset: session.storylineOffset))
        session.goForwardHistory = []
    }

    private func goBack(_ engine: PlaybackEngine) {
        guard let step = session.goBackHistory.popLast() else { return }
        session.goForwardHistory.append(.current(engine: engine, timeline: timeline, pps: pps,
                                                  scrollOffset: session.storylineOffset))
        apply(step, engine)
    }

    private func goForward(_ engine: PlaybackEngine) {
        guard let step = session.goForwardHistory.popLast() else { return }
        session.goBackHistory.append(.current(engine: engine, timeline: timeline, pps: pps,
                                              scrollOffset: session.storylineOffset))
        apply(step, engine)
    }

    private func apply(_ step: PlayheadStep, _ engine: PlaybackEngine) {
        if engine.isPlaying { engine.pause() }
        engine.seek(step.time)
        pps = step.pps
        session.pendingScroll = step.leadingSlideID
    }

    /// What the Show/View menu commands need refreshed for
    /// (`editShowCommands`, below): everything else in
    /// `EditShowCommandsValue` is a closure that reads live state when
    /// called (through `mutate`/`engine`, never a captured snapshot), so
    /// only these four plus the show itself need to be watched.
    private struct CommandsTrigger: Equatable {
        var showID: Int64
        var rangeLocked: Bool
        var loopOn: Bool
        var canGoBack: Bool
        var canGoForward: Bool
    }

    /// Keyboard shortcuts: Final Cut's J/K/L, space, and its M (marker), I
    /// and O (range), N (snapping), and the arrow keys — bare keys, so
    /// `SingleKeys` handles them (never `.keyboardShortcut`,
    /// which would become a window key equivalent AppKit offers before
    /// the focused text field, stealing "j" or a space out of Search —
    /// audit M4). ⌘L (loop), ⌘=/⌘− (zoom), ⌥X (clear range) and ⇧Z (fit)
    /// all need a modifier, so they're safe as real menu shortcuts
    /// instead (F1, batch 5) — `editShowCommands`, below, publishes the
    /// actions the Show and View menus call.
    ///
    /// **Not `.focusedSceneValue` any more** (`spec/panekit.md`, "The
    /// order," step 5, found 2026-09-25): that's scoped to SwiftUI's own
    /// `Scene` graph, so it never reached the Show/View menus while the
    /// Timeline pane's popped-out window was key, even though its content
    /// — this view — was still live and on screen. `model.editShowCommands`
    /// is a plain stored property, so it's reachable regardless of which
    /// window is key, the same fix `UndoMenuState` made for Undo/Redo.
    /// Pushed via `onChange` rather than written directly in `body`
    /// (SwiftUI doesn't allow mutating `@Observable` state during a view
    /// update) — **and reading `show`, not `engine.show`**, since
    /// `PlaybackEngine.show` is `@ObservationIgnored` (showtools-gotchas):
    /// reading it here would silently stop `CommandsTrigger` from ever
    /// refreshing.
    private func shortcuts(_ engine: PlaybackEngine) -> some View {
        ZStack {
            SingleKeys { event in
                switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased(), event.plainModifiers) {
                case (49, _, []): engine.togglePlay()                  // space
                case (_, "j", []): engine.shuttle(-1)
                case (_, "k", []): engine.shuttle(0)
                case (_, "l", []): engine.shuttle(1)
                case (_, "m", []): addMarker(engine)
                case (_, "i", []): setRangeIn(engine)
                case (_, "o", []): setRangeOut(engine)
                case (_, "n", []): snapping.toggle()
                // Delete/⌫ isn't handled here: MainView's own Delete/⌘Delete
                // handler tries the lane's selection first (`SlideActions
                // .removeSelected`), before its sidebar fallback — one
                // handler, so there's no race between two `SingleKeys`
                // instances on the same window over the same keypress
                // (found 2026-09-25, `spec/panekit.md` step 5's follow-up).
                case (123, _, []): moveSelection(-1, extend: false, engine: engine)     // ←
                case (123, _, [.shift]): moveSelection(-1, extend: true, engine: engine)
                case (124, _, []): moveSelection(1, extend: false, engine: engine)      // →
                case (124, _, [.shift]): moveSelection(1, extend: true, engine: engine)
                case (126, _, []): moveRow(-1, engine: engine)                          // ↑
                case (125, _, []): moveRow(1, engine: engine)                           // ↓
                default: return false
                }
                return true
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .background(GeometryReader { g in
            Color.clear.onAppear { visibleWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in visibleWidth = w }
        })
        .onChange(of: CommandsTrigger(showID: show.id, rangeLocked: show.editor.rangeLocked,
                                      loopOn: show.editor.loopPlayback,
                                      canGoBack: !session.goBackHistory.isEmpty,
                                      canGoForward: !session.goForwardHistory.isEmpty),
                 initial: true) { _, t in
            model.editShowCommands = EditShowCommandsValue(
                togglePlay: { engine.togglePlay() },
                addMarker: { addMarker(engine) },
                setRangeIn: { setRangeIn(engine) },
                setRangeOut: { setRangeOut(engine) },
                clearRange: clearRange,
                setRangeToView: setRangeToView,
                setRangeToWholeShow: setRangeToWholeShow,
                toggleRangeLock: { toggleRangeLock(engine) },
                rangeLocked: t.rangeLocked,
                toggleLoop: { engine.updateEditor { $0.loopPlayback.toggle() } },
                loopOn: t.loopOn,
                zoomToFit: fitStoryline,
                goBack: { goBack(engine) },
                goForward: { goForward(engine) },
                canGoBack: t.canGoBack,
                canGoForward: t.canGoForward)
        }
    }
}

/// Item 19, feedback worklist: the timeline pane's stand-in while Edit
/// Slides has the show open. Same chrome as the real transport bar
/// (`TransportRow`) so switching modes doesn't reflow the window, but
/// dimmed and inert — there's no live `PlaybackEngine` to show real state,
/// since one only exists while Edit Show is on screen. What a drop onto
/// this bar should do (item 33) is still an open question for Jason.
private struct TimelinePanePlaceholder: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "backward.end.fill")
                Image(systemName: "play.fill").frame(width: 14)
                Image(systemName: "forward.end.fill")
                Slider(value: .constant(0), in: 0...1).disabled(true)
                Text("--:-- / --:--")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 110, alignment: .trailing)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
            Divider()
            Text("Switch to Edit Show to use the timeline")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.secondary)
        }
        .allowsHitTesting(false)
    }
}
