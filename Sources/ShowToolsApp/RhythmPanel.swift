import SwiftUI
import ShowToolsCore

/// The Rhythm tool (plan, Phase 3 step 7): a floating panel that writes a
/// rhythm pattern and lays it over the range as hand markers, on an even
/// BPM or on the song's detected beats, optionally fitting the slides to
/// them. It stays open while you work, so it can be applied to one range
/// after another. It works on the show the storyline is showing.
@MainActor @Observable
final class RhythmTool {
    static let shared = RhythmTool()

    /// The show it works on: the storyline's, followed while it's open.
    var showID: Int64?
    /// The main window's, so Apply undoes there and ⌘Z works in the panel.
    @ObservationIgnored var undoManager: UndoManager?
    /// Where Apply would put markers (show times), drawn faintly on the ruler.
    var preview: [Double] = []
    var isOpen: Bool { panel != nil }

    @ObservationIgnored private var panel: RhythmPanel?

    func open(showID: Int64, model: AppModel, undoManager: UndoManager?) {
        self.showID = showID
        if let undoManager { self.undoManager = undoManager }
        if let panel { panel.front(); return }
        let p = RhythmPanel(model: model, tool: self)
        panel = p
        p.front()
    }

    /// While it's open, the storyline on screen keeps it on its show,
    /// without bringing the panel forward.
    func follow(showID: Int64, undoManager: UndoManager?) {
        guard isOpen else { return }
        self.showID = showID
        if let undoManager { self.undoManager = undoManager }
        panel?.useUndoManager(self.undoManager)
    }

    fileprivate func closed() {
        panel = nil
        preview = []
    }
}

@MainActor
private final class RhythmPanel: NSObject, NSWindowDelegate {
    private let window: InfoPanelWindow
    private let tool: RhythmTool

    init(model: AppModel, tool: RhythmTool) {
        self.tool = tool
        window = InfoPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Rhythm"
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.sharedUndoManager = tool.undoManager
        window.contentView = NSHostingView(rootView: RhythmPanelContent().environment(model).environment(tool))
        // The first time, bottom right of the screen; after that, where it was left.
        if !window.setFrameUsingName("rhythmPanel"), let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - window.frame.width - 20,
                                          y: screen.visibleFrame.minY + 80))
        }
        window.setFrameAutosaveName("rhythmPanel")
    }

    func front() {
        window.sharedUndoManager = tool.undoManager
        window.makeKeyAndOrderFront(nil)
    }

    func useUndoManager(_ u: UndoManager?) { window.sharedUndoManager = u }

    func windowWillClose(_ notification: Notification) { tool.closed() }
}

struct RhythmPanelContent: View {
    @Environment(AppModel.self) private var model
    @Environment(RhythmTool.self) private var tool

    // Remembered for next time.
    @AppStorage("rhythmPattern") private var text = "h q q"
    /// "A quarter note = N beats".
    @AppStorage("rhythmQuarter") private var beatsPerQuarter = 4.0
    /// The even pulse's tempo, used with no song, or when typed over one.
    @AppStorage("rhythmBPM") private var bpm = 120.0
    @AppStorage("rhythmFit") private var fitSlides = true
    /// Off once a BPM is typed over a song; "Use the song's beats" turns it back on.
    @State private var followSong = true

    private var show: Show? { tool.showID.flatMap { model.show($0) } }

    private var parsed: (pattern: RhythmPattern, unreadable: [Int]) { RhythmPattern.parse(text) }

    /// The range, or the whole show.
    private func range(_ show: Show, _ timeline: ShowTimeline) -> ClosedRange<Double> {
        PlaybackEngine.range(of: show.editor, duration: timeline.duration) ?? 0...max(timeline.duration, 0.1)
    }

