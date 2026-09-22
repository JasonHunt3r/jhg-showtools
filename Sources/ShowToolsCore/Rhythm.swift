import Foundation

/// A rhythm pattern (plan, Phase 3 step 7): a row of note values, each only
/// the gap to the next slide change. Written as letters, `h q q rq 3e 3e 3e`:
/// `w h q e s` (whole to sixteenth), a dot after a value adds half its length,
/// `3` before one makes it a triplet note (three in the time of two), and `r`
/// before one makes it a rest (it takes time but changes nothing). Spaces are
/// optional. The pattern is saved as its text, so what's stored is what was
/// typed.
public struct RhythmPattern: Hashable, Sendable {
    public enum Value: Character, CaseIterable, Sendable {
        case whole = "w", half = "h", quarter = "q", eighth = "e", sixteenth = "s"

        /// In quarter notes.
        public var quarters: Double {
            switch self {
            case .whole: 4
            case .half: 2
            case .quarter: 1
            case .eighth: 0.5
            case .sixteenth: 0.25
            }
        }
    }

    public struct Note: Hashable, Sendable {
        public var value: Value
        public var dotted = false
        public var triplet = false
        public var rest = false

        public init(_ value: Value, dotted: Bool = false, triplet: Bool = false, rest: Bool = false) {
            self.value = value
            self.dotted = dotted
            self.triplet = triplet
            self.rest = rest
        }

        /// How long it lasts, in quarter notes.
        public var quarters: Double {
            value.quarters * (dotted ? 1.5 : 1) * (triplet ? 2.0 / 3 : 1)
        }

        public var text: String {
            (rest ? "r" : "") + (triplet ? "3" : "") + String(value.rawValue) + (dotted ? "." : "")
        }
    }

    public var notes: [Note]

    public init(_ notes: [Note] = []) { self.notes = notes }

    /// The pattern in letters, one note per word.
    public var text: String { notes.map(\.text).joined(separator: " ") }

    /// How long one pass lasts, in quarter notes.
    public var quarters: Double { notes.reduce(0) { $0 + $1.quarters } }

    /// Reads letters. Anything it can't read is skipped and its offsets (in
    /// characters) are returned, so the text field can mark them.
    public static func parse(_ text: String) -> (pattern: RhythmPattern, unreadable: [Int]) {
        var notes: [Note] = []
        var bad: [Int] = []
        let chars = Array(text.lowercased())
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            let start = i
            var rest = false, triplet = false
            if chars[i] == "r" { rest = true; i += 1 }
            if i < chars.count, chars[i] == "3" { triplet = true; i += 1 }
            guard i < chars.count, let v = Value(rawValue: chars[i]) else {
                // Skip one character and try again from the next.
                bad.append(start)
                i = start + 1
                continue
            }
            i += 1
            var dotted = false
            if i < chars.count, chars[i] == "." { dotted = true; i += 1 }
            notes.append(Note(v, dotted: dotted, triplet: triplet, rest: rest))
        }
        return (RhythmPattern(notes), bad)
    }

    public init(text: String) { self = Self.parse(text).pattern }
}

extension RhythmPattern {
    /// The ones every library has (plan, Phase 3 step 7).
    public static let builtIns: [(name: String, pattern: RhythmPattern)] = [
        ("Steady", RhythmPattern(text: "q")),
        ("Long, short, short", RhythmPattern(text: "h q q")),
        ("Build", RhythmPattern(text: "w h h q q q q e e e e e e e e")),
        ("Swing (triplet feel)", RhythmPattern(text: "3q 3e")),
    ]
}

/// A pattern saved by name in the library.
public struct SavedRhythm: Hashable, Identifiable, Sendable {
    public let id: Int64
    public var name: String
    public var pattern: RhythmPattern
    /// "A quarter note = N beats" when it was saved; nil leaves it as it is.
    public var beatsPerQuarter: Double?

    public init(id: Int64, name: String, pattern: RhythmPattern, beatsPerQuarter: Double? = nil) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.beatsPerQuarter = beatsPerQuarter
    }
}

