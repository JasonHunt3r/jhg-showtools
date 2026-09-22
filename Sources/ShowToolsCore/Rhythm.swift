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