    /// The song the pattern follows: the one playing where the range starts,
    /// else the first one inside it.
    private func song(_ show: Show, in r: ClosedRange<Double>) -> (clip: AudioClip, item: MediaItem)? {
        let under = show.music.filter { $0.end > r.lowerBound && $0.start < r.upperBound }
        let clip = under.first { $0.start <= r.lowerBound + 1e-6 } ?? under.min { $0.start < $1.start }
        guard let clip, let item = model.itemsByID[clip.itemID] else { return nil }
        return (clip, item)
    }

    private struct Setup {
        let show: Show
        let timeline: ShowTimeline
        let range: ClosedRange<Double>
        let song: (clip: AudioClip, item: MediaItem)?
        let rhythm: SongRhythm?
    }

    private var setup: Setup? {
        guard let show else { return nil }
        let t = model.timeline(for: show)
        let r = range(show, t)
        let s = song(show, in: r)
        return Setup(show: show, timeline: t, range: r, song: s, rhythm: s.flatMap { Rhythms.shared.rhythm($0.item) })
    }

    /// On the song's beats while following it, else an even pulse.
    private func pulse(_ s: Setup) -> RhythmPulse {
        if followSong, let song = s.song, let r = s.rhythm { return .song(song.clip, r) }
        return .even(beatsPerMinute: bpm)
    }

    private func times(_ s: Setup) -> [Double] {
        RhythmPlacement.markers(parsed.pattern, beatsPerQuarter: beatsPerQuarter, pulse: pulse(s),
                                from: s.range.lowerBound, to: s.range.upperBound)
    }

    var body: some View {
        Group {
            if let s = setup {
                content(s)
                    .onAppear { tool.preview = times(s) }
                    .onChange(of: times(s)) { _, t in tool.preview = t }
                    .task(id: s.song?.item.id) {
                        // A song not yet analysed starts now.
                        if let item = s.song?.item, let url = model.url(for: item) {
                            await Rhythms.shared.load(item, url: url)
                        }
                    }
            } else {
                ContentUnavailableView("No Show", systemImage: "music.note.list",
                                       description: Text("Open a show in Edit Show to lay a rhythm on it."))
            }
        }
        .frame(width: 380)
    }

