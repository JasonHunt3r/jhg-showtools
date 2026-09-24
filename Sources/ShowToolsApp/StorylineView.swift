import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// The show as a Final Cut-style storyline: one block per slide, as wide as
/// the slide is long, sitting end to end.
///
/// - Magnetic: dragging a block (or a selection of them) reorders, and the
///   rest close up around it. No gaps, ever.
/// - Trim: drag a block's right edge to change its length; what follows
///   shifts along.
/// - The ruler and the playhead share the engine's clock.
struct StorylineView: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    @Binding var selection: Set<Int64>
    /// The anchor for ⇧-click (batch 4, E1): the last plain or ⌘-click,
    /// not derived from `selection` itself (the old bug used the first
    /// selected slide instead, which isn't the same thing once ⌘-click has
    /// moved the anchor elsewhere). `selectionBase` is `selection` at the
    /// moment the anchor was last set, for `GridSelection`'s ⇧-click to
    /// union with — local to the storyline, not shared with Edit Slides,
    /// which is a plain `List` and doesn't need it.
    @State private var anchor: Int64?
    @State private var selectionBase: Set<Int64> = []
    /// The transition selected in the lane, by the slide it leads into.
    @Binding var selectedTransition: Int64?
    /// The image selected in the lane's images row.
    @Binding var selectedOverlay: UUID?
    /// The song selected in the music row.
    @Binding var selectedSong: UUID?
    /// Markers selected on the ruler: dragging one moves them all.
    @Binding var selectedMarkers: Set<UUID>
    /// Points per second: the zoom.
    @Binding var pps: Double
    /// How far the storyline is scrolled, for the frame strip to follow.
    @Binding var scrollOffset: CGFloat
    let mutate: ShowMutator
    let openInspector: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    /// N: edges land on markers (plan, Phase 3). App-wide, like Final Cut's.
    @AppStorage("snapping") private var snapping = true

    /// Markers being dragged: which, and how far.
    private struct MarkerDrag {
        let ids: Set<UUID>
        var dt: Double
    }
    @State private var markerDrag: MarkerDrag?

    /// Every marker where it's drawn, a drag in progress applied: the hand
    /// markers (no song), and each song's detected ones that are showing.
    private var markerTimes: [(marker: Marker, time: Double, song: UUID?)] {
        let hand = show.markers.map { ($0, $0.time, UUID?.none) }
        let detected = show.detectedMarkers.map { ($0.marker, $0.time, UUID?.some($0.clipID)) }
        return (hand + detected).map { m, t, song in
            let moving = markerDrag?.ids.contains(m.id) == true
            return (m, max(t + (moving ? markerDrag!.dt : 0), 0), song)
        }
    }

    /// What a dragged edge snaps to (markers of both kinds), and from how
    /// far (six points), or nil with snapping off.
    private var snap: (targets: [Double], tolerance: Double)? {
        let targets = show.markers.map(\.time) + show.detectedMarkers.map(\.time)
        return snapping && !targets.isEmpty ? (targets, 6 / pps) : nil
    }

    /// The beat detection sheet, open for this stretch of the show.
    @State private var beatSheet: BeatSheet.Request?
    /// The markers the open sheet would place, drawn faintly on the ruler.
    @State private var beatPreview: [Double] = []

    static let blockHeight: CGFloat = 64
    static let rulerHeight: CGFloat = 22
    static let inset: CGFloat = 12
    /// The lane's transitions row.
    static let laneRowHeight: CGFloat = 22
    /// The images row, the same height empty or not (a faded placeholder
    /// holds its place).
    static let imagesRowHeight: CGFloat = 30
    /// The music row.
    static let musicRowHeight: CGFloat = 44
    static let rowGap: CGFloat = 4
    /// Where the rows start in the scrolling content: below the padding and
    /// the ruler.
    static let rowsOrigin: CGFloat = 6 + rulerHeight + 4

    static func height(of kind: TimelineRow.Kind) -> CGFloat {
        switch kind {
        case .images: imagesRowHeight
        case .transitions: laneRowHeight
        case .slides: blockHeight
        case .music: musicRowHeight
        }
    }

    /// Everything the storyline shows with every row in it: for the pane's
    /// size, which shouldn't have to scroll up and down.
    static var fullHeight: CGFloat {
        let rows = TimelineRow.Kind.allCases.reduce(0) { $0 + height(of: $1) + rowGap }
        return rowsOrigin + rows + 6
    }

    /// A transition section being dragged: drawn as it goes, saved on release.
    private struct TransitionEdit {
        enum Part { case start, end, body }
        /// The slide the transition leads into.
        let id: Int64
        let part: Part
        let lead0: Double, duration0: Double
        var lead: Double, duration: Double
        /// The longest the overlap can be: the shorter of the two slides.
        let limit: Double
    }
    @State private var transitionEdit: TransitionEdit?
    @State private var hoveredJoin: Int64?
    /// Something is being dragged over the images row: it lights up.
    @State private var imagesDropTargeted = false
    /// Files being dragged over the storyline: where the pointer is, for the
    /// insertion line.
    @State private var dropX: CGFloat?

    /// A row being dragged by its handle: where the pointer is, and the
    /// slot it would drop into. The rows rearrange as it goes; the show
    /// saves once, on release.
    private struct RowDrag {
        let id: UUID
        var target: Int
    }
    @State private var rowDrag: RowDrag?
    /// Rows whose drawers are open. View state only: not saved.
    @State private var openDrawers: Set<UUID> = []

    /// The show's rows in the order they're drawn: a row being dragged is
    /// already in its new slot.
    private var displayRows: [TimelineRow] {
        var rows = show.rows
        if let d = rowDrag, let i = rows.firstIndex(where: { $0.id == d.id }) {
            let r = rows.remove(at: i)
            rows.insert(r, at: min(d.target, rows.count))
        }
        return rows
    }

    /// Each row's top, from the top of the rows, in the order drawn.
    private func rowTop(_ kind: TimelineRow.Kind) -> CGFloat {
        var y: CGFloat = 0
        for r in displayRows {
            if r.kind == kind { return y }
            y += Self.height(of: r.kind) + Self.rowGap
        }
        return y
    }
    private var rowsHeight: CGFloat {
        displayRows.reduce(0) { $0 + Self.height(of: $1.kind) + Self.rowGap }
    }
    private var laneTop: CGFloat { rowTop(.transitions) }
    private var blocksTop: CGFloat { rowTop(.slides) }

    private struct Moving {
        var ids: Set<Int64>
        /// Where the pointer grabbed the group, from the group's left edge.
        var grab: CGFloat
        var pointerX: CGFloat
        var target: Int
    }
    @State private var moving: Moving?
    @State private var magnifyBase: Double?
    /// A click anywhere in the storyline brings the keyboard here, so
    /// Delete and Esc act on what was just selected, not the sidebar.
    @FocusState private var focused: Bool

    /// Final Cut's three edits at a cut, by where the pointer grabs it.
    enum EdgeKind: Equatable {
        /// Left of the cut: move the left clip's end. What follows ripples.
        case trimEnd(Int64)
        /// Right of the cut: move the right clip's start. What follows ripples.
        case trimStart(Int64)
        /// On the cut: move it, the left clip gaining what the right one loses.
        /// The show's total length doesn't change.
        case roll(Int64, Int64)
    }
    private struct EdgeEdit {
        var kind: EdgeKind
        /// Seconds the cut has moved; positive is to the right.
        var delta: Double
        var cutX: CGFloat
    }
    @State private var edge: EdgeEdit?
    @State private var hoveredEdge: EdgeKind?

    // MARK: Layout

    private struct Placed: Identifiable {
        let slide: ResolvedSlide
        let x: CGFloat
        let width: CGFloat
        var id: Int64 { slide.slide.id }
    }

    /// Lengths with any edge edit in progress applied.
    private func length(_ r: ResolvedSlide) -> Double {
        guard let e = edge else { return r.length }
        let id = r.slide.id
        switch e.kind {
        case .trimEnd(let a) where a == id: return r.length + e.delta
        case .trimStart(let b) where b == id: return r.length - e.delta
        case .roll(let a, _) where a == id: return r.length + e.delta
        case .roll(_, let b) where b == id: return r.length - e.delta
        default: return r.length
        }
    }

    /// Blocks in the order they'd sit if the drag in progress were dropped:
    /// the moving group pulled out and reinserted at its target.
    private func layout() -> (placed: [Placed], group: [Placed]) {
        var order = timeline.slides
        var group: [ResolvedSlide] = []
        if let m = moving {
            group = order.filter { m.ids.contains($0.slide.id) }
            order.removeAll { m.ids.contains($0.slide.id) }
            order.insert(contentsOf: group, at: min(m.target, order.count))
        }
        var x = Self.inset
        var placed: [Placed] = []
        for r in order {
            let w = CGFloat(length(r) * pps)
            placed.append(Placed(slide: r, x: x, width: w))
            x += w
        }
        return (placed, placed.filter { p in group.contains { $0.slide.id == p.id } })
    }

    /// The slides (with any trim in progress), or the longest row if one
    /// runs past them, plus room to drop things beyond the end.
    private var contentWidth: CGFloat {
        CGFloat(max(timeline.slides.reduce(0) { $0 + length($1) }, timeline.duration) * pps) + Self.inset * 2 + 200
    }

    // MARK: Body

    var body: some View {
        let (placed, group) = layout()
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    RulerView(duration: timeline.duration, pps: pps, inset: Self.inset)
                        .frame(width: contentWidth, height: Self.rulerHeight)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture)
                        .overlay(alignment: .topLeading) { rangeOnRuler }
                        .overlay(alignment: .topLeading) { markersOnRuler }
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: contentWidth, height: rowsHeight)
                        ImagesRow(show: show, timeline: timeline, engine: engine, pps: pps, inset: Self.inset,
                                  width: contentWidth, height: Self.imagesRowHeight, snap: snap,
                                  dropTargeted: $imagesDropTargeted, selectedOverlay: $selectedOverlay,
                                  mutate: mutate,
                                  didSelect: { selection = []; selectedTransition = nil; selectedSong = nil; focused = true })
                            .offset(y: rowTop(.images))
                        MusicRow(show: show, timeline: timeline, pps: pps, inset: Self.inset,
                                 width: contentWidth, height: Self.musicRowHeight,
                                 selectedSong: $selectedSong, mutate: mutate,
                                 setRange: { r in
                                     engine.updateEditor { $0.rangeIn = r.lowerBound; $0.rangeOut = r.upperBound; $0.rangeOn = true }
                                 },
                                 detectBeats: { clip in openBeatSheet(for: clip) },
                                 didSelect: { selection = []; selectedTransition = nil; selectedOverlay = nil; focused = true })
                            .offset(y: rowTop(.music))
                        ForEach(placed) { p in
                            let isMoving = moving?.ids.contains(p.id) == true
                            block(p)
                                .opacity(isMoving ? 0.25 : 1)
                                .offset(x: p.x, y: blocksTop)
                                .id(p.id)
                        }
                        if moving == nil {
                            transitionsRow(placed)
                            cutHandles(placed)
                        }
                        if let x = dropX {
                            let target = dropTarget(x, placed)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: Self.blockHeight + 8)
                                .offset(x: target.x - 1.5, y: blocksTop - 4)
                                .allowsHitTesting(false)
                        }
                        // The group being dragged follows the pointer.
                        if let m = moving, let first = group.first {
                            let groupWidth = group.reduce(0) { $0 + $1.width }
                            HStack(spacing: 0) {
                                ForEach(group) { p in block(p).frame(width: p.width) }
                            }
                            .frame(width: groupWidth, alignment: .leading)
                            .shadow(radius: 6)
                            .offset(x: m.pointerX - m.grab, y: blocksTop - 6)
                            .allowsHitTesting(false)
                            .id("dragging-\(first.id)")
                        }
                    }
                    .animation(.snappy(duration: 0.18), value: moving?.target)
                    .animation(.snappy(duration: 0.18), value: displayRows.map(\.id))
                    .onDrop(of: ItemDrag.accepted, delegate: StorylineDrop(
                        update: { dropX = $0?.x },
                        perform: { providers, location in drop(providers, at: location.x, placed) }))
                }
                .overlay(alignment: .topLeading) { linesThroughRows }
                .overlay(alignment: .topLeading) { Playhead(engine: engine, timeline: timeline, pps: pps, inset: Self.inset) }
                .coordinateSpace(name: "storyline")
                .padding(.vertical, 6)
                .background(GeometryReader { g in
                    Color.clear.preference(key: StorylineScrollKey.self,
                                           value: -g.frame(in: .named("storylineScroll")).minX)
                })
            }
            .coordinateSpace(name: "storylineScroll")
            .overlay(alignment: .topLeading) { rowHandles }
            .onPreferenceChange(StorylineScrollKey.self) { scrollOffset = $0 }
            .onChange(of: engine.currentIndex) { _, i in
                // Keep the playing slide in view.
                guard engine.isPlaying, timeline.slides.indices.contains(i) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(timeline.slides[i].slide.id, anchor: .center) }
            }
        }
        .gesture(MagnifyGesture()
            .onChanged { v in
                if magnifyBase == nil { magnifyBase = pps }
                pps = min(max((magnifyBase ?? pps) * v.magnification, 2), 400)
            }
            .onEnded { _ in magnifyBase = nil })
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        // An open Rhythm tool follows the show on screen.
        .onAppear { RhythmTool.shared.follow(showID: show.id, undoManager: undoManager) }
        .onChange(of: show.id) { RhythmTool.shared.follow(showID: show.id, undoManager: undoManager) }
        // The Rhythm tool's Listen plays here, on this show's engine.
        .onChange(of: RhythmTool.shared.listening) { _, on in
            let tool = RhythmTool.shared
            if on, tool.showID == show.id {
                engine.onListenEnded = { tool.listening = false }
                engine.listen(listenRange, clicks: tool.preview)
            } else {
                engine.stopListening()
            }
        }
        .onChange(of: RhythmTool.shared.preview) { _, clicks in
            if RhythmTool.shared.listening { engine.updateListening(listenRange, clicks: clicks) }
        }
        .sheet(item: $beatSheet) { req in
            BeatSheet(request: req, show: show, timeline: timeline, preview: $beatPreview, mutate: mutate)
        }
        .onKeyPress(.escape) {
            if !openDrawers.isEmpty {
                openDrawers = []
                return .handled
            }
            guard selectedOverlay != nil || selectedSong != nil || !selectedMarkers.isEmpty else { return .ignored }
            selectedOverlay = nil
            selectedSong = nil
            selectedMarkers = []
            return .handled
        }
    }

    // MARK: Markers and the range

    /// The show's editing state (range, lines), from the saved show, which
    /// SwiftUI observes.
    private var editor: ShowEditorState { show.editor }

    /// Blue, like Final Cut's range: the span shaded on the ruler, a
    /// triangle at each end. Faded while the range is switched off.
    /// Double-click a triangle for its line through the rows; ⌥-double-
    /// click for both ends' lines.
    @ViewBuilder private var rangeOnRuler: some View {
        let e = editor
        let lo = e.rangeIn ?? 0, hi = e.rangeOut ?? timeline.duration
        if e.rangeIn != nil || e.rangeOut != nil, hi > lo {
            let x0 = Self.inset + CGFloat(lo * pps), x1 = Self.inset + CGFloat(hi * pps)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.blue.opacity(e.rangeOn ? 0.28 : 0.1))
                    .frame(width: x1 - x0, height: Self.rulerHeight)
                    .offset(x: x0)
                    .allowsHitTesting(false)
                if e.rangeIn != nil { rangeEnd(x0, isIn: true, on: e.rangeOn) }
                if e.rangeOut != nil { rangeEnd(x1, isIn: false, on: e.rangeOn) }
            }
        }
    }

    private func rangeEnd(_ x: CGFloat, isIn: Bool, on: Bool) -> some View {
        let w: CGFloat = 7, h = Self.rulerHeight
        return Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 10))
            p.addLine(to: CGPoint(x: isIn ? w : -w, y: 10))
            p.closeSubpath()
        }
        .fill(Color.blue.opacity(on ? 1 : 0.4))
        .frame(width: w, height: 10)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .offset(x: isIn ? x - 2 : x - w - 2, y: h - 10)
        .onTapGesture {
            guard (NSApp.currentEvent?.clickCount ?? 1) >= 2 else { return }
            if NSEvent.modifierFlags.contains(.option) {
                engine.updateEditor { $0.rangeLines.toggle() }
            } else {
                // Its own line; with the range's lines off, this turns them
                // back on to show it.
                engine.updateEditor { e in
                    let showing = e.rangeLines && (isIn ? e.rangeInLine : e.rangeOutLine)
                    if !e.rangeLines { e.rangeLines = true }
                    if isIn { e.rangeInLine = !showing } else { e.rangeOutLine = !showing }
                }
            }
        }
        .help((isIn ? "Range start" : "Range end")
              + ". Double-click to show or hide its line; ⌥-double-click for both ends.")
    }

    /// Markers on the ruler: click to select (⌘ or ⇧ adds), drag to move
    /// (a selected one takes the rest of the selection with it), Delete to
    /// remove; double-click for its own line through the rows, ⌥-double-
    /// click for every marker's. Moving, removing and a marker's own line
    /// are undoable; the all-markers switch is editing state, and isn't.
    @ViewBuilder private var markersOnRuler: some View {
        ForEach(markerTimes, id: \.marker.id) { m, t, song in
            let selected = selectedMarkers.contains(m.id)
            MarkerShape()
                .fill(selected ? Color.yellow : song == nil ? Color.orange : Color.teal)
                .overlay(MarkerShape().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                .frame(width: 9, height: 11)
                .padding(.horizontal, 3)
                .contentShape(Rectangle())
                .offset(x: Self.inset + CGFloat(t * pps) - 7.5, y: Self.rulerHeight - 11)
                .onTapGesture { clickMarker(m) }
                .gesture(markerDragGesture(m.id))
                .help((song == nil ? "Marker" : "Beat marker (moves with its audio clip)")
                      + " at \(formatClock(t)). Drag to move; Delete removes it; double-click for its line.")
                // Just the obvious one for now (audit C3); Show/Hide Line
                // waits for the right-click conversation (spec/conventions.md §3).
                .contextMenu {
                    Button("Remove Marker") {
                        selectedMarkers = [m.id]
                        mutate("Remove Marker") { $0.removeMarkers([m.id]) }
                        selectedMarkers = []
                    }
                }
        }
        // What the Rhythm tool would place on this show, faint, until it's applied.
        if RhythmTool.shared.showID == show.id {
            ForEach(Array(RhythmTool.shared.preview.enumerated()), id: \.offset) { _, t in
                MarkerShape()
                    .fill(Color.orange.opacity(0.45))
                    .frame(width: 9, height: 11)
                    .offset(x: Self.inset + CGFloat(t * pps) - 4.5, y: Self.rulerHeight - 11)
                    .allowsHitTesting(false)
            }
        }
        // What the beat detection sheet would place, faint, until it's applied.
        ForEach(Array(beatPreview.enumerated()), id: \.offset) { _, t in
            MarkerShape()
                .fill(Color.teal.opacity(0.45))
                .frame(width: 9, height: 11)
                .offset(x: Self.inset + CGFloat(t * pps) - 4.5, y: Self.rulerHeight - 11)
                .allowsHitTesting(false)
        }
    }

    /// What Listen loops: the range, or the whole show (as the tool uses).
    private var listenRange: ClosedRange<Double> {
        engine.range ?? 0...max(timeline.duration, 0.1)
    }

    /// The Rhythm tool, on this show.
    private func openRhythm() {
        RhythmTool.shared.open(showID: show.id, model: model, undoManager: undoManager)
    }

    /// From a song's menu: the range if there is one, else that song.
    private func openBeatSheet(for clip: AudioClip?) {
        let r = engine.range ?? clip.map { $0.start...$0.end } ?? 0...max(timeline.duration, 0.1)
        beatSheet = BeatSheet.Request(range: r, song: clip?.id)
    }

    private func clickMarker(_ m: Marker) {
        focused = true
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            if NSEvent.modifierFlags.contains(.option) {
                engine.updateEditor { $0.markerLines.toggle() }
                return
            }
            let showing = editor.markerLines && m.showsLine
            // With every marker's line off, this turns them back on to show it.
            if !editor.markerLines { engine.updateEditor { $0.markerLines = true } }
            if m.showsLine == showing {
                mutate(showing ? "Hide Marker Line" : "Show Marker Line") { s in
                    s.updateMarker(m.id) { $0.showsLine = !showing }
                }
            }
            return
        }
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) || mods.contains(.shift) {
            if selectedMarkers.contains(m.id) { selectedMarkers.remove(m.id) } else { selectedMarkers.insert(m.id) }
        } else {
            selectedMarkers = [m.id]
        }
    }

    private func markerDragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("storyline"))
            .onChanged { g in
                if markerDrag == nil {
                    if !selectedMarkers.contains(id) { selectedMarkers = [id] }
                    markerDrag = MarkerDrag(ids: selectedMarkers, dt: 0)
                    focused = true
                }
                markerDrag?.dt = ((Double(g.translation.width) / pps) * 100).rounded() / 100
            }
            .onEnded { _ in
                guard let d = markerDrag else { return }
                markerDrag = nil
                guard d.dt != 0 else { return }
                mutate(d.ids.count == 1 ? "Move Marker" : "Move Markers") { s in
                    for id in d.ids {
                        s.updateMarker(id) { $0.time = max((($0.time + d.dt) * 100).rounded() / 100, 0) }
                    }
                }
            }
    }

    /// Lines down through every row, two kinds switched separately (and
    /// each marker or range end on its own): the markers in faint orange,
    /// the range's ends in blue, so an edge can be lined up by eye.
    private var linesThroughRows: some View {
        let e = editor
        return ZStack(alignment: .topLeading) {
            if e.markerLines {
                ForEach(markerTimes.filter { $0.marker.showsLine }, id: \.marker.id) { _, t, song in
                    Rectangle().fill((song == nil ? Color.orange : Color.teal).opacity(0.45)).frame(width: 1)
                        .offset(x: Self.inset + CGFloat(t * pps))
                }
            }
            if e.rangeOn, e.rangeLines {
                let ends = [e.rangeInLine ? e.rangeIn : nil, e.rangeOutLine ? e.rangeOut : nil].compactMap { $0 }
                ForEach(ends, id: \.self) { t in
                    Rectangle().fill(Color.blue.opacity(0.8)).frame(width: 1.5)
                        .offset(x: Self.inset + CGFloat(t * pps))
                }
            }
        }
        .padding(.top, Self.rulerHeight + 6)
        .allowsHitTesting(false)
    }

    // MARK: Rows

    /// Each row's handle, pinned at the left edge (it doesn't scroll
    /// sideways), and its drawer. Drag a handle to move the row; click it
    /// to slide the drawer out over the row; ⌥-click opens or closes them
    /// all. Esc closes them.
    private var rowHandles: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: rowsHeight)
            ForEach(displayRows) { row in
                RowHandle(row: row, height: Self.height(of: row.kind),
                          open: openDrawers.contains(row.id), dragging: rowDrag?.id == row.id,
                          width: Self.inset,
                          action: row.kind == .music ? ("Detect Beats…", { openBeatSheet(for: nil) })
                              : row.kind == .slides ? ("Rhythm…", { openRhythm() }) : nil,
                          toggle: { toggleDrawer(row.id) },
                          drag: rowDragGesture(row))
                    .offset(y: rowTop(row.kind))
            }
        }
        .coordinateSpace(name: "rowHandles")
        .offset(y: Self.rowsOrigin)
        .animation(.snappy(duration: 0.18), value: displayRows.map(\.id))
        .animation(.snappy(duration: 0.15), value: openDrawers)
    }

    private func toggleDrawer(_ id: UUID) {
        focused = true
        if NSEvent.modifierFlags.contains(.option) {
            openDrawers = openDrawers.count == show.rows.count ? [] : Set(show.rows.map(\.id))
        } else if openDrawers.contains(id) {
            openDrawers.remove(id)
        } else {
            openDrawers.insert(id)
        }
    }

    private func rowDragGesture(_ row: TimelineRow) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("rowHandles"))
            .onChanged { g in
                // Past the middle of another row, the dragged row takes its slot.
                let others = show.rows.filter { $0.id != row.id }
                var y: CGFloat = 0
                var target = others.count
                for (i, r) in others.enumerated() {
                    let h = Self.height(of: r.kind)
                    if g.location.y < y + h / 2 { target = i; break }
                    y += h + Self.rowGap
                }
                if rowDrag?.target != target || rowDrag?.id != row.id {
                    rowDrag = RowDrag(id: row.id, target: target)
                }
            }
            .onEnded { _ in
                let rows = displayRows
                rowDrag = nil
                guard rows.map(\.id) != show.rows.map(\.id) else { return }
                mutate("Move Row") { $0.rows = rows }
            }
    }

    // MARK: Blocks

    private func block(_ p: Placed) -> some View {
        let selected = selection.contains(p.id)
        return StoryBlock(slide: p.slide, item: p.slide.item, url: model.url(for: p.slide.item),
                          width: p.width, height: Self.blockHeight, pps: pps,
                          length: length(p.slide), selected: selected)
            .frame(width: p.width, height: Self.blockHeight)
            .contentShape(Rectangle())
            .onTapGesture { click(p.id) }
            .gesture(moveGesture(p))
            .modifier(HoverInfo(slide: p.slide, length: length(p.slide)))
            .contextMenu {
                let ids = selection.contains(p.id) ? selection : [p.id]
                Button("Duplicate") { SlideActions.duplicate(ids, mutate: mutate) }
                Button("Remove from Show") { SlideActions.remove(ids, selection: $selection, mutate: mutate) }
            }
            // A video slide's own sound (spec/video-audio.md). Silent until
            // it's turned up, so the line starts along the bottom.
            .overlay(alignment: .topLeading) {
                if p.slide.item.kind == .video, p.width > 24 {
                    CurveLine(curve: p.slide.slide.settings.audio ?? LevelCurve(),
                              length: length(p.slide), pps: pps,
                              width: p.width, height: Self.blockHeight,
                              colour: .orange, name: "Volume",
                              begin: { if !selection.contains(p.id) { click(p.id) } },
                              commit: { curve, action in
                                  mutate(action) { s in
                                      guard let i = s.slides.firstIndex(where: { $0.id == p.id }) else { return }
                                      s.slides[i].settings.audio = curve.isEmpty ? nil : curve
                                  }
                              })
                }
            }
    }

    /// Finder-style: plain click selects one and anchors here, ⌘ toggles
    /// and moves the anchor too, ⇧ selects the range from the anchor,
    /// replacing the previous ⇧-range rather than adding to it (batch 4,
    /// E1; `GridSelection`, unit-tested there — the old anchor, "the first
    /// selected slide", wasn't the same thing once a ⌘-click had moved it
    /// elsewhere). The preview jumps to the slide and pauses, as a
    /// thumbnail click does in the livery gallery.
    private func click(_ id: Int64) {
        let mods = NSEvent.modifierFlags
        let items = timeline.slides.map(\.slide.id)
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
        selectedTransition = nil
        selectedOverlay = nil
        focused = true
        engine.showSlide(id: id)
        // Checked on the event rather than with a double-tap gesture, which
        // would hold every single click back while it waits for a second.
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { openInspector() }
    }

    private func moveGesture(_ p: Placed) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("storyline"))
            .onChanged { g in
                if moving == nil {
                    // Dragging an unselected block moves just it.
                    if !selection.contains(p.id) { selection = [p.id] }
                    let ids = selection
                    let groupStart = layout().placed.first { ids.contains($0.id) }?.x ?? p.x
                    moving = Moving(ids: ids, grab: g.startLocation.x - groupStart,
                                    pointerX: g.location.x, target: 0)
                }
                moving?.pointerX = g.location.x
                moving?.target = targetIndex()
            }
            .onEnded { _ in
                if let m = moving {
                    let before = timeline.slides.map(\.slide.id)
                    var rest = before.filter { !m.ids.contains($0) }
                    rest.insert(contentsOf: before.filter { m.ids.contains($0) }, at: min(m.target, rest.count))
                    if rest != before { SlideActions.move(m.ids, toIndexAmongOthers: m.target, mutate: mutate) }
                }
                moving = nil
            }
    }

    /// Where the dragged group's left edge falls among the other blocks:
    /// past a block's midpoint, it goes after that block.
    private func targetIndex() -> Int {
        guard let m = moving else { return 0 }
        let left = m.pointerX - m.grab
        var x = Self.inset
        var i = 0
        for r in timeline.slides where !m.ids.contains(r.slide.id) {
            let w = CGFloat(length(r) * pps)
            if left < x + w / 2 { return i }
            x += w
            i += 1
        }
        return i
    }

    // MARK: Cuts

    /// Three grab zones at every cut (and a trim-end zone after the last
    /// slide): left of the cut trims the left clip's end, on the cut rolls
    /// it, right of the cut trims the right clip's start.
    private func cutHandles(_ placed: [Placed]) -> some View {
        ForEach(Array(placed.enumerated()), id: \.element.id) { i, p in
            let next = i + 1 < placed.count ? placed[i + 1] : nil
            let x = p.x + p.width
            // Zones shrink with tiny blocks so a cut stays reachable.
            let side = min(9, max(3, p.width / 3))
            let rightSide = next.map { min(9, max(3, $0.width / 3)) } ?? 0
            let roll: CGFloat = next == nil ? 0 : 6
            ZStack(alignment: .topLeading) {
                zone(.trimEnd(p.id), cutX: x, width: side, offset: x - roll / 2 - side, slide: p.slide)
                if let next {
                    zone(.roll(p.id, next.id), cutX: x, width: roll, offset: x - roll / 2, slide: p.slide)
                    zone(.trimStart(next.id), cutX: x, width: rightSide, offset: x + roll / 2, slide: next.slide)
                }
            }
        }
        .overlay(alignment: .topLeading) { edgeReadout }
    }

    private func zone(_ kind: EdgeKind, cutX: CGFloat, width: CGFloat, offset: CGFloat,
                      slide: ResolvedSlide) -> some View {
        // The layout already reflects an edit in progress (lengths change as
        // you drag), so zones sit where the blocks put them — no extra shift.
        let active = hoveredEdge == kind || edge?.kind == kind
        return ZStack {
            Rectangle().fill(Color.white.opacity(0.001))
            if active { EdgeBracket(kind: kind) }
        }
        .frame(width: max(width, 1), height: Self.blockHeight)
        .contentShape(Rectangle())
        .offset(x: offset, y: blocksTop)
        .onHover { inside in
            if inside {
                hoveredEdge = kind
                cursor(for: kind).set()
            } else {
                if hoveredEdge == kind { hoveredEdge = nil }
                // Set, not popped: the zones move under the pointer during
                // a trim, and a push without its pop leaves the cursor stuck.
                NSCursor.arrow.set()
            }
        }
        .gesture(edgeGesture(kind, cutX: cutX))
        .help(help(for: kind))
    }

    private func cursor(for kind: EdgeKind) -> NSCursor {
        switch kind {
        case .trimEnd: .resizeLeft
        case .trimStart: .resizeRight
        case .roll: .resizeLeftRight
        }
    }

    private func help(for kind: EdgeKind) -> String {
        switch kind {
        case .trimEnd: "Drag to change where this slide ends"
        case .trimStart: "Drag to change where this slide starts"
        case .roll: "Drag to move the cut: one slide grows as the other shrinks"
        }
    }

    private func edgeGesture(_ kind: EdgeKind, cutX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("storyline"))
            .onChanged { g in
                let raw = Double(g.translation.width) / pps
                // The cut's position when the drag began: the view (and so
                // `cutX`) moves as the edit reshapes the layout.
                let origin = edge?.kind == kind ? edge!.cutX : cutX
                let delta = snapped(kind, raw) ?? (raw * 10).rounded() / 10
                edge = EdgeEdit(kind: kind, delta: clampedDelta(kind, delta), cutX: origin)
            }
            .onEnded { _ in
                if let e = edge, e.delta != 0 { commit(e) }
                edge = nil
            }
    }

    private func resolved(_ id: Int64) -> ResolvedSlide? { timeline.slides.first { $0.slide.id == id } }

    /// The delta that puts the cut being dragged on a marker, if one is in
    /// reach. Trimming an end or rolling moves that cut; trimming a start
    /// leaves it and moves the next cut instead (what follows ripples), so
    /// that's the one that snaps.
    private func snapped(_ kind: EdgeKind, _ raw: Double) -> Double? {
        guard let snap else { return nil }
        switch kind {
        case .trimEnd(let a), .roll(let a, _):
            guard let r = resolved(a) else { return nil }
            let cut = r.start + r.length
            return Snap.nearest(cut + raw, in: snap.targets, within: snap.tolerance).map { $0 - cut }
        case .trimStart(let b):
            guard let r = resolved(b) else { return nil }
            let cut = r.start + r.length
            return Snap.nearest(cut - raw, in: snap.targets, within: snap.tolerance).map { cut - $0 }
        }
    }

    /// Keeps every slide at least half a second long, and a video's start
    /// within its clip.
    private func clampedDelta(_ kind: EdgeKind, _ d: Double) -> Double {
        let minLength = 0.5
        func startRoom(_ r: ResolvedSlide) -> ClosedRange<Double> {
            // How far a start can move: not past the slide's own end, and a
            // video's start not before its first frame.
            let lower = r.item.kind == .image ? -.infinity : -r.clipStart
            return lower...(r.length - minLength)
        }
        switch kind {
        case .trimEnd(let a):
            guard let ra = resolved(a) else { return 0 }
            return max(d, minLength - ra.length)
        case .trimStart(let b):
            guard let rb = resolved(b) else { return 0 }
            let r = startRoom(rb)
            return min(max(d, r.lowerBound), r.upperBound)
        case .roll(let a, let b):
            guard let ra = resolved(a), let rb = resolved(b) else { return 0 }
            let r = startRoom(rb)
            return min(max(d, max(minLength - ra.length, r.lowerBound)), r.upperBound)
        }
    }

    private func commit(_ e: EdgeEdit) {
        func setLength(_ s: inout Show, _ id: Int64, _ length: Double) {
            if let i = s.slides.firstIndex(where: { $0.id == id }) {
                s.slides[i].settings.length = .seconds((length * 100).rounded() / 100)
            }
        }
        /// Moving a start later skips into a video; for a still it just shortens.
        func shiftStart(_ s: inout Show, _ r: ResolvedSlide, by d: Double) {
            guard r.item.kind != .image, let i = s.slides.firstIndex(where: { $0.id == r.slide.id }) else { return }
            let v = max(r.clipStart + d, 0)
            s.slides[i].settings.clipStart = v < 0.001 ? nil : v
        }
        switch e.kind {
        case .trimEnd(let a):
            guard let ra = resolved(a) else { return }
            mutate("Trim End") { setLength(&$0, a, ra.length + e.delta) }
        case .trimStart(let b):
            guard let rb = resolved(b) else { return }
            mutate("Trim Start") { s in
                setLength(&s, b, rb.length - e.delta)
                shiftStart(&s, rb, by: e.delta)
            }
        case .roll(let a, let b):
            guard let ra = resolved(a), let rb = resolved(b) else { return }
            mutate("Roll Edit") { s in
                setLength(&s, a, ra.length + e.delta)
                setLength(&s, b, rb.length - e.delta)
                shiftStart(&s, rb, by: e.delta)
            }
        }
    }

    /// While dragging a cut: how far it has moved and the lengths it makes.
    @ViewBuilder private var edgeReadout: some View {
        if let e = edge {
            let text: String = switch e.kind {
            case .trimEnd(let a): "\(signed(e.delta)) · \(formatSeconds(resolved(a).map { $0.length + e.delta } ?? 0))"
            case .trimStart(let b): "\(signed(-e.delta)) · \(formatSeconds(resolved(b).map { $0.length - e.delta } ?? 0))"
            case .roll(let a, let b):
                "\(formatSeconds(resolved(a).map { $0.length + e.delta } ?? 0)) | \(formatSeconds(resolved(b).map { $0.length - e.delta } ?? 0))"
            }
            Text(text)
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.yellow, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.black)
                .fixedSize()
                // A trimmed start keeps its place (what follows ripples in);
                // trimming an end or rolling moves the cut itself.
                .offset(x: e.cutX + (isTrimStart(e.kind) ? 0 : CGFloat(e.delta * pps)) - 30,
                        y: blocksTop + 38)
                .allowsHitTesting(false)
        }
    }

    private func isTrimStart(_ k: EdgeKind) -> Bool {
        if case .trimStart = k { return true }
        return false
    }

    private func signed(_ d: Double) -> String {
        (d >= 0 ? "+" : "−") + formatSeconds(abs(d))
    }

    // MARK: Dropping files

    /// The join a drop at `x` lands on: before the block under the pointer
    /// if it's in the block's first half, after it if in the second.
    private func dropTarget(_ x: CGFloat, _ placed: [Placed]) -> (index: Int, x: CGFloat) {
        for p in placed where x < p.x + p.width / 2 {
            return (show.slides.firstIndex { $0.id == p.id } ?? show.slides.count, p.x)
        }
        return (show.slides.count, placed.last.map { $0.x + $0.width } ?? Self.inset)
    }

    /// Files from the Collection Browser, or from Finder or Photos (imported
    /// first), inserted as slides at the join, after checking they're in
    /// the show's collection.
    private func drop(_ providers: [NSItemProvider], at x: CGFloat, _ placed: [Placed]) {
        let index = dropTarget(x, placed).index
        let showID = show.id
        Task {
            // Songs go in the music row, at the time they were dropped.
            let all = await model.itemIDs(from: providers)
            let songs = model.songs(all), ids = model.pictures(all)
            if !songs.isEmpty, model.bringIntoCollection(songs, forShow: showID) {
                MusicRow.place(songs, at: max(0, Double(x - Self.inset) / pps), model: model, mutate: mutate)
            }
            guard !ids.isEmpty, model.bringIntoCollection(ids, forShow: showID) else { return }
            mutate(ids.count == 1 ? "Insert Slide" : "Insert Slides") { s in
                s.slides.insert(contentsOf: ids.map { Slide(id: 0, itemID: $0) }, at: min(index, s.slides.count))
            }
        }
    }

    // MARK: Transitions row

    /// Each join, with the slide that comes in there. When a show loops,
    /// the wrap from the last slide into the first is a join too, at the end.
    private func joins(_ placed: [Placed]) -> [(incoming: Placed, x: CGFloat, time: Double)] {
        var out = placed.indices.dropFirst().map { (incoming: placed[$0], x: placed[$0].x, time: placed[$0].slide.start) }
        // (Only when the slides run to the show's end: past them, the wrap
        // is a cut from the background.)
        if timeline.wrapsDirectly, placed.count > 1, let last = placed.last {
            out.append((incoming: placed[0], x: last.x + last.width, time: timeline.duration))
        }
        return out
    }

    /// The lane's transitions row: each transition a section across its
    /// join, the section being the overlap itself. Its edges move
    /// independently, its middle slides it; a cut shows nothing but a "+"
    /// on hover. Sections the show's default gave are drawn lighter than
    /// ones set by hand.
    private func transitionsRow(_ placed: [Placed]) -> some View {
        ForEach(joins(placed), id: \.incoming.id) { j in
            let r = j.incoming.slide
            let editing = transitionEdit?.id == r.slide.id ? transitionEdit : nil
            let lead = editing?.lead ?? r.transitionIn.lead
            let d = editing?.duration ?? r.transitionIn.duration
            if d > 0 {
                transitionSection(r, joinX: j.x, joinTime: j.time, lead: lead, duration: d)
            } else {
                addTransitionButton(r, joinX: j.x)
            }
        }
    }

    private func transitionSection(_ r: ResolvedSlide, joinX: CGFloat, joinTime: Double,
                                   lead: Double, duration: Double) -> some View {
        let id = r.slide.id
        let left = joinX - CGFloat(lead * pps)
        let width = max(CGFloat(duration * pps), 8)
        let own = r.slide.settings.transition != nil
        let selected = selectedTransition == id
        let h = Self.laneRowHeight - 4
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.accentColor : Color.white.opacity(own ? 0.9 : 0.55))
            // Where the join is, inside the overlap.
            Rectangle().fill(Color.black.opacity(0.55))
                .frame(width: 1, height: h)
                .offset(x: CGFloat(lead * pps))
            if width > 70 {
                Text(r.transitionIn.style.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? .white : .black.opacity(0.75))
                    .lineLimit(1)
                    .frame(width: width, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: h)
        .contentShape(Rectangle())
        .onTapGesture { selectTransition(id, at: joinTime) }
        .gesture(transitionDrag(r, part: .body))
        .overlay(alignment: .leading) { transitionEdgeZone(r, part: .start) }
        .overlay(alignment: .trailing) { transitionEdgeZone(r, part: .end) }
        .onHover { if $0 { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        .help("\(r.transitionIn.style.title) · \(formatSeconds(duration))"
              + (own ? "" : " (show default)") + ". Drag an edge to change when it starts or ends; drag the middle to slide it.")
        .offset(x: left, y: laneTop + 2)
        // Just the obvious one for now (audit C2); the fuller menu (its
        // style as a submenu, Use Show Default) waits for the right-click
        // conversation (spec/conventions.md §3).
        .contextMenu {
            Button("Remove Transition") {
                selectTransition(id, at: joinTime)
                mutate("Remove Transition") { s in
                    guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return }
                    s.slides[i].settings.transition = ShowToolsCore.Transition(style: .cut, duration: 0)
                }
                selectedTransition = nil
            }
        }
    }

    private func transitionEdgeZone(_ r: ResolvedSlide, part: TransitionEdit.Part) -> some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(transitionDrag(r, part: part))
    }

    /// Edges move independently, but the section always touches or covers
    /// its join, and an overlap can't outlast either slide it joins.
    private func transitionDrag(_ r: ResolvedSlide, part: TransitionEdit.Part) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("storyline"))
            .onChanged { g in
                let id = r.slide.id
                if transitionEdit?.id != id {
                    let i = r.index
                    let prev = i > 0 ? timeline.slides[i - 1] : timeline.slides.last
                    transitionEdit = TransitionEdit(id: id, part: part, lead0: r.transitionIn.lead,
                                                    duration0: r.transitionIn.duration,
                                                    lead: r.transitionIn.lead, duration: r.transitionIn.duration,
                                                    limit: min(r.length, prev?.length ?? r.length))
                }
                guard var e = transitionEdit else { return }
                let dt = Double(g.translation.width) / pps
                let tail0 = e.duration0 - e.lead0
                let shortest = 0.1
                switch e.part {
                case .start:
                    e.lead = min(max(e.lead0 - dt, max(0, shortest - tail0)), max(e.limit - tail0, 0))
                    e.duration = e.lead + tail0
                case .end:
                    let tail = min(max(tail0 + dt, max(0, shortest - e.lead0)), max(e.limit - e.lead0, 0))
                    e.duration = e.lead0 + tail
                case .body:
                    var lead = min(max(e.lead0 - dt, 0), e.duration0)
                    // Snaps to centred on the join, within a few points.
                    if abs(lead - e.duration0 / 2) * pps < 4 { lead = e.duration0 / 2 }
                    e.lead = lead
                }
                transitionEdit = e
            }
            .onEnded { _ in
                guard let e = transitionEdit else { return }
                transitionEdit = nil
                guard e.lead != e.lead0 || e.duration != e.duration0 else { return }
                let base = r.transitionIn
                mutate(e.part == .body ? "Move Transition" : "Change Transition Length") { s in
                    guard let i = s.slides.firstIndex(where: { $0.id == e.id }) else { return }
                    s.slides[i].settings.transition = ShowToolsCore.Transition(style: base.style, duration: e.duration,
                                                                 direction: base.direction, lead: e.lead)
                }
                selectedTransition = e.id
                focused = true
            }
    }

    /// At a cut: a "+" on hover that adds the show's default transition (or,
    /// if the default is itself a cut, a new show's default).
    private func addTransitionButton(_ r: ResolvedSlide, joinX: CGFloat) -> some View {
        let id = r.slide.id
        return ZStack {
            Color.clear
            if hoveredJoin == id {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Color.accentColor)
            }
        }
        .frame(width: 22, height: Self.laneRowHeight - 2)
        .contentShape(Rectangle())
        .onHover { hoveredJoin = $0 ? id : (hoveredJoin == id ? nil : hoveredJoin) }
        .onTapGesture {
            mutate("Add Transition") { s in
                guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return }
                s.slides[i].settings.transition = s.defaults.transition.style == .cut ? .newShowDefault : nil
            }
            selectedTransition = id
            focused = true
        }
        .help("Cut. Click + to add a transition here.")
        .offset(x: joinX - 11, y: laneTop + 1)
    }

    /// Selecting a transition shows it: the preview goes to its join.
    private func selectTransition(_ id: Int64, at time: Double) {
        selectedTransition = id
        selectedOverlay = nil
        selectedSong = nil
        selection = []
        focused = true
        engine.pause()
        engine.seek(time)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                if engine.isPlaying { engine.pause() }
                let t = max(0, Double(g.location.x - Self.inset) / pps)
                engine.seek(min(t, max(timeline.duration - 0.001, 0)))
            }
    }
}

