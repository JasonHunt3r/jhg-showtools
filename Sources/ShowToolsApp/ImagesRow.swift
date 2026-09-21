import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore

/// The lane's images row, over the transitions row (plan, Phase 2c).
///
/// Collapsed to a thin strip while empty; it opens when an image is dragged
/// over it. Drop files from Finder or Photos to place them where they land,
/// or right-click at a point and choose "Place Image Here…". Drag an image
/// to move it and its edges to trim it; one row, so images never overlap.
/// Every drag saves once, on release.
struct ImagesRow: View {
    let show: Show
    let timeline: ShowTimeline
    let engine: PlaybackEngine
    /// Points per second, and the storyline's left inset.
    let pps: Double
    let inset: CGFloat
    let width: CGFloat
    let height: CGFloat
    @Binding var dropTargeted: Bool
    @Binding var selectedOverlay: UUID?
    let mutate: ShowMutator
    /// Called when an image is selected, so the rest of the selection clears.
    let didSelect: () -> Void
    @Environment(AppModel.self) private var model

    /// A new image's length.
    static let newLength = 5.0
    static let shortest = 0.2

    private struct ClipEdit {
        enum Part { case move, start, end }
        let id: UUID
        let part: Part
        let start0: Double, length0: Double
        var start: Double, length: Double
        /// The free stretch it can use: between its neighbours.
        let room: ClosedRange<Double>
    }
    @State private var edit: ClipEdit?
    @State private var hoverX: CGFloat = 0
    /// While the library picker is open: the time to place at.
    @State private var placing: PlaceRequest?

    struct PlaceRequest: Identifiable {
        let time: Double
        var id: Double { time }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(dropTargeted ? 0.14 : 0.05))
                .frame(width: max(CGFloat(timeline.duration * pps), 0), height: height)
                .offset(x: inset)
            ForEach(timeline.overlays, id: \.clip.id) { o in
                if height > 12 { clipView(o) }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover { if case .active(let p) = $0 { hoverX = p.x } }
        .contextMenu {
            let t = time(at: hoverX)
            Button("Place Image Here…") { placing = PlaceRequest(time: t) }
                .disabled(OverlayPlacement.freeSpan(at: t, in: show.overlays, duration: timeline.duration) == nil)
        }
        .onDrop(of: ItemDrag.accepted, isTargeted: $dropTargeted) { providers, location in
            let t = time(at: location.x)
            Task {
                let ids = await model.itemIDs(from: providers)
                guard !ids.isEmpty, model.bringIntoCollection(ids, forShow: show.id) else { return }
                place(ids, at: t)
            }
            return true
        }
        .sheet(item: $placing) { request in
            LibraryPicker { item in
                placing = nil
                // Like a drop: a file from outside the show's collection
                // joins it, after asking.
                if let item, model.bringIntoCollection([item.id], forShow: show.id) {
                    place([item.id], at: request.time)
                }
            }
        }
        .help(timeline.overlays.isEmpty
              ? "Images row: drop an image here, or right-click and choose Place Image Here…"
              : "")
    }

    private func time(at x: CGFloat) -> Double {
        min(max(Double(x - inset) / pps, 0), timeline.duration)
    }

    /// Several files dropped at once go end to end from where they landed,
    /// as far as there's room.
    private func place(_ itemIDs: [Int64], at t: Double) {
        guard !itemIDs.isEmpty else { return }
        var placed: OverlayClip?
        mutate(itemIDs.count == 1 ? "Place Image" : "Place Images") { s in
            var at = t
            for id in itemIDs {
                // No video in the lane yet: skip it, and place the rest.
                guard model.itemsByID[id]?.kind != .video else { continue }
                guard var clip = OverlayPlacement.place(itemID: id, at: at, length: Self.newLength,
                                                        in: s.overlays, duration: timeline.duration,
                                                        shortest: Self.shortest)
                else { break }                                      // no room left
                // Half size, centred: visibly over the picture, and easy to grab.
                clip.transform.scale = 0.5
                s.overlays.append(clip)
                placed = placed ?? clip
                at = clip.start + clip.length
            }
        }
        // The new clip isn't in `show` yet (that's the show before this edit).
        if let placed { select(placed.id, clip: placed) }
    }

    // MARK: One image

