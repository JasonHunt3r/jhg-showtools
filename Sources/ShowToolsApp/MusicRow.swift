import SwiftUI
import ShowToolsCore

/// The storyline's music row (plan, Phase 3): songs as clips on the show's
/// clock, each drawn with its waveform. Drop songs from Finder, the library
/// or the collection list to place them where they land; several dropped at
/// once go end to end. Drag a song to move it and its edges to trim it
/// (the front edge cuts into the start of the song, as in Final Cut). Songs
/// may overlap: the overlap draws green, and where one starts inside
/// another they crossfade. Each song's level line sets its volume and
/// fades. Every drag saves once, on release.
struct MusicRow: View {
    let show: Show
    let timeline: ShowTimeline
    let pps: Double
    let inset: CGFloat
    let width: CGFloat
    let height: CGFloat
    @Binding var selectedSong: UUID?
    let mutate: ShowMutator
    /// Called when a song is selected, so the rest of the selection clears.
    let didSelect: () -> Void
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    static let shortest = 0.5

    private struct SongEdit {
        enum Part { case move, start, end }
        let id: UUID
        let part: Part
        let original: AudioClip
        var clip: AudioClip
        /// The whole song's length: a trim can't reach past either end of it.
        let songLength: Double
    }
    @State private var edit: SongEdit?