// MARK: - One block

struct StoryBlock: View {
    let slide: ResolvedSlide
    let item: MediaItem
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let pps: Double
    let length: Double
    let selected: Bool

    private var tint: Color {
        switch item.kind {
        case .image: Color(red: 0.30, green: 0.34, blue: 0.62)
        case .animatedImage: Color(red: 0.20, green: 0.52, blue: 0.52)
        case .video: Color(red: 0.22, green: 0.42, blue: 0.70)
        case .audio: Color(red: 0.16, green: 0.30, blue: 0.46)
        }
    }

    var body: some View {
        let thumbH = height - 8
        let aspect = CGFloat(item.pixelWidth) / CGFloat(max(item.pixelHeight, 1))
        let thumbW = thumbH * aspect
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.55))
            if item.kind == .video, let url {
                VideoStrip(item: item, url: url, height: thumbH, tileWidth: thumbW, width: width - 8,
                           pps: pps, length: length, clipStart: slide.clipStart)
                    .padding(.leading, 4)
            } else {
                HStack(spacing: 6) {
                    // True proportions: portrait is tall and narrow, landscape wide.
                    ThumbnailView(item: item, url: url)
                        .frame(width: thumbW, height: thumbH)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(width: min(thumbW, max(width - 8, 0)), alignment: .leading)
                        .clipped()
                    if width - thumbW > 50 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName).lineLimit(1).truncationMode(.middle)
                            Text(formatSeconds(length)).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .frame(width: max(width, 1), height: height, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : .black.opacity(0.45), lineWidth: selected ? 3 : 1))
        .overlay(alignment: .topTrailing) {
            let m = slide.peakMagnification(outputSize: outputPixelSize)
            if m > ResolvedSlide.softAbove, width > 24 {
                SoftBadge(magnification: m)
                    .font(.caption)
                    .padding(4)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
    }
}

