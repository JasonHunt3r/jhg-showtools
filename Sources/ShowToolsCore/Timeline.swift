import Foundation

/// A slide with every "use the default" resolved and its place in time fixed.
public struct ResolvedSlide: Sendable {
    public let index: Int
    public let slide: Slide
    public let item: MediaItem
    /// When the transition into this slide begins.
    public let start: Double
    /// Seconds from `start` to the next slide's `start`. Includes this
    /// slide's incoming transition.
    public let length: Double
    /// Duration already clamped to fit between its neighbours.
    public let transitionIn: Transition
    public let kenBurns: KenBurns?
    public let fit: Fit
    /// How long the slide is on screen in total: its own length plus the
    /// transition out of it, during which it is still visible underneath.
    public internal(set) var visibleSpan: Double

    public var end: Double { start + length }
}

/// One slide as it should appear at a moment.
public struct Layer: Sendable {
    public let slide: ResolvedSlide
    /// Seconds since this slide's `start` (its transition in began).
    public let localTime: Double

    /// 0…1 through the Ken Burns move, which spans everything visible.
    public var kenBurnsProgress: Double {
        slide.visibleSpan > 0 ? min(max(localTime / slide.visibleSpan, 0), 1) : 0
    }

    public var kenBurnsFrame: KenBurnsFrame {
        slide.kenBurns?.frame(at: kenBurnsProgress) ?? .centred
    }
}

/// What the screen shows at one instant.
///
/// This is the single description every output works from — the player, the
/// scrubber, the live desktop, and a future video exporter, which will ask
/// for one of these per frame.
public enum FrameState: Sendable {
    case empty
    case still(Layer)
    case transition(from: Layer, to: Layer, style: Transition, progress: Double)

    /// The slide that owns this moment: the incoming one mid-transition.
    public var currentIndex: Int? {
        switch self {
        case .empty: nil
        case .still(let l): l.slide.index
        case .transition(_, let to, _, _): to.slide.index
        }
    }

    public var layers: [Layer] {
        switch self {
        case .empty: []
        case .still(let l): [l]
        case .transition(let a, let b, _, _): [a, b]
        }
    }
}

public struct ShowTimeline: Sendable {
    public let slides: [ResolvedSlide]
    public let duration: Double
    public let loops: Bool

    /// Slides whose library item is missing are skipped.
    public init(show: Show, items: [Int64: MediaItem]) {
        let d = show.defaults
        var resolved: [ResolvedSlide] = []
        var t = 0.0

        let present = show.slides.compactMap { s in items[s.itemID].map { (s, $0) } }

        // Lengths first: transition clamping needs both neighbours.
        let lengths: [Double] = present.map { slide, item in
            let spec = slide.settings.length
                ?? (item.kind == .video && d.videoUsesClipLength ? .clip : .seconds(d.length))
            switch spec {
            case .seconds(let s): return max(s, 0.1)
            case .clip: return max(item.duration ?? d.length, 0.1)
            }
        }

        for (i, (slide, item)) in present.enumerated() {
            var transition = slide.settings.transition ?? d.transition
            // A transition can't outlast either slide it joins.
            let prevLength = i > 0 ? lengths[i - 1] : (show.defaults.loop ? lengths.last ?? 0 : 0)
            let limit = min(lengths[i], prevLength > 0 ? prevLength : lengths[i])
            transition.duration = transition.style == .cut ? 0 : min(max(transition.duration, 0), limit)

            let kb: KenBurns? = switch slide.settings.kenBurns ?? d.kenBurns {
            case .off: nil
            case .auto: Self.autoKenBurns(seed: slide.id)
            case .custom(let k): k
            }

            resolved.append(ResolvedSlide(
                index: i, slide: slide, item: item, start: t, length: lengths[i],
                transitionIn: transition, kenBurns: kb,
                fit: slide.settings.fit ?? d.fit, visibleSpan: lengths[i]))
            t += lengths[i]
        }

        // Each slide stays visible through the transition out of it.
        for i in resolved.indices {
            let next = i + 1 < resolved.count ? resolved[i + 1]
                     : (show.defaults.loop ? resolved.first : nil)
            resolved[i].visibleSpan = resolved[i].length + (next?.transitionIn.duration ?? 0)
        }

        slides = resolved
        duration = t
        loops = show.defaults.loop
    }

    public var isEmpty: Bool { slides.isEmpty }

    /// Index of the slide whose span contains `t` (unwrapped into one pass).
    public func index(at t: Double) -> Int {
        guard !slides.isEmpty else { return 0 }
        let local = wrap(t)
        // Binary search on start times.
        var lo = 0, hi = slides.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if slides[mid].start <= local { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func wrap(_ t: Double) -> Double {
        guard duration > 0 else { return 0 }
        if loops {
            let r = t.truncatingRemainder(dividingBy: duration)
            return r < 0 ? r + duration : r
        }
        return min(max(t, 0), duration - 1e-9)
    }

    public func frame(at t: Double) -> FrameState {
        guard !slides.isEmpty else { return .empty }
        let local = wrap(t)
        let i = index(at: t)
        let cur = slides[i]
        let into = local - cur.start
        let d = cur.transitionIn.duration

        // A transition into slide 0 only exists once the show has wrapped.
        let hasPrevious = i > 0 || (loops && t >= duration)
        if d > 0, into < d, hasPrevious, slides.count > 1 {
            let prevIndex = i > 0 ? i - 1 : slides.count - 1
            let prev = slides[prevIndex]
            // The previous slide's clock keeps running past its own end.
            let prevLocal = i > 0 ? local - prev.start : local + duration - prev.start
            return .transition(
                from: Layer(slide: prev, localTime: prevLocal),
                to: Layer(slide: cur, localTime: into),
                style: cur.transitionIn,
                progress: into / d)
        }
        return .still(Layer(slide: cur, localTime: into))
    }

    /// The time at which slide `i` is fully on screen (its transition done).
    public func settledTime(of i: Int) -> Double {
        guard slides.indices.contains(i) else { return 0 }
        return slides[i].start + slides[i].transitionIn.duration
    }

    // MARK: Auto Ken Burns

    /// A slow push in or pull out with a little drift, chosen by the slide's
    /// id so it varies across a show but never between plays.
    static func autoKenBurns(seed: Int64) -> KenBurns {
        var rng = SplitMix64(seed: UInt64(bitPattern: seed))
        let near = 1.12 + rng.unit() * 0.13          // 1.12 … 1.25
        let drift = 0.08
        let a = KenBurnsFrame(x: 0.5, y: 0.5, zoom: 1.0)
        let b = KenBurnsFrame(x: 0.5 + (rng.unit() * 2 - 1) * drift,
                              y: 0.5 + (rng.unit() * 2 - 1) * drift,
                              zoom: near)
        return rng.unit() < 0.5 ? KenBurns(start: a, end: b, easing: .linear)
                                : KenBurns(start: b, end: a, easing: .linear)
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