    @ViewBuilder private func content(_ s: Setup) -> some View {
        let t = times(s)
        VStack(alignment: .leading, spacing: 12) {
            Text("From \(formatClock(s.range.lowerBound)) to \(formatClock(s.range.upperBound))"
                 + (PlaybackEngine.range(of: s.show.editor, duration: s.timeline.duration) != nil ? " (the range)" : ""))
                .foregroundStyle(.secondary)

            patternField
            RhythmNotationView(pattern: parsed.pattern)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            legend

            Form {
                tempoRow(s)
                Picker("A quarter note =", selection: $beatsPerQuarter) {
                    Text("¼ beat").tag(0.25)
                    Text("½ beat").tag(0.5)
                    Text("1 beat").tag(1.0)
                    Text("2 beats").tag(2.0)
                    Text("4 beats (a bar)").tag(4.0)
                    Text("8 beats").tag(8.0)
                }
                Toggle("Fit slides to markers", isOn: $fitSlides)
                    .help("From the slide the range starts in, each slide is resized to end on the next marker")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 200)

            HStack {
                Text("\(t.count) marker\(t.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { apply(s, t) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(t.isEmpty)
            }
        }
        .padding(16)
    }

    // MARK: The pattern

    private var patternField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Pattern", text: $text, prompt: Text("h q q rq 3e 3e 3e"))
                .font(.system(.title3, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            let (p, bad) = parsed
            if !bad.isEmpty {
                let chars = Array(text)
                let shown = bad.compactMap { chars.indices.contains($0) ? "“\(chars[$0])”" : nil }
                Text("Skipped \(shown.joined(separator: ", ")): not a note")
                    .font(.callout).foregroundStyle(.orange)
            } else if !p.notes.isEmpty, !p.notes.contains(where: { !$0.rest }) {
                Text("All rests: nothing to place").font(.callout).foregroundStyle(.orange)
            } else {
                Text(p.notes.isEmpty ? " " : "One pass: \(Self.quartersText(p.quarters))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private static func quartersText(_ q: Double) -> String {
        let n = (q * 1000).rounded() / 1000
        let s = n == n.rounded() ? "\(Int(n))" : String(format: "%g", n)
        return "\(s) quarter note\(n == 1 ? "" : "s")"
    }

    /// Each glyph with its letter: click to add it (a "Rosetta stone").
    private var legend: some View {
        // SMuFL code points in Bravura (bundled; see make-app.sh).
        let notes: [(String, String, String)] = [
            ("\u{E1D2}", "w", "Whole note"), ("\u{E1D3}", "h", "Half note"), ("\u{E1D5}", "q", "Quarter note"),
            ("\u{E1D7}", "e", "Eighth note"), ("\u{E1D9}", "s", "Sixteenth note"),
        ]
        let marks: [(String, String, String)] = [
            ("\u{E4E5}", "r", "Rest: put before a note value (rq is a quarter rest)"),
            ("\u{E1E7}", ".", "Dot: half as long again"),
            ("\u{E883}", "3", "Triplet: put before a note value (3e 3e 3e fills a quarter)"),
        ]
        return HStack(spacing: 4) {
            ForEach(notes + marks, id: \.1) { glyph, letter, help in
                Button { add(letter) } label: {
                    VStack(spacing: 0) {
                        Text(glyph).font(.custom("Bravura", size: letter == "." ? 44 : 22))
                            .frame(height: 28)
                        Text(letter).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .frame(width: 32, height: 42)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityLabel("\(help.prefix { $0 != ":" }) (\(letter))")
            }
            Button { removeLast() } label: {
                Image(systemName: "delete.left")
                    .frame(width: 32, height: 42)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove the last note")
        }
    }

    /// Adds a letter the way it would be typed: a new note after a finished
    /// one gets a space first; a dot joins the note before it.
    private func add(_ letter: String) {
        let last = text.last
        let finished = last.map { "whqes.".contains($0) } ?? false
        if letter != ".", finished { text += " " }
        text += letter
    }

    private func removeLast() {
        var words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return }
        words.removeLast()
        text = words.joined(separator: " ")
    }

    // MARK: Tempo

    @ViewBuilder private func tempoRow(_ s: Setup) -> some View {
        let songBPM = s.rhythm?.beatsPerMinute
        let following = followSong && s.rhythm != nil
        LabeledContent("Tempo") {
            HStack(spacing: 6) {
                TextField("", value: Binding(
                    get: { following ? (songBPM ?? bpm) : bpm },
                    set: { v in
                        bpm = min(max(v, 20), 300)
                        followSong = false
                    }), format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 54)
                    .multilineTextAlignment(.trailing)
                Text("BPM").foregroundStyle(.secondary)
            }
        }
        if let song = s.song {
            HStack {
                switch Rhythms.shared.state(song.item) {
                case .ready:
                    if following {
                        Text("On \(song.item.fileName)'s beats").foregroundStyle(.secondary)
                    } else {
                        Text("An even beat").foregroundStyle(.secondary)
                        Spacer()
                        Button("Use the song's beats") { followSong = true }
                    }
                case .analysing, nil:
                    ProgressView().controlSize(.small)
                    Text("Finding the beats…").foregroundStyle(.secondary)
                case .failed:
                    Text("Couldn't read the song's beats: an even beat").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    private func apply(_ s: Setup, _ times: [Double]) {
        let fit = fitSlides, range = s.range, timeline = s.timeline
        var next = s.show
        next = RhythmApply.apply(times, to: next, timeline: timeline, in: range, fitSlides: fit)
        model.update(next, undo: tool.undoManager,
                     action: fit ? "Rhythm Markers and Fit Slides" : "Rhythm Markers")
    }
}