/// Frames across a video block, each at the moment it sits over.
struct VideoStrip: View {
    let item: MediaItem
    let url: URL
    let height: CGFloat
    let tileWidth: CGFloat
    let width: CGFloat
    let pps: Double
    let length: Double
    let clipStart: Double
    @State private var frames: [NSImage]?

    var body: some View {
        HStack(spacing: 0) {
            if let frames, !frames.isEmpty, tileWidth > 0 {
                let count = max(1, Int((width / tileWidth).rounded(.up)))
                let duration = max(item.duration ?? length, 0.01)
                ForEach(0..<count, id: \.self) { i in
                    let t = clipStart + Double(CGFloat(i) * tileWidth) / pps
                    // Past the clip's end the video holds its last frame.
                    let f = min(Int(min(t, duration) / duration * Double(frames.count)), frames.count - 1)
                    Image(nsImage: frames[f]).resizable()
                        .frame(width: tileWidth, height: height)
                }
            }
        }
        .frame(width: max(width, 0), height: height, alignment: .leading)
        .clipped()
        .onAppear {
            frames = Thumbnails.shared.strip(item, url: url) {
                frames = Thumbnails.shared.strip(item, url: url) {}
            }
        }
    }
}

/// Slide info after the pointer rests on a block for a second.
struct HoverInfo: ViewModifier {
    let slide: ResolvedSlide
    let length: Double
    @State private var shown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    pending = Task {
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .popover(isPresented: $shown, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(slide.index + 1). \(slide.item.fileName)").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        GridRow { Text("Starts").foregroundStyle(.secondary); Text(formatDuration(slide.start)) }
                        GridRow { Text("Length").foregroundStyle(.secondary); Text(formatSeconds(length)) }
                        GridRow {
                            Text("Transition in").foregroundStyle(.secondary)
                            Text(slide.transitionIn.style == .cut ? "Cut"
                                 : "\(slide.transitionIn.style.title), \(formatSeconds(slide.transitionIn.duration))")
                        }
                        GridRow {
                            Text("Pan and Zoom").foregroundStyle(.secondary)
                            Text(slide.panAndZoom == nil ? "Off"
                                 : String(format: "zoom %.2f → %.2f", slide.panAndZoom!.start.zoom, slide.panAndZoom!.end.zoom))
                        }
                        GridRow { Text("Fit").foregroundStyle(.secondary); Text(slide.fit.title) }
                        GridRow {
                            let m = slide.peakMagnification(outputSize: outputPixelSize)
                            Text("Sharpness").foregroundStyle(.secondary)
                            Text(m > ResolvedSlide.softAbove
                                 ? String(format: "soft: up to %.1f× the file's pixels", m)
                                 : String(format: "sharp (up to %.2f× the file's pixels)", m))
                        }
                        GridRow {
                            Text("Image").foregroundStyle(.secondary)
                            Text("\(slide.item.pixelWidth) × \(slide.item.pixelHeight) · \(orientation)")
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
            }
    }

    private var orientation: String {
        let w = slide.item.pixelWidth, h = slide.item.pixelHeight
        return w > h ? "landscape" : w < h ? "portrait" : "square"
    }
}

// MARK: - Ruler and playhead

struct RulerView: View {
    let duration: Double
    let pps: Double
    let inset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            // A labelled tick at least ~80pt apart, on a round number of seconds.
            let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]
            let major = steps.first { $0 * pps >= 80 } ?? 1200
            let minor = major / 5
            var t = 0.0
            while t <= duration + major {
                let x = inset + CGFloat(t * pps)
                let isMajor = abs((t / major).rounded() * major - t) < 1e-6
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x, y: size.height - (isMajor ? 10 : 4)))
                ctx.stroke(p, with: .color(.secondary), lineWidth: 1)
                if isMajor {
                    ctx.draw(Text(formatDuration(t)).font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                }
                t += minor
            }
        }
    }
}

