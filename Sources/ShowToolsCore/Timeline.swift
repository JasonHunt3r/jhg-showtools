import Foundation

/// A slide with every "use the default" resolved and its place in time fixed.
public struct ResolvedSlide: Sendable {
    public let index: Int
    public let slide: Slide
    public let item: MediaItem
    /// The join where this slide's block begins on the storyline.
    public let start: Double
    /// Seconds from this join to the next: the slide's length as set.
    public let length: Double
    /// Duration and lead already clamped to fit between its neighbours.
    public internal(set) var transitionIn: Transition
    /// Seconds of the transition out of this slide (the next one's in), or 0.
    public internal(set) var transitionOut: Double = 0
    public let kenBurns: KenBurns?
    public let fit: Fit
    public let transform: Transform
    /// Nil when the slide has no rotation or its checkbox is off.
    public let rotation: Rotation?
    public let background: SRGBColor
    /// Seconds into the media where playback starts (video and animation).
    public let clipStart: Double
    /// How long the slide is on screen in total: from its transition in
    /// beginning (`visibleStart`) to its transition out ending.
    public internal(set) var visibleSpan: Double

    public var end: Double { start + length }
    /// When the transition into this slide begins: its lead before the join.
    public var visibleStart: Double { start - transitionIn.lead }

    /// Seconds an effect moves for; see `Layer.motionSpan`. Assumes both
    /// transitions play, as they do mid-show.
    public func motionSpan(frozen: Bool) -> Double {
        frozen ? max(visibleSpan - transitionIn.duration - transitionOut, 0) : visibleSpan
    }
}

/// One slide as it should appear at a moment.
public struct Layer: Sendable {
    public let slide: ResolvedSlide
    /// Seconds since this slide's `start` (its transition in began).
    public let localTime: Double
    /// Seconds of transition that actually play into and out of this slide
    /// on this pass. They can be 0 where the slide's own settings say
    /// otherwise: the first slide on the first pass has nothing to come in
    /// from, a show that doesn't loop has nothing after its last slide, and
    /// a one-slide show has no transitions at all.
    public let transitionInPlays: Double
    public let transitionOutPlays: Double

    public init(slide: ResolvedSlide, localTime: Double,
                transitionInPlays: Double, transitionOutPlays: Double) {
        self.slide = slide
        self.localTime = localTime
        self.transitionInPlays = transitionInPlays
        self.transitionOutPlays = transitionOutPlays
    }

    /// 0…1 through the Ken Burns move, which spans everything visible.
    public var kenBurnsProgress: Double {
        slide.visibleSpan > 0 ? min(max(localTime / slide.visibleSpan, 0), 1) : 0
    }

    /// Seconds an effect moves for. Frozen, that's only the time the slide
    /// is on screen alone: after its transition in, before its transition out.
    public func motionSpan(frozen: Bool) -> Double {
        frozen ? max(slide.visibleSpan - transitionInPlays - transitionOutPlays, 0) : slide.visibleSpan
    }

    /// 0…1 through an effect's move; see `motionSpan`. Frozen, it holds 0
    /// through the transition in and 1 through the transition out.
    public func motionProgress(frozen: Bool) -> Double {
        guard frozen else { return kenBurnsProgress }
        let span = motionSpan(frozen: true)
        let t = localTime - transitionInPlays
        guard span > 0 else { return t < 0 ? 0 : 1 }
        return min(max(t / span, 0), 1)
    }

    public var kenBurnsFrame: KenBurnsFrame {
        guard let kb = slide.kenBurns else { return .centred }
        return kb.frame(at: motionProgress(frozen: kb.freezeOnTransition))
    }

    /// Degrees clockwise.
    public var rotationAngle: Double {
        guard let r = slide.rotation else { return 0 }
        return r.angle(at: motionProgress(frozen: r.freezeOnTransition),
                       span: motionSpan(frozen: r.freezeOnTransition))
    }

    /// The Rotation effect's turn now, or nil when it's off.
    public var spin: (angle: Double, pivot: ImagePoint)? {
        slide.rotation == nil ? nil : (angle: rotationAngle, pivot: rotationPivot)
    }