    private func clipView(_ o: ResolvedOverlay) -> some View {
        let id = o.clip.id
        let e = edit?.id == id ? edit : nil
        let start = e?.start ?? o.start
        let length = e?.length ?? o.clip.length
        let w = max(CGFloat(length * pps), 6)
        let selected = selectedOverlay == id
        let h = height - 4
        let aspect = CGFloat(o.item.pixelWidth) / CGFloat(max(o.item.pixelHeight, 1))
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.55, green: 0.38, blue: 0.62).opacity(0.85))
            // The fades, as ramps at the ends.
            fadeRamps(o.clip, width: w, height: h)
            HStack(spacing: 5) {
                ThumbnailView(item: o.item, url: model.url(for: o.item))
                    .frame(width: (h - 4) * aspect, height: h - 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                if w - (h - 4) * aspect > 60 {
                    Text(o.item.fileName).font(.caption2).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.leading, 3)
            .frame(width: w, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(selected ? Color.accentColor : .black.opacity(0.4), lineWidth: selected ? 2.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { select(id) }
        .gesture(drag(o, part: .move))
        .overlay(alignment: .leading) { edgeZone(o, part: .start) }
        .overlay(alignment: .trailing) { edgeZone(o, part: .end) }
        .onHover { if $0 { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
        .help("\(o.item.fileName) · \(formatSeconds(length))")
        .offset(x: inset + CGFloat(start * pps), y: 2)
    }

    private func fadeRamps(_ c: OverlayClip, width: CGFloat, height: CGFloat) -> some View {
        Canvas { ctx, _ in
            let inW = min(CGFloat(c.fadeIn * pps), width / 2), outW = min(CGFloat(c.fadeOut * pps), width / 2)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: inW, y: 0)); p.addLine(to: CGPoint(x: 0, y: height))
            p.move(to: CGPoint(x: width, y: 0)); p.addLine(to: CGPoint(x: width - outW, y: 0))
            p.addLine(to: CGPoint(x: width, y: height))
            ctx.fill(p, with: .color(.black.opacity(0.3)))
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func edgeZone(_ o: ResolvedOverlay, part: ClipEdit.Part) -> some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(drag(o, part: part))
    }

    private func drag(_ o: ResolvedOverlay, part: ClipEdit.Part) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                let id = o.clip.id
                if edit?.id != id {
                    let room = OverlayPlacement.freeSpan(at: o.start, in: show.overlays,
                                                         duration: timeline.duration, ignoring: id)
                        ?? o.start...o.end
                    edit = ClipEdit(id: id, part: part, start0: o.start, length0: o.clip.length,
                                    start: o.start, length: o.clip.length, room: room)
                    select(id)
                }
                guard var e = edit else { return }
                let dt = Double(g.translation.width) / pps
                switch e.part {
                case .move:
                    e.start = min(max(e.start0 + dt, e.room.lowerBound), e.room.upperBound - e.length0)
                case .start:
                    let end = e.start0 + e.length0
                    e.start = min(max(e.start0 + dt, e.room.lowerBound), end - Self.shortest)
                    e.length = end - e.start
                case .end:
                    e.length = min(max(e.length0 + dt, Self.shortest), e.room.upperBound - e.start0)
                }
                edit = e
            }
            .onEnded { _ in
                guard let e = edit else { return }
                edit = nil
                guard e.start != e.start0 || e.length != e.length0 else { return }
                mutate(e.part == .move ? "Move Image" : "Trim Image") { s in
                    guard let i = s.overlays.firstIndex(where: { $0.id == e.id }) else { return }
                    s.overlays[i].start = e.start
                    s.overlays[i].length = e.length
                }
            }
    }

    /// Selecting an image also brings the playhead onto it, where it's
    /// fully faded in, so its handles show on the picture.
    private func select(_ id: UUID, clip: OverlayClip? = nil) {
        selectedOverlay = id
        didSelect()
        guard let c = clip ?? show.overlays.first(where: { $0.id == id }) else { return }
        engine.pause()
        let now = timeline.wrap(engine.now)
        if now < c.start || now >= c.start + c.length {
            engine.seek(c.start + min(c.fadeIn, c.length / 2))
        }
    }
}

/// Pick an image from the library, for "Place Image Here…". Video isn't
/// offered: the lane doesn't play it yet.
struct LibraryPicker: View {
    let choose: (MediaItem?) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Text("Place Image").font(.headline).padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 12) {
                    ForEach(model.items.filter { $0.kind != .video }) { item in
                        Button { choose(item) } label: {
                            VStack(spacing: 4) {
                                ThumbnailView(item: item, url: model.url(for: item))
                                    .frame(width: 110, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(item.fileName).font(.caption).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.fileName)
                    }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { choose(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 460)
    }
}