struct Playhead: View {
    let engine: PlaybackEngine
    let timeline: ShowTimeline
    let pps: Double
    let inset: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !engine.isPlaying)) { _ in
            let _ = engine.seekCount
            let x = inset + CGFloat(timeline.wrap(engine.now) * pps)
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Rectangle().fill(.red).frame(width: 2)
            }
            .frame(width: 12)
            .offset(x: x - 6)
            .allowsHitTesting(false)
        }
    }
}

/// Final Cut's yellow edit brackets: "]" on a clip's end, "[" on a start,
/// both for a roll.
struct EdgeBracket: View {
    let kind: StorylineView.EdgeKind

    var body: some View {
        HStack(spacing: 0) {
            switch kind {
            case .trimEnd: bracket(opening: false)
            case .trimStart: bracket(opening: true)
            case .roll: bracket(opening: false); bracket(opening: true)
            }
        }
        .allowsHitTesting(false)
    }

    private func bracket(opening: Bool) -> some View {
        Canvas { ctx, size in
            var p = Path()
            let x: CGFloat = opening ? 1.5 : size.width - 1.5
            let tip: CGFloat = opening ? size.width : 0
            p.move(to: CGPoint(x: tip, y: 1.5))
            p.addLine(to: CGPoint(x: x, y: 1.5))
            p.addLine(to: CGPoint(x: x, y: size.height - 1.5))
            p.addLine(to: CGPoint(x: tip, y: size.height - 1.5))
            ctx.stroke(p, with: .color(.yellow), lineWidth: 3)
        }
        .frame(width: 5)
    }
}

