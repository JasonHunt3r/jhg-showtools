import Foundation

/// A point on a level line: a level at a time, both belonging to the clip
/// it sits on (`time` is seconds from the clip's own start, not the show's).
public struct LevelPoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    /// Seconds from the clip's start.
    public var time: Double
    /// 0…1.
    public var level: Double

    public init(time: Double, level: Double) {
        self.time = max(time, 0)
        self.level = min(max(level, 0), 1)
    }

    /// Field by field, like every saved type. A point without a time or a
    /// level has no sensible fallback, so it fails, and `LevelCurve`'s
    /// decode steps past it rather than losing the rest of the line.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(Double.self, forKey: .time)
        let l = try c.decode(Double.self, forKey: .level)
        self.init(time: t, level: l)
        id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
    }
}

/// A level line along a clip, as any number of points (plan: a video
/// slide's own sound, settled 2026-09-22 — keep someone speaking, drop the
/// dogs barking). The level ramps linearly between points and holds flat
/// past the outermost ones.
///
/// **An empty curve is silence**, which is what a video slide gets until
/// its sound is turned up. `AudioClip` and `OverlayClip` keep their own
/// `volume`/`fadeIn`/`fadeOut` fields and only *describe* themselves as a
/// curve (`AudioClip.curve`), so one drawing path serves all three without
/// changing anything already saved.
public struct LevelCurve: Codable, Hashable, Sendable {
    /// Always in time order.
    public private(set) var points: [LevelPoint]

    public init(points: [LevelPoint] = []) {
        self.points = points.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Each point on its own: one unreadable point doesn't cost the rest of
    /// the line.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try? c.nestedUnkeyedContainer(forKey: .points)
        var read: [LevelPoint] = []
        while let l = list, !l.isAtEnd {
            if let p = try? list!.decode(LevelPoint.self) { read.append(p) } else { _ = try? list!.decode(Skip.self) }
        }
        self.init(points: read)
    }

    /// Decodes anything, to step past an unreadable point.
    private struct Skip: Decodable {}

    /// The level at `local` seconds into the clip: flat before the first
    /// point and after the last, linear between. No points means silence.
    public func level(at local: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if local <= first.time { return first.level }
        if local >= last.time { return last.level }
        // The pair the time falls between. Lines are short (a handful of
        // points), so a walk is cheaper than anything cleverer.
        for (a, b) in zip(points, points.dropFirst()) where local >= a.time && local <= b.time {
            let span = b.time - a.time
            guard span > 1e-9 else { return b.level }
            return a.level + (b.level - a.level) * ((local - a.time) / span)
        }
        return last.level
    }

    // MARK: - Editing
    //
    // Each returns a new curve, so an edit is one value to hand a mutator
    // and one undo step.

    public func adding(time: Double, level: Double) -> LevelCurve {
        LevelCurve(points: points + [LevelPoint(time: time, level: level)])
    }

    /// Adds a point on the line itself, at whatever level it already has
    /// there — clicking a line shouldn't move it.
    public func addingOnLine(at time: Double) -> LevelCurve {
        adding(time: time, level: isEmpty ? 0 : level(at: time))
    }

    public func removing(_ id: LevelPoint.ID) -> LevelCurve {
        LevelCurve(points: points.filter { $0.id != id })
    }

    /// The curve a level-plus-fades clip draws: up from silence over the
    /// fade in, flat at `level`, down to silence over the fade out. This is
    /// how a song and a lane image describe themselves to a level line
    /// without their saved fields changing. It matches `envelope(at:)`
    /// exactly unless the two fades overlap, where the envelope applies
    /// both and this ramps straight from one to the other.
    public static func fades(level: Double, fadeIn: Double, fadeOut: Double,
                             length: Double) -> LevelCurve {
        let end = max(length, 0)
        let inEnd = min(max(fadeIn, 0), end)
        let outStart = max(end - max(fadeOut, 0), 0)
        var points = [LevelPoint(time: 0, level: fadeIn > 0 ? 0 : level)]
        if fadeIn > 0 { points.append(LevelPoint(time: inEnd, level: level)) }
        if fadeOut > 0 {
            points.append(LevelPoint(time: outStart, level: level))
            points.append(LevelPoint(time: end, level: 0))
        } else {
            points.append(LevelPoint(time: end, level: level))
        }
        return LevelCurve(points: points)
    }

    public func moving(_ id: LevelPoint.ID, toTime time: Double, level: Double) -> LevelCurve {
        LevelCurve(points: points.map {
            guard $0.id == id else { return $0 }
            var p = LevelPoint(time: time, level: level)
            p.id = $0.id
            return p
        })
    }
}
