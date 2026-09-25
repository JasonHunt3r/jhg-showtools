import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// "Fill Range with Images…" (W10, work order item 6; plan, "Fill the
/// range with images"): right-click the range on the ruler, pick some
/// pictures, and they replace or displace whatever's there, resized to
/// fill the range exactly. Nothing here is greyed out (settled, Jason,
/// 2026-09-24) — the dialog shows the fill's own numbers as feedback
/// instead of disabling choices that don't apply.
struct FillRangeSheet: View {
    struct Request: Identifiable {
        let range: ClosedRange<Double>
        let id = UUID()
    }

    enum Kind: String, CaseIterable, Identifiable {
        case even, beats, bars, seconds, pattern
        var id: String { rawValue }
        var title: String {
            switch self {
            case .even: "Even"
            case .beats: "Every N beats"
            case .bars: "Every N bars"
            case .seconds: "About every…"
            case .pattern: "Pattern"
            }
        }
    }

    enum Source: String, CaseIterable, Identifiable {
        case collection, library
        var id: String { rawValue }
        var title: String { self == .collection ? "Collection" : "Library" }
    }

    let request: Request
    let show: Show
    let timeline: ShowTimeline
    let mutate: ShowMutator
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    @State private var source: Source = .collection
    @State private var picked: [Int64] = []
    @State private var mode: RangeFillMode = .replace
    @State private var transitionStyle: TransitionStyle?

    @AppStorage("fillRangeKind") private var kind: Kind = .even
    @AppStorage("fillRangeEvery") private var every = 1
    @AppStorage("fillRangeSeconds") private var seconds = 1.0
    @AppStorage("fillRangeTempo") private var tempo: SongRhythm.Tempo = .asDetected
    @AppStorage("beatBarShift") private var barShift = 0
    // The pattern is the Rhythm tool's own: shared, like the apply sheet's.
    @AppStorage("rhythmPattern") private var patternText = "h q q"
    @AppStorage("rhythmQuarter") private var beatsPerQuarter = 4.0

    private var range: ClosedRange<Double> { request.range }

    private var timing: RangeFillTiming {
        switch kind {
        case .even: .even
        case .beats: .rhythm(BeatPlan(mode: .beats(max(every, 1)), tempo: tempo, barShift: barShift))
        case .bars: .rhythm(BeatPlan(mode: .bars(max(every, 1)), tempo: tempo, barShift: barShift))
        case .seconds: .rhythm(BeatPlan(mode: .seconds(max(seconds, 0.25)), tempo: tempo, barShift: barShift))
        case .pattern:
            .rhythm(BeatPlan(mode: .pattern(RhythmPattern(text: patternText), beatsPerQuarter: beatsPerQuarter),
                             tempo: tempo, barShift: barShift))
        }
    }

    /// The songs under the range, for quantizing onto — empty just means
    /// every rhythm choice behaves like Even (nothing's greyed out for it).
    private var songs: [(clip: AudioClip, item: MediaItem)] {
        show.music.compactMap { c in
            guard c.end > range.lowerBound, c.start < range.upperBound, let item = model.itemsByID[c.itemID]
            else { return nil }
            return (c, item)
        }
    }
    private var rhythms: [Int64: SongRhythm] {
        var out: [Int64: SongRhythm] = [:]
        for s in songs { if let r = Rhythms.shared.rhythm(s.item) { out[s.item.id] = r } }
        return out
    }

    private var pickerItems: [MediaItem] {
        switch source {
        case .collection:
            guard let cid = show.collectionID, let c = model.collection(cid) else { return [] }
            return c.itemIDs.compactMap { model.itemsByID[$0] }.filter { $0.kind.isPicture }
        case .library:
            return model.itemsByID.values.filter { $0.kind.isPicture }.sorted { $0.ingestedAt > $1.ingestedAt }
        }
    }