/// Tracks files dragged over the storyline, for its insertion line, and
/// hands over the drop.
struct StorylineDrop: DropDelegate {
    let update: (CGPoint?) -> Void
    let perform: ([NSItemProvider], CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: ItemDrag.accepted) }
    func dropEntered(info: DropInfo) { update(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { update(nil) }
    func performDrop(info: DropInfo) -> Bool {
        let location = info.location
        update(nil)
        perform(info.itemProviders(for: ItemDrag.accepted), location)
        return true
    }
}

/// The storyline's horizontal scroll, reported for the frame strip.
struct StorylineScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Row handle and drawer

/// A row's handle: a thin strip with a grip, always showing at the
/// storyline's left edge. Its drawer slides out over the row's content,
/// leaving the timeline where it is (plan, Phase 3).
struct RowHandle<G: Gesture>: View {
    let row: TimelineRow
    let height: CGFloat
    let open: Bool
    let dragging: Bool
    let width: CGFloat
    /// The row's one control so far, in its drawer (the music row's "Detect
    /// Beats…").
    let action: (title: String, run: () -> Void)?
    let toggle: () -> Void
    let drag: G

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(dragging || open ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.14))
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(dragging || open ? 0.9 : 0.5)).frame(width: 5, height: 1)
                    }
                }
            }
            .frame(width: width - 2, height: height)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .gesture(drag)
            .onHover { if $0 { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
            .help("\(row.kind.title) row. Drag to move it; click to open its drawer; ⌥-click opens or closes them all.")
            if open {
                drawer
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(.leading, 1)
    }

    /// The row's name and icon, and (as they're built) its controls.
    private var drawer: some View {
        HStack(spacing: 6) {
            Image(systemName: row.kind.symbol)
            Text(row.kind.title)
                .lineLimit(1)
            if let action {
                Button(action.title, action: action.run)
                    .controlSize(.small)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .frame(width: action == nil ? 130 : 210, height: height, alignment: .leading)
        .background(.regularMaterial, in: UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5))
        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.85)).frame(width: 1) }
        .shadow(radius: 3, x: 2)
    }
}

extension TimelineRow.Kind {
    var title: String {
        switch self {
        case .images: "Images"
        case .transitions: "Transitions"
        case .slides: "Slides"
        case .music: "Audio"
        }
    }

    var symbol: String {
        switch self {
        case .images: "photo.on.rectangle"
        case .transitions: "arrow.triangle.swap"
        case .slides: "rectangle.stack"
        case .music: "waveform"
        }
    }
}

/// A marker's shape: a little tag pointing down at its time.
struct MarkerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - r.width / 2))
        p.closeSubpath()
        return p
    }
}