extension RhythmPattern: Codable {
    /// Saved as its text: an unreadable save is an empty pattern, never an error.
    public init(from decoder: Decoder) throws {
        let s = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self.init(text: s)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

/// The beat a pattern is counted on, in show time: an even pulse at a tempo,
/// or a song's detected beats (so a song that drifts is still followed).
public enum RhythmPulse: Hashable, Sendable {
    case even(beatsPerMinute: Double)
    /// Beat times, in show seconds, in order.
    case beats([Double])

    /// A song's detected beats (with the tempo correction) at their show
    /// times, inside the clip.
    public static func song(_ clip: AudioClip, _ rhythm: SongRhythm, tempo: SongRhythm.Tempo = .asDetected) -> RhythmPulse {
        .beats(rhythm.beats(tempo)
            .map(clip.showTime(ofSongTime:))
            .filter { $0 >= clip.start - 1e-6 && $0 <= clip.end + 1e-6 })
    }
}

public enum RhythmPlacement {
    /// Where a pattern changes slides over `from...to` (show times): from the
    /// start (on a song, its first beat at or after the start), each note in
    /// turn, repeating until the end. The last pass is cut short. Rests take
    /// their time and leave no marker.
    ///
    /// `beatsPerQuarter` is the note-length setting ("a quarter note = N
    /// beats"). On detected beats, a note that ends between two beats lands
    /// in proportion between them. Past the song's last beat there is no
    /// pulse, so nothing more is placed.
    public static func markers(_ pattern: RhythmPattern, beatsPerQuarter: Double, pulse: RhythmPulse,
                               from: Double, to: Double) -> [Double] {
        guard beatsPerQuarter > 0, pattern.quarters > 0, to > from,
              pattern.notes.contains(where: { !$0.rest }) else { return [] }
        let time: (Double) -> Double?
        switch pulse {
        case .even(let bpm):
            guard bpm > 0 else { return [] }
            time = { from + $0 * 60 / bpm }
        case .beats(let all):
            guard let first = all.firstIndex(where: { $0 >= from - 1e-6 }) else { return [] }
            let bs = Array(all[first...])
            time = { b in
                let k = Int((b + 1e-9).rounded(.down)), frac = max(0, b - Double(k))
                guard k < bs.count else { return nil }
                if frac < 1e-9 { return bs[k] }
                guard k + 1 < bs.count else { return nil }
                return bs[k] + frac * (bs[k + 1] - bs[k])
            }
        }
        var out: [Double] = []
        var beat = 0.0
        // A pass always moves the pulse on, but cap it anyway.
        for _ in 0..<100_000 {
            for note in pattern.notes {
                guard let t = time(beat), t <= to + 1e-6 else { return out }
                if !note.rest { out.append((t * 1000).rounded() / 1000) }
                beat += note.quarters * beatsPerQuarter
            }
        }
        return out
    }
}

public enum RhythmApply {
    /// The Rhythm tool's Apply: hand markers (orange) at `times`, skipping
    /// any with one already there, and, if asked, the slides fitted to them
    /// over `range`. One show edit, so one undo step.
    public static func apply(_ times: [Double], to show: Show, timeline: ShowTimeline,
                             in range: ClosedRange<Double>, fitSlides: Bool) -> Show {
        var out = show
        for t in times where !out.markers.contains(where: { abs($0.time - t) < 0.05 }) {
            out.markers.append(Marker(time: t))
        }
        out.markers.sort { $0.time < $1.time }
        guard fitSlides else { return out }
        return SlideFitting.fit(out, timeline: timeline, markers: times, in: range)
    }
}

/// Where a pattern's notes go when it's drawn as notation (plan, Phase 3
/// step 7): one rhythm line, in staff spaces from the left. Eighths and
/// sixteenths are beamed within each beat; triplet notes are bracketed in
/// threes; a bar line falls every `barQuarters` where a note ends exactly
/// on it (4/4 by default). Drawing it is the app's job.
public enum RhythmNotation {
    public struct Item: Hashable, Sendable {
        public let note: RhythmPattern.Note
        /// When it starts in the pattern, in quarter notes.
        public let start: Double
        /// Where its notehead (or rest) begins, in staff spaces.
        public let x: Double
    }

    public struct Layout: Hashable, Sendable {
        public var items: [Item] = []
        /// Bar lines' x, in staff spaces.
        public var barLines: [Double] = []
        /// Runs of item indices beamed together (two notes or more).
        public var beams: [ClosedRange<Int>] = []
        /// Runs of item indices under one triplet mark.
        public var tuplets: [ClosedRange<Int>] = []
        /// Where the closing repeat sign goes: the pattern repeats.
        public var end: Double = 0
    }

    /// The room a note takes, in staff spaces: more for longer notes, but
    /// not in proportion, as engravers space them.
    public static func advance(_ quarters: Double) -> Double { 2.2 + 3.2 * quarters }

    static let margin = 1.0
    static let barGap = 1.6

    public static func layout(_ p: RhythmPattern, barQuarters: Double = 4) -> Layout {
        var out = Layout()
        var x = margin, t = 0.0
        for (i, n) in p.notes.enumerated() {
            out.items.append(Item(note: n, start: t, x: x))
            x += advance(n.quarters)
            t += n.quarters
            let onBar = abs(t / barQuarters - (t / barQuarters).rounded()) < 1e-6
            if onBar, i < p.notes.count - 1 {
                // Just after this note's room, with a gap before the next.
                out.barLines.append(x + 0.2)
                x += barGap
            }
        }
        out.end = x
        out.beams = runs(out.items) { a, b in
            beamable(a.note) && beamable(b.note) && beat(a) == beat(b)
        }.filter { $0.count >= 2 }
        out.tuplets = runs(out.items) { a, b in a.note.triplet && b.note.triplet }
            .filter { out.items[$0.lowerBound].note.triplet }
            .flatMap { r in stride(from: r.lowerBound, through: r.upperBound, by: 3).map { $0...min($0 + 2, r.upperBound) } }
        return out
    }

    static func beamable(_ n: RhythmPattern.Note) -> Bool {
        !n.rest && (n.value == .eighth || n.value == .sixteenth)
    }

    static func beat(_ i: Item) -> Int { Int((i.start + 1e-6).rounded(.down)) }

    /// Maximal runs where each neighbouring pair belongs together.
    static func runs(_ items: [Item], _ together: (Item, Item) -> Bool) -> [ClosedRange<Int>] {
        guard !items.isEmpty else { return [] }
        var out: [ClosedRange<Int>] = []
        var start = 0
        for i in items.indices.dropFirst() where !together(items[i - 1], items[i]) {
            out.append(start...(i - 1))
            start = i
        }
        out.append(start...(items.count - 1))
        return out
    }
}

/// A pattern as a drum machine's step grid (plan, Phase 3 step 7): a lit
/// square is a slide change; the gaps between them are the note values.
/// Straight grids have 16 steps a bar (sixteenths); triplet grids have 12
/// (triplet eighths). A pattern that fits neither (straight and triplet
/// notes mixed, say) has no grid.
public struct RhythmGrid: Hashable, Sendable {
    public enum Feel: Int, CaseIterable, Sendable {
        /// Steps per quarter note.
        case straight = 4, triplet = 3
    }

    public var feel: Feel
    /// One per step, for one pass of the pattern.
    public var cells: [Bool]

    public var stepsPerBar: Int { feel.rawValue * 4 }
    public var bars: Int { max(1, (cells.count + stepsPerBar - 1) / stepsPerBar) }

    public init(feel: Feel = .straight, cells: [Bool]) {
        self.feel = feel
        self.cells = cells
    }

    /// An empty bar.
    public static func empty(_ feel: Feel = .straight) -> RhythmGrid {
        RhythmGrid(feel: feel, cells: Array(repeating: false, count: feel.rawValue * 4))
    }

    /// The pattern on this grid, or nil if a note falls between its steps.
    public init?(_ p: RhythmPattern, feel: Feel) {
        let per = Double(feel.rawValue)
        func step(_ q: Double) -> Int? {
            let s = q * per
            return abs(s - s.rounded()) < 1e-6 ? Int(s.rounded()) : nil
        }
        guard let total = step(p.quarters) else { return nil }
        var cells = Array(repeating: false, count: total)
        var t = 0.0
        for n in p.notes {
            guard let s = step(t) else { return nil }
            if !n.rest, s < total { cells[s] = true }
            t += n.quarters
        }
        self.init(feel: feel, cells: cells)
    }

    /// The grid a pattern shows on: straight if it can, else triplet; an
    /// empty pattern is an empty straight bar.
    public static func fitting(_ p: RhythmPattern) -> RhythmGrid? {
        if p.notes.isEmpty { return .empty() }
        return RhythmGrid(p, feel: .straight) ?? RhythmGrid(p, feel: .triplet)
    }

    /// The pattern it spells: each gap from a lit square to the next is one
    /// note, as long a value as fits without crossing a bar line, with rests
    /// making up the rest, also split at bar lines (Jason, 2026-09-22): 5
    /// sixteenths is `q rs`, and a quarter on beat 4 before an empty bar is
    /// `q rw`. Squares before the first lit one are rests.
    public var pattern: RhythmPattern {
        var notes: [RhythmPattern.Note] = []
        let lit = cells.indices.filter { cells[$0] }
        if let first = lit.first, first > 0 { notes += spell(from: 0, first) }
        if lit.isEmpty, !cells.isEmpty { notes += spell(from: 0, cells.count) }
        for (k, s) in lit.enumerated() {
            let next = k + 1 < lit.count ? lit[k + 1] : cells.count
            let gap = spell(from: s, next - s)
            if var head = gap.first {
                head.rest = false
                notes += [head] + gap.dropFirst()
            }
        }
        return RhythmPattern(notes)
    }

    /// `steps` from step `start` as rests (the caller un-rests the first),
    /// each as long as fits before the next bar line.
    private func spell(from start: Int, _ steps: Int) -> [RhythmPattern.Note] {
        var out: [RhythmPattern.Note] = []
        var at = start, left = steps
        while left > 0 {
            let room = min(left, stepsPerBar - at % stepsPerBar)
            let piece = spell(room, rest: true)
            guard !piece.isEmpty else { break }
            out += piece
            at += room
            left -= room
        }
        return out
    }

    /// `steps` as notes, longest first.
    private func spell(_ steps: Int, rest: Bool) -> [RhythmPattern.Note] {
        typealias N = RhythmPattern.Note
        let values: [(Int, N)] = switch feel {
        case .straight:
            [(24, N(.whole, dotted: true, rest: rest)), (16, N(.whole, rest: rest)),
             (12, N(.half, dotted: true, rest: rest)), (8, N(.half, rest: rest)),
             (6, N(.quarter, dotted: true, rest: rest)), (4, N(.quarter, rest: rest)),
             (3, N(.eighth, dotted: true, rest: rest)), (2, N(.eighth, rest: rest)), (1, N(.sixteenth, rest: rest))]
        case .triplet:
            [(18, N(.whole, dotted: true, rest: rest)), (12, N(.whole, rest: rest)),
             (9, N(.half, dotted: true, rest: rest)), (6, N(.half, rest: rest)),
             (3, N(.quarter, rest: rest)), (2, N(.quarter, triplet: true, rest: rest)),
             (1, N(.eighth, triplet: true, rest: rest))]
        }
        var left = steps, out: [N] = []
        while left > 0, let (n, note) = values.first(where: { $0.0 <= left }) {
            out.append(note)
            left -= n
        }
        return out
    }

    /// Lengthened (with empty squares) or shortened to whole bars.
    public func resized(bars n: Int) -> RhythmGrid {
        let count = max(1, n) * stepsPerBar
        var c = Array(cells.prefix(count))
        c += Array(repeating: false, count: count - c.count)
        return RhythmGrid(feel: feel, cells: c)
    }

    /// The same squares in time, on the other feel, if every lit one lands
    /// on a step there (an empty grid always does).
    public func converted(to f: Feel) -> RhythmGrid? {
        guard f != feel else { return self }
        guard let g = RhythmGrid(pattern, feel: f) else { return nil }
        return g.resized(bars: bars)
    }
}