    public var rotationPivot: ImagePoint {
        guard let r = slide.rotation else { return .centre }
        return r.pivot(at: motionProgress(frozen: r.freezeOnTransition))
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

/// An image from the lane's images row with its file found.
public struct ResolvedOverlay: Sendable {
    public let clip: OverlayClip
    public let item: MediaItem
    public var start: Double { clip.start }
    public var end: Double { clip.start + clip.length }
}

/// The lane's image as it appears at one moment.
public struct OverlayLayer: Sendable {
    public let overlay: ResolvedOverlay
    /// Seconds since it appeared.
    public let localTime: Double
    /// Its opacity with the fades applied.
    public let opacity: Double
}

public struct ShowTimeline: Sendable {
    public let slides: [ResolvedSlide]
    public let duration: Double
    public let loops: Bool
    /// The images row, earliest first. Clips whose file is missing, or that
    /// have no length, are left out.
    public let overlays: [ResolvedOverlay]

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
            case .clip: return max((item.duration ?? d.length) - (slide.settings.clipStart ?? 0), 0.1)
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
                fit: slide.settings.fit ?? d.fit,
                transform: slide.settings.transform ?? .identity,
                rotation: slide.settings.rotation.flatMap { $0.enabled ? $0 : nil },
                background: slide.settings.background ?? d.background,
                clipStart: item.kind == .image ? 0 : max(slide.settings.clipStart ?? 0, 0),
                visibleSpan: lengths[i]))
            t += lengths[i]
        }

        // Leads: a transition can begin before its join, but only as far as
        // the outgoing slide has room left after its own transition in has
        // finished, so two transitions never overlap. Slide 0's lead (used
        // when a show loops) is fitted after the last slide's, then slide 1
        // is checked again against it.
        func fitLead(_ i: Int) {
            guard resolved.indices.contains(i) else { return }
            let p = i > 0 ? i - 1 : resolved.count - 1
            var tr = resolved[i].transitionIn
            let room = i > 0 || show.defaults.loop
                ? resolved[p].length - (resolved[p].transitionIn.duration - resolved[p].transitionIn.lead)
                : 0
            tr.lead = min(max(tr.lead, 0), tr.duration, max(room, 0))
            resolved[i].transitionIn = tr
        }
        for i in resolved.indices.dropFirst() { fitLead(i) }
        fitLead(0)
        fitLead(1)

        // Each slide stays visible through the transition out of it.
        for i in resolved.indices {
            let next = i + 1 < resolved.count ? resolved[i + 1]
                     : (show.defaults.loop ? resolved.first : nil)
            let out = next?.transitionIn
            resolved[i].transitionOut = out?.duration ?? 0
            resolved[i].visibleSpan = resolved[i].length + resolved[i].transitionIn.lead
                - (out?.lead ?? 0) + (out?.duration ?? 0)
        }

        slides = resolved
        duration = t
        loops = show.defaults.loop
        overlays = show.overlays
            .compactMap { c in c.length > 0 ? items[c.itemID].map { ResolvedOverlay(clip: c, item: $0) } : nil }
            .sorted { $0.start < $1.start }
    }

    /// The lane's image showing at `t`, if any. Images sit on the show's
    /// clock, so a looping show shows them again on every pass.
    public func overlay(at t: Double) -> OverlayLayer? {
        guard !overlays.isEmpty else { return nil }
        let local = wrap(t)
        guard let o = overlays.last(where: { $0.start <= local && local < $0.end }) else { return nil }
        let into = local - o.start, c = o.clip
        var a = min(max(c.opacity, 0), 1)
        if c.fadeIn > 0 { a *= min(into / c.fadeIn, 1) }
        if c.fadeOut > 0 { a *= min((c.length - into) / c.fadeOut, 1) }
        return OverlayLayer(overlay: o, localTime: into, opacity: max(a, 0))
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

    /// `t` is found in a slide's block (join to join). A transition can be
    /// under way at either end of it: the one into this slide runs on past
    /// its join, and the one out of it begins its lead before the next join.
    /// Local times count from each slide's `visibleStart`.
    public func frame(at t: Double) -> FrameState {
        guard !slides.isEmpty else { return .empty }
        let local = wrap(t)
        let i = index(at: t)
        let n = slides.count
        let cur = slides[i]

        // The transition out of this slide, when it has already begun.
        if n > 1, i + 1 < n || loops {
            let ni = (i + 1) % n
            let next = slides[ni]
            let d = next.transitionIn.duration
            let begins = (i + 1 < n ? next.start : duration) - next.transitionIn.lead
            if d > 0, local >= begins {
                let into = local - begins
                return .transition(
                    from: layer(i, localTime: local - cur.visibleStart, at: t),
                    // Into slide 0 across the wrap: its transition does play.
                    to: layer(ni, localTime: into, at: t, transitionInPlays: true),
                    style: next.transitionIn,
                    progress: into / d)
            }
        }

        // The transition into this slide, still running. Into slide 0 only
        // once the show has wrapped.
        let into = local - cur.visibleStart
        let d = cur.transitionIn.duration
        let hasPrevious = i > 0 || (loops && t >= duration)
        if n > 1, d > 0, into < d, hasPrevious {
            let prevIndex = i > 0 ? i - 1 : n - 1
            let prev = slides[prevIndex]
            // The previous slide's clock keeps running past its own end.
            let prevLocal = i > 0 ? local - prev.visibleStart : local + duration - prev.visibleStart
            return .transition(
                from: layer(prevIndex, localTime: prevLocal, at: t),
                to: layer(i, localTime: into, at: t),
                style: cur.transitionIn,
                progress: into / d)
        }
        return .still(layer(i, localTime: into, at: t))
    }

    /// Slide `i` at show time `t`, knowing which of its transitions play on
    /// this pass (the rules `frame(at:)` draws by).
    func layer(_ i: Int, localTime: Double, at t: Double, transitionInPlays: Bool? = nil) -> Layer {
        let s = slides[i]
        let multiple = slides.count > 1
        // Into slide 0 only once the show has wrapped (or as the last slide
        // hands over to it, which the caller says).
        let inPlays = transitionInPlays ?? (multiple && (i > 0 || (loops && t >= duration)))
        let outPlays = multiple && (i < slides.count - 1 || loops)
        return Layer(slide: s, localTime: localTime,
                     transitionInPlays: inPlays ? s.transitionIn.duration : 0,
                     transitionOutPlays: outPlays ? s.transitionOut : 0)
    }

    /// The time at which slide `i` is fully on screen (its transition done).
    public func settledTime(of i: Int) -> Double {
        guard slides.indices.contains(i) else { return 0 }
        return slides[i].visibleStart + slides[i].transitionIn.duration
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

extension ResolvedSlide {
    /// Above this, the picture enlarges the file enough to look soft. A
    /// little enlargement is hard to see, so it isn't flagged.
    public static let softAbove = 1.25

    /// How much the picture enlarges the file at its closest: output pixels
    /// per file pixel, the most it reaches over the slide's time on screen
    /// (Ken Burns, the Transform and rotation all count). Measured against
    /// the file's own size, not the smaller copy decoded for playback.
    public func peakMagnification(outputSize: CGSize) -> Double {
        let e = CGRect(x: 0, y: 0, width: item.pixelWidth, height: item.pixelHeight)
        var peak = 0.0
        for i in 0...20 {
            let layer = Layer(slide: self, localTime: visibleSpan * Double(i) / 20,
                              transitionInPlays: transitionIn.duration,
                              transitionOutPlays: transitionOut)
            guard let m = Compositor.placement(for: layer, imageExtent: e, outputSize: outputSize) else { continue }
            peak = max(peak, Double(max(hypot(m.a, m.b), hypot(m.c, m.d))))
        }
        return peak
    }

    public func isSoft(outputSize: CGSize) -> Bool {
        peakMagnification(outputSize: outputSize) > Self.softAbove
    }
}
