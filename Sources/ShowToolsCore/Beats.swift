import Foundation

/// A song's rhythm, found by beat detection (plan, Phase 3 step 6), in song
/// seconds: every beat, every bar start (beat 1), the tempo, and the song's
/// sections. Cached per file by hash, so each song is analysed once. How
/// it's found (Apple's Music Understanding, macOS 27) lives in the app;
/// everything done with it lives here, where it can be tested.
public struct SongRhythm: Codable, Hashable, Sendable {
    public var beats: [Double]
    public var bars: [Double]
    public var beatsPerMinute: Double?
    /// The song's large parts (verse, chorus…), start to end.
    public var sections: [Span]

    public struct Span: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) { self.start = start; self.end = end }
    }

    public init(beats: [Double], bars: [Double], beatsPerMinute: Double? = nil, sections: [Span] = []) {
        self.beats = beats.sorted()
        self.bars = bars.sorted()
        self.beatsPerMinute = beatsPerMinute
        self.sections = sections
    }

    /// Field by field, like every saved type.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        beats = (((try? c.decodeIfPresent([Double].self, forKey: .beats)) ?? nil) ?? []).sorted()
        bars = (((try? c.decodeIfPresent([Double].self, forKey: .bars)) ?? nil) ?? []).sorted()
        beatsPerMinute = (try? c.decodeIfPresent(Double.self, forKey: .beatsPerMinute)) ?? nil
        sections = ((try? c.decodeIfPresent([Span].self, forKey: .sections)) ?? nil) ?? []
    }

    /// Detectors are most often wrong by a factor of two: they hear 60 BPM
    /// in a 120 BPM song. ×2 puts a beat halfway between each pair; ÷2
    /// keeps every other beat, counting from the bar starts so beat 1 stays.
    /// The bar starts follow (`bars(_:)`).
    public enum Tempo: String, Codable, CaseIterable, Sendable {
        case asDetected, double, half
    }

    /// The beats with a tempo correction applied.
    public func beats(_ tempo: Tempo) -> [Double] {
        switch tempo {
        case .asDetected:
            return beats
        case .double:
            var out: [Double] = []
            for (i, b) in beats.enumerated() {
                out.append(b)
                if i + 1 < beats.count { out.append((b + beats[i + 1]) / 2) }
            }
            return out
        case .half:
            let anchor = bars.first.flatMap { f in beats.firstIndex { abs($0 - f) < 0.02 } } ?? 0
            return beats.enumerated().filter { ($0.offset - anchor) % 2 == 0 }.map(\.element)
        }
    }

    /// The bar starts with the same correction. A detector that heard half
    /// the tempo also heard bars twice as long, so ×2 puts a bar start
    /// halfway between each pair (on the beat nearest there), and ÷2 keeps
    /// every other one, from the first.
    public func bars(_ tempo: Tempo) -> [Double] {
        switch tempo {
        case .asDetected:
            return bars
        case .double:
            let bs = beats(.double)
            var out: [Double] = []
            for (i, b) in bars.enumerated() {
                out.append(b)
                guard i + 1 < bars.count else { continue }
                let mid = (b + bars[i + 1]) / 2
                out.append(bs.min(by: { abs($0 - mid) < abs($1 - mid) }) ?? mid)
            }
            return out
        case .half:
            return bars.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        }
    }

    /// The bar starts moved along by `shift` beats: "bar starts here" for a
    /// detector that put beat 1 on the wrong beat.
    public func bars(shiftedBy shift: Int, tempo: Tempo) -> [Double] {
        let bars = bars(tempo), bs = beats(tempo)
        guard shift != 0, !bs.isEmpty else { return bars }
        return bars.compactMap { bar in
            guard let i = bs.firstIndex(where: { $0 >= bar - 0.02 }) else { return nil }
            let j = i + shift
            return bs.indices.contains(j) ? bs[j] : nil
        }
    }
}

/// The apply sheet's settings (plan, Phase 3 step 6): where the markers go.
public struct BeatPlan: Codable, Hashable, Sendable {
    public enum Mode: Codable, Hashable, Sendable {
        /// Every n beats, counting from the first bar start in the range.
        case beats(Int)
        /// Every n bars.
        case bars(Int)
        /// About every so many seconds, each landing on the nearest beat.
        case seconds(Double)
    }
    public var mode: Mode = .bars(1)
    public var tempo: SongRhythm.Tempo = .asDetected
    /// Beats to move beat 1 by ("bar starts here").
    public var barShift = 0

    public init(mode: Mode = .bars(1), tempo: SongRhythm.Tempo = .asDetected, barShift: Int = 0) {
        self.mode = mode
        self.tempo = tempo
        self.barShift = barShift
    }

    /// Marker times, in song seconds, from `from` to `to`.
    public func markers(_ r: SongRhythm, from: Double, to: Double) -> [Double] {
        let beats = r.beats(tempo).filter { $0 >= from - 1e-6 && $0 <= to + 1e-6 }
        let bars = r.bars(shiftedBy: barShift, tempo: tempo).filter { $0 >= from - 1e-6 && $0 <= to + 1e-6 }
        switch mode {
        case .beats(let n):
            guard n > 0, !beats.isEmpty else { return [] }
            // From beat 1 when there is one in reach, so "every 4" lands on bars.
            let first = bars.first.flatMap { b in beats.firstIndex { abs($0 - b) < 0.02 } } ?? 0
            return stride(from: first, to: beats.count, by: n).map { beats[$0] }
        case .bars(let n):
            guard n > 0 else { return [] }
            return stride(from: 0, to: bars.count, by: n).map { bars[$0] }
        case .seconds(let x):
            guard x > 0, !beats.isEmpty else { return [] }
            var out: [Double] = []
            var t = beats[0]
            while t <= to + 1e-6 {
                if let near = beats.min(by: { abs($0 - t) < abs($1 - t) }), out.last != near { out.append(near) }
                t += x
            }
            return out
        }
    }
}

