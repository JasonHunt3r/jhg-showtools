import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// "Detect Beats…" (plan, Phase 3 step 6): markers on the beat, over the
/// range (or one song, with no range), from each song's detected rhythm.
/// Every N beats, every N bars, or about every X seconds on the nearest
/// beat; ×2 / ÷2 and "bar starts here" for a detector that misheard; and
/// optionally the slides fitted to the markers. The markers show faintly on
/// the ruler as the settings change; Apply is one undo step. Step 7 adds
/// rhythm patterns as a fourth way.
struct BeatSheet: View {
    struct Request: Identifiable {
        let range: ClosedRange<Double>
        /// The song it was opened from, if any (for the title).
        let song: UUID?
        let id = UUID()
    }

    enum Kind: String, CaseIterable, Identifiable {
        case beats, bars, seconds, pattern
        var id: String { rawValue }
        var title: String {
            switch self {
            case .beats: "Every N beats"
            case .bars: "Every N bars"
            case .seconds: "About every…"
            case .pattern: "Pattern"
            }
        }
    }

    let request: Request
    let show: Show
    let timeline: ShowTimeline
    @Binding var preview: [Double]
    let mutate: ShowMutator
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // The last settings are remembered for next time, as a sheet's usually are.
    @AppStorage("beatKind") private var kind: Kind = .bars
    @AppStorage("beatEvery") private var every = 1
    @AppStorage("beatSeconds") private var seconds = 3.0
    @AppStorage("beatTempo") private var tempo: SongRhythm.Tempo = .asDetected
    @AppStorage("beatFit") private var fitSlides = true
    @State private var barShift = 0
    // The pattern is the Rhythm tool's: shared, so Edit… changes it here too.
    @AppStorage("rhythmPattern") private var patternText = "h q q"
    @AppStorage("rhythmQuarter") private var beatsPerQuarter = 4.0

    private var plan: BeatPlan {
        let mode: BeatPlan.Mode = switch kind {
        case .beats: .beats(max(every, 1))
        case .bars: .bars(max(every, 1))
        case .seconds: .seconds(max(seconds, 0.25))
        case .pattern: .pattern(RhythmPattern(text: patternText), beatsPerQuarter: beatsPerQuarter)
        }
        return BeatPlan(mode: mode, tempo: tempo, barShift: barShift)
    }

    /// The songs under the range.
    private var songs: [(clip: AudioClip, item: MediaItem)] {
        show.music.compactMap { c in
            guard c.end > request.range.lowerBound, c.start < request.range.upperBound,
                  let item = model.itemsByID[c.itemID] else { return nil }
            return (c, item)
        }
    }

    private var rhythms: [Int64: SongRhythm] {
        var out: [Int64: SongRhythm] = [:]
        for s in songs { if let r = Rhythms.shared.rhythm(s.item) { out[s.item.id] = r } }
        return out
    }

    private var times: [Double] {
        BeatDetection.preview(plan, show: show, rhythms: rhythms, in: request.range).flatMap(\.times).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detect Beats").font(.headline)
            Text("From \(formatClock(request.range.lowerBound)) to \(formatClock(request.range.upperBound))"
                 + (show.editor.rangeIn != nil || show.editor.rangeOut != nil ? " (the range)" : ""))
                .foregroundStyle(.secondary)

            if !Rhythms.isAvailable {
                Text("Beat detection uses Apple's Music Understanding, which needs macOS 27. "
                     + "This Mac is on macOS \(Self.systemVersion).")
                    .fixedSize(horizontal: false, vertical: true)
            } else if songs.isEmpty {
                Text("There's no song under this stretch of the show.")
            } else {
                songList
                Divider()
                settings
            }

            HStack {
                if Rhythms.isAvailable, !songs.isEmpty {
                    Text("\(times.count) marker\(times.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                }
                Spacer()
                if Rhythms.isAvailable {
                    Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(times.isEmpty)
                } else {
                    // Nothing to apply before macOS 27 (Jason's wording).
                    Button("Bummer") { close() }
                        .keyboardShortcut(.defaultAction)
                    Button("") { close() }.keyboardShortcut(.cancelAction).hidden()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { preview = times }
        .onChange(of: times) { _, t in preview = t }
        .task {
            // Songs not yet analysed start now.
            for s in songs { if let url = model.url(for: s.item) { await Rhythms.shared.load(s.item, url: url) } }
        }
    }

    /// Each song: its tempo, or where its analysis is up to.
    private var songList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(songs, id: \.clip.id) { s in
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                    Text(s.item.fileName).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    switch Rhythms.shared.state(s.item) {
                    case .ready(let r):
                        Text(r.beatsPerMinute.map { "\(Int($0.rounded())) BPM" } ?? "\(r.beats.count) beats")
                            .foregroundStyle(.secondary).monospacedDigit()
                    case .analysing, nil:
                        ProgressView().controlSize(.small)
                        Text("Finding the beats…").foregroundStyle(.secondary)
                    case .failed(let why):
                        Text("Couldn't read the beats").foregroundStyle(.red).help(why)
                        Button("Try Again") {
                            if let url = model.url(for: s.item) { Task { await Rhythms.shared.retry(s.item, url: url) } }
                        }
                    }
                }
                .font(.callout)
            }
        }
    }

    private var settings: some View {
        Form {
            Picker("Markers", selection: $kind) {
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
                Picker("A quarter note =", selection: $beatsPerQuarter) {
                    Text("¼ beat").tag(0.25)
                    Text("½ beat").tag(0.5)
                    Text("1 beat").tag(1.0)
                    Text("2 beats").tag(2.0)
                    Text("4 beats (a bar)").tag(4.0)
                    Text("8 beats").tag(8.0)
                }
            } else if kind == .seconds {
                LabeledContent("Seconds") {
                    SecondsField(value: seconds) { seconds = min(max($0, 0.25), 60) }
                }
            } else {
                Stepper(value: $every, in: 1...16) {
                    Text(kind == .beats ? "Every \(every) beat\(every == 1 ? "" : "s")"
                                        : "Every \(every) bar\(every == 1 ? "" : "s")")
                }
            }
            Picker("Tempo", selection: $tempo) {
                Text("As detected").tag(SongRhythm.Tempo.asDetected)
                Text("×2").tag(SongRhythm.Tempo.double)
                Text("÷2").tag(SongRhythm.Tempo.half)
            }
            .pickerStyle(.segmented)
            .help("If the markers come twice as fast or slow as the music, the tempo was misheard")
            Stepper(value: $barShift, in: -3...3) {
                Text(barShift == 0 ? "Bar starts as detected"
                                   : "Bar starts moved \(barShift > 0 ? "later" : "earlier") by \(abs(barShift)) beat\(abs(barShift) == 1 ? "" : "s")")
            }
            .help("If beat 1 landed on the wrong beat, move it")
            Toggle("Fit slides to markers", isOn: $fitSlides)
                .help("From the slide the range starts in, each slide is resized to end on the next marker")
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: kind == .pattern ? 270 : 230)
    }

    private func apply() {
        let plan = plan, rhythms = rhythms, range = request.range, fit = fitSlides, timeline = timeline
        mutate(fit ? "Detect Beats and Fit Slides" : "Detect Beats") { s in
            s = BeatDetection.apply(plan, to: s, timeline: timeline, rhythms: rhythms, in: range, fitSlides: fit)
        }
        close()
    }

    private static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    private func close() {
        preview = []
        RhythmTool.shared.endEditingPattern()
        dismiss()
    }
}