    /// The songs as drawn: a drag in progress already applied.
    private var clips: [AudioClip] {
        show.music.map { c in edit?.id == c.id ? edit!.clip : c }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(dropTargeted ? 0.14 : 0.05))
                .frame(width: max(CGFloat(timeline.duration * pps), 0), height: height)
                .offset(x: inset)
            if show.music.isEmpty {
                Label("Drop songs here", systemImage: "music.note")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: height)
                    .offset(x: inset + 8)
                    .allowsHitTesting(false)
            }
            let drawn = clips
            // Later songs sit on top of earlier ones.
            ForEach(drawn.sorted { $0.start < $1.start }) { clip in
                if let item = model.itemsByID[clip.itemID] { clipView(clip, item: item) }
            }
            // Where songs overlap, green, over both.
            ForEach(Array(AudioClip.overlaps(drawn).enumerated()), id: \.offset) { _, o in
                RoundedRectangle(cornerRadius: 3)
                    .fill(SongClip.overlap)
                    .frame(width: max(CGFloat((o.upperBound - o.lowerBound) * pps), 1), height: height - 18)
                    .offset(x: inset + CGFloat(o.lowerBound * pps), y: 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onDrop(of: ItemDrag.accepted, isTargeted: $dropTargeted) { providers, location in
            let t = max(0, Double(location.x - inset) / pps)
            Task {
                let ids = model.songs(await model.itemIDs(from: providers))
                guard !ids.isEmpty, model.bringIntoCollection(ids, forShow: show.id) else { return }
                MusicRow.place(ids, at: t, model: model, mutate: mutate)
            }
            return true
        }
    }

    private func clipView(_ clip: AudioClip, item: MediaItem) -> some View {
        let w = max(CGFloat(clip.length * pps), 4)
        return SongClip(clip: clip, item: item, url: model.url(for: item),
                        selected: selectedSong == clip.id, height: height)
            .frame(width: w, height: height)
            .contentShape(Rectangle())
            .onTapGesture { select(clip.id) }
            .gesture(drag(clip, item: item, part: .move))
            .overlay(alignment: .leading) { edgeZone(clip, item: item, part: .start) }
            .overlay(alignment: .trailing) { edgeZone(clip, item: item, part: .end) }
            .overlay(alignment: .topLeading) {
                LevelLine(level: clip.volume, fadeIn: clip.fadeIn, fadeOut: clip.fadeOut, length: clip.length,
                          pps: pps, width: w, height: height, colour: .orange, name: "Volume",
                          begin: { select(clip.id) },
                          commit: { level, fadeIn, fadeOut in
                              mutate(level != clip.volume ? "Change Volume" : "Change Fade") { s in
                                  guard let i = s.music.firstIndex(where: { $0.id == clip.id }) else { return }
                                  s.music[i].volume = level
                                  s.music[i].fadeIn = fadeIn
                                  s.music[i].fadeOut = fadeOut
                              }
                          })
            }
            .onHover { if $0 { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
            .contextMenu {
                Button("Remove Song") {
                    mutate("Remove Song") { $0.music.removeAll { $0.id == clip.id } }
                    if selectedSong == clip.id { selectedSong = nil }
                }
            }
            .help("\(item.fileName) · \(formatSeconds(clip.length))")
            .offset(x: inset + CGFloat(clip.start * pps))
    }

    private func select(_ id: UUID) {
        selectedSong = id
        didSelect()
    }

    private func edgeZone(_ clip: AudioClip, item: MediaItem, part: SongEdit.Part) -> some View {
        Color.clear
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(drag(clip, item: item, part: part))
    }

    /// Move keeps the song's in point; trimming the start moves the start
    /// and the in point together, so the music stays where it was on the
    /// clock; trimming the end changes only the length. A trim stops at
    /// either end of the song, and a clip is never shorter than half a
    /// second. Fades shrink with it if it gets shorter than they are.
    private func drag(_ clip: AudioClip, item: MediaItem, part: SongEdit.Part) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("storyline"))
            .onChanged { g in
                if edit?.id != clip.id {
                    edit = SongEdit(id: clip.id, part: part, original: clip, clip: clip,
                                    songLength: item.duration ?? clip.inPoint + clip.length)
                    select(clip.id)
                }
                guard var e = edit else { return }
                let o = e.original
                let dt = ((Double(g.translation.width) / pps) * 100).rounded() / 100
                switch e.part {
                case .move:
                    e.clip.start = max(o.start + dt, 0)
                case .start:
                    // Not before the song's first moment, nor the show's.
                    let lo = max(-o.inPoint, -o.start), hi = o.length - Self.shortest
                    let d = min(max(dt, lo), hi)
                    e.clip.start = o.start + d
                    e.clip.inPoint = o.inPoint + d
                    e.clip.length = o.length - d
                case .end:
                    e.clip.length = min(max(o.length + dt, Self.shortest), e.songLength - o.inPoint)
                }
                let room = e.clip.length
                if e.clip.fadeIn + e.clip.fadeOut > room {
                    let scale = room / (e.clip.fadeIn + e.clip.fadeOut)
                    e.clip.fadeIn = o.fadeIn * scale
                    e.clip.fadeOut = o.fadeOut * scale
                }
                edit = e
            }
            .onEnded { _ in
                guard let e = edit else { return }
                edit = nil
                guard e.clip != e.original else { return }
                mutate(e.part == .move ? "Move Song" : "Trim Song") { s in
                    guard let i = s.music.firstIndex(where: { $0.id == e.id }) else { return }
                    s.music[i] = e.clip
                }
            }
    }

    /// Songs placed from `t`, end to end, each its whole length.
    static func place(_ ids: [Int64], at t: Double, model: AppModel, mutate: ShowMutator) {
        var at = t
        var clips: [AudioClip] = []
        for id in ids {
            guard let d = model.itemsByID[id]?.duration, d > 0 else { continue }
            clips.append(AudioClip(itemID: id, start: (at * 100).rounded() / 100, length: d))
            at += d
        }
        guard !clips.isEmpty else { return }
        mutate(clips.count == 1 ? "Add Song" : "Add Songs") { $0.music += clips }
    }
}

/// One song on the music row: light blue, its waveform, its name.
struct SongClip: View {
    let clip: AudioClip
    let item: MediaItem
    let url: URL?
    let selected: Bool
    let height: CGFloat
    @State private var waveform: Waveform?

    static let fill = Color(red: 0.55, green: 0.76, blue: 0.95)
    static let overlap = Color(red: 0.55, green: 0.90, blue: 0.55).opacity(0.55)
    static let wave = Color(red: 0.12, green: 0.30, blue: 0.52)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4).fill(Self.fill)
            if let waveform {
                WaveformView(waveform: waveform, inPoint: clip.inPoint, length: clip.length, colour: Self.wave)
                    .padding(.vertical, 3)
            }
            Text(item.fileName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Self.wave)
                .lineLimit(1)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Self.fill.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                .padding(3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.35), lineWidth: selected ? 2 : 1)
        }
        .task(id: url) {
            waveform = Waveforms.shared.cached(item)
            if waveform == nil, let url { waveform = await Waveforms.shared.load(item, url: url) }
        }
    }
}