public enum SlideFitting {
    /// "Fit slides to markers" (plan, Phase 3 step 6): from the slide the
    /// range starts in, each cut in turn lands on the next marker, until
    /// the markers or the slides run out. The slides before are untouched;
    /// what comes after moves with them (the storyline is magnetic). A
    /// marker too close to the previous cut for a slide of at least
    /// `shortest` seconds is skipped.
    ///
    /// `markers` are show times. Returns the show with new lengths.
    public static func fit(_ show: Show, timeline: ShowTimeline, markers: [Double], in range: ClosedRange<Double>,
                           shortest: Double = 0.5) -> Show {
        let targets = markers.filter { range.contains($0) }.sorted()
        guard !targets.isEmpty,
              let first = timeline.slides.firstIndex(where: { $0.start + $0.length > range.lowerBound + 1e-9 })
        else { return show }
        var out = show
        var start = timeline.slides[first].start
        var i = first
        for m in targets where i < timeline.slides.count {
            let length = m - start
            guard length >= shortest - 1e-9 else { continue }
            let id = timeline.slides[i].slide.id
            if let j = out.slides.firstIndex(where: { $0.id == id }) {
                out.slides[j].settings.length = .seconds((length * 1000).rounded() / 1000)
            }
            start = m
            i += 1
        }
        return out
    }
}

public enum BeatDetection {
    /// The marker times a plan gives over `range` (show times), for each
    /// song under it, with that song's rhythm: what the sheet previews.
    public static func preview(_ plan: BeatPlan, show: Show, rhythms: [Int64: SongRhythm],
                               in range: ClosedRange<Double>) -> [(clipID: UUID, times: [Double])] {
        show.music.compactMap { clip in
            guard let r = rhythms[clip.itemID] else { return nil }
            let lo = max(range.lowerBound, clip.start), hi = min(range.upperBound, clip.end)
            guard hi > lo else { return nil }
            let song = plan.markers(r, from: clip.songTime(ofShowTime: lo), to: clip.songTime(ofShowTime: hi))
            return (clip.id, song.map(clip.showTime(ofSongTime:)))
        }
    }

    /// Applies a plan over `range`: each song under it gets the plan's
    /// markers there, replacing the detected ones it had in that stretch
    /// (hand markers are never touched), and, if asked, the slides are
    /// fitted to them. One show edit, so one undo step.
    public static func apply(_ plan: BeatPlan, to show: Show, timeline: ShowTimeline, rhythms: [Int64: SongRhythm],
                             in range: ClosedRange<Double>, fitSlides: Bool) -> Show {
        var out = show
        var all: [Double] = []
        for (clipID, times) in preview(plan, show: show, rhythms: rhythms, in: range) {
            guard let i = out.music.firstIndex(where: { $0.id == clipID }) else { continue }
            let clip = out.music[i]
            let lo = clip.songTime(ofShowTime: max(range.lowerBound, clip.start))
            let hi = clip.songTime(ofShowTime: min(range.upperBound, clip.end))
            out.music[i].markers.removeAll { $0.time >= lo - 1e-6 && $0.time <= hi + 1e-6 }
            out.music[i].markers += times.map { Marker(time: ((clip.songTime(ofShowTime: $0)) * 1000).rounded() / 1000) }
            out.music[i].markers.sort { $0.time < $1.time }
            all += times
        }
        guard fitSlides else { return out }
        // Two songs' markers a hair apart are one cut.
        var cuts: [Double] = []
        for t in all.sorted() where cuts.last.map({ t - $0 > 0.05 }) ?? true { cuts.append(t) }
        return SlideFitting.fit(out, timeline: timeline, markers: cuts, in: range)
    }
}

extension Show {
    /// Every song's detected markers that are showing, at their show times.
    public var detectedMarkers: [(clipID: UUID, marker: Marker, time: Double)] {
        music.flatMap { c in c.visibleMarkers.map { (c.id, $0.marker, $0.time) } }
    }
}

extension Show {
    /// Changes one marker, hand-placed or detected, wherever it lives. A
    /// detected marker's time is in its song's time; a change of time is the
    /// same distance either way.
    public mutating func updateMarker(_ id: UUID, _ change: (inout Marker) -> Void) {
        if let i = markers.firstIndex(where: { $0.id == id }) { change(&markers[i]); return }
        for c in music.indices {
            if let i = music[c].markers.firstIndex(where: { $0.id == id }) { change(&music[c].markers[i]); return }
        }
    }

    /// Removes markers of either kind.
    public mutating func removeMarkers(_ ids: Set<UUID>) {
        markers.removeAll { ids.contains($0.id) }
        for c in music.indices { music[c].markers.removeAll { ids.contains($0.id) } }
    }
}