    private var lengths: [Double] {
        RangeFill.lengths(itemCount: picked.count, timing: timing, show: show, rhythms: rhythms, in: range)
    }
    private var cutsUsed: (used: Int, needed: Int) {
        RangeFill.cutsUsed(itemCount: picked.count, timing: timing, show: show, rhythms: rhythms, in: range)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill Range with Images").font(.headline)
            Text("From \(formatClock(range.lowerBound)) to \(formatClock(range.upperBound)) "
                 + "(\(formatSeconds(range.upperBound - range.lowerBound)))")
                .foregroundStyle(.secondary)

            Picker("", selection: $source) {
                ForEach(Source.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)

            picker

            Divider()

            Form {
                Picker("Transition", selection: $transitionStyle) {
                    Text("Show Default").tag(TransitionStyle?.none)
                    ForEach(TransitionStyle.allCases, id: \.self) { Text($0.title).tag(TransitionStyle?.some($0)) }
                }
                Picker("Rhythm", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                if kind == .pattern {
                    LabeledContent("Pattern") {
                        HStack {
                            Text(patternText.isEmpty ? "None" : patternText)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1).truncationMode(.tail)
                            Button("Edit…") { RhythmTool.shared.editPattern(model: model) }
                        }
                    }
                } else if kind == .seconds {
                    LabeledContent("Seconds") {
                        SecondsField(value: seconds) { seconds = min(max($0, 0.25), 60) }
                    }
                } else if kind == .beats || kind == .bars {
                    Stepper(value: $every, in: 1...16) {
                        Text(kind == .beats ? "Every \(every) beat\(every == 1 ? "" : "s")"
                                            : "Every \(every) bar\(every == 1 ? "" : "s")")
                    }
                }
                if kind != .even {
                    Picker("Tempo", selection: $tempo) {
                        Text("As detected").tag(SongRhythm.Tempo.asDetected)
                        Text("×2").tag(SongRhythm.Tempo.double)
                        Text("÷2").tag(SongRhythm.Tempo.half)
                    }
                    .pickerStyle(.segmented)
                }
                Picker("Fill by", selection: $mode) {
                    Text("Replace").tag(RangeFillMode.replace)
                    Text("Displace").tag(RangeFillMode.displace)
                }
                .pickerStyle(.segmented)
                .help(mode == .replace
                      ? "What's inside the range is removed; the show's length doesn't change."
                      : "Nothing is removed; everything after the range moves later, and the show gets longer.")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: kind == .even ? 150 : (kind == .pattern || kind == .seconds || kind == .beats || kind == .bars ? 220 : 180))

            feedback

            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Fill") { fill() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            for s in songs { if let url = model.url(for: s.item) { await Rhythms.shared.load(s.item, url: url) } }
        }
    }

    private var picker: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                ForEach(pickerItems) { item in
                    let n = picked.firstIndex(of: item.id).map { $0 + 1 }
                    Button {
                        if let i = picked.firstIndex(of: item.id) { picked.remove(at: i) } else { picked.append(item.id) }
                    } label: {
                        ThumbnailView(item: item, url: model.url(for: item))
                            .frame(width: 84, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(n != nil ? Color.accentColor : .clear, lineWidth: 3))
                            .overlay(alignment: .topLeading) {
                                if let n {
                                    Text("\(n)").font(.caption2.weight(.bold)).monospacedDigit()
                                        .padding(3).background(Color.accentColor, in: Circle())
                                        .foregroundStyle(.white).padding(3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(item.fileName)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 160)
        .overlay {
            if pickerItems.isEmpty {
                Text(source == .collection ? "This show's collection has no pictures." : "The library has no pictures.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var feedback: some View {
        if picked.isEmpty {
            Text("Pick some pictures above.").foregroundStyle(.secondary).font(.callout)
        } else {
            let (used, needed) = cutsUsed
            VStack(alignment: .leading, spacing: 2) {
                Text("\(picked.count) image\(picked.count == 1 ? "" : "s"), \(lengths.map(formatSeconds).joined(separator: ", "))")
                    .font(.callout).lineLimit(2)
                if needed > 0 {
                    Text(used == needed ? "Every cut lands on a beat."
                                        : "\(used) of \(needed) cut\(needed == 1 ? "" : "s") land on a beat; "
                                          + "the rest split the leftover time evenly.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fill() {
        guard !picked.isEmpty, model.bringIntoCollection(picked, forShow: show.id) else { return }
        let plan = RangeFillPlan(itemIDs: picked, timing: timing, transition: transitionOverride, mode: mode)
        let rhythms = rhythms, timeline = timeline, range = range
        mutate(mode == .replace ? "Fill Range" : "Fill Range (Displace)") { s in
            s = RangeFill.apply(plan, to: s, timeline: timeline, rhythms: rhythms, in: range)
        }
        close()
    }

    private var transitionOverride: ShowToolsCore.Transition? {
        guard let transitionStyle else { return nil }
        let base = show.defaults.transition
        return ShowToolsCore.Transition(style: transitionStyle, duration: base.duration,
                                        direction: base.direction, lead: base.lead)
    }

    private func close() { dismiss() }
}
