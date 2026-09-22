import SwiftUI
import ShowToolsCore

/// The storyline's music row (plan, Phase 3): songs as clips on the show's
/// clock, each drawn with its waveform. Drop songs from Finder, the library
/// or the collection list to place them where they land; several dropped at
/// once go end to end. Moving, trimming, crossfades and the level line come
/// in step 3.
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
            ForEach(show.music) { clip in
                if let item = model.itemsByID[clip.itemID] {
                    SongClip(clip: clip, item: item, url: model.url(for: item),
                             selected: selectedSong == clip.id, height: height)
                        .frame(width: max(CGFloat(clip.length * pps), 4), height: height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSong = clip.id
                            didSelect()
                        }
                        .contextMenu {
                            Button("Remove Song") {
                                mutate("Remove Song") { $0.music.removeAll { $0.id == clip.id } }
                                if selectedSong == clip.id { selectedSong = nil }
                            }
                        }
                        .help("\(item.fileName) · \(formatSeconds(clip.length))")
                        .offset(x: inset + CGFloat(clip.start * pps))
                }
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
