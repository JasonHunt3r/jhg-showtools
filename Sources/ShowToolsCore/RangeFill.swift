import Foundation

/// "Fill Range with Images…" (plan, "Fill the range with images"): right-
/// click the range on the ruler, pick some pictures, and they replace or
/// displace whatever's there, resized to fill the range exactly.
public enum RangeFillTiming: Hashable, Sendable {
    /// An equal split — the default.
    case even
    /// The apply sheet's own choices, reused: roughly N beats or bars per
    /// slide, about every X seconds, or a rhythm pattern, quantized onto
    /// detected beats when there's a song under the range.
    case rhythm(BeatPlan)
}

public enum RangeFillMode: Sendable {
    /// The slide the range starts inside is trimmed to end at the in point,
    /// slides wholly inside the range are removed, and the slide the range
    /// ends inside is shortened at its front to start at the out point.
    /// The show's length doesn't change.
    case replace
    /// The start slide is trimmed the same way, but nothing else is
    /// removed: everything from there on moves later, and the show gets
    /// longer.
    case displace
}

public struct RangeFillPlan: Sendable {
    /// In the order they'll appear.
    public var itemIDs: [Int64]
    public var timing: RangeFillTiming
    /// Nil: each new slide uses the show's default transition, like any
    /// other slide with no override of its own.
    public var transition: Transition?
    public var mode: RangeFillMode

    public init(itemIDs: [Int64], timing: RangeFillTiming, transition: Transition?, mode: RangeFillMode) {
        self.itemIDs = itemIDs
        self.timing = timing
        self.transition = transition
        self.mode = mode
    }
}

public enum RangeFill {
    /// The boundary times the fill would cut on: `itemIDs.count + 1` of
    /// them, from the range's start to its end exactly. One less than that
    /// many interior cuts come from the rhythm (when there's one to quantize
    /// onto); whatever's short is split evenly across what's left of the
    /// range, so the fill always fits exactly (settled, Jason, 2026-09-24)
    /// regardless of how sparse the beats are.
    public static func boundaries(itemCount: Int, timing: RangeFillTiming, show: Show,
                                  rhythms: [Int64: SongRhythm], in range: ClosedRange<Double>) -> [Double] {
        guard itemCount > 0 else { return [range.lowerBound, range.upperBound] }
        let neededCuts = itemCount - 1
        var cuts: [Double] = []
        if case .rhythm(let plan) = timing, neededCuts > 0 {
            let raw = BeatDetection.preview(plan, show: show, rhythms: rhythms, in: range)
                .flatMap(\.times).sorted()
                .filter { $0 > range.lowerBound + 1e-6 && $0 < range.upperBound - 1e-6 }
            // Two songs' cuts a hair apart are one cut (as BeatDetection.apply treats them).
            var deduped: [Double] = []
            for t in raw where deduped.last.map({ t - $0 > 0.05 }) ?? true { deduped.append(t) }
            cuts = Array(deduped.prefix(neededCuts))
        }
        var bounds = [range.lowerBound] + cuts
        let missing = neededCuts - cuts.count
        if missing > 0 {
            let from = bounds.last!
            let step = (range.upperBound - from) / Double(missing + 1)
            for k in 1...missing { bounds.append(from + step * Double(k)) }
        }
        bounds.append(range.upperBound)
        return bounds
    }

    /// Each image's length, for the fill and for the dialog's own feedback.
    public static func lengths(itemCount: Int, timing: RangeFillTiming, show: Show,
                               rhythms: [Int64: SongRhythm], in range: ClosedRange<Double>) -> [Double] {
        let b = boundaries(itemCount: itemCount, timing: timing, show: show, rhythms: rhythms, in: range)
        return zip(b, b.dropFirst()).map { $1 - $0 }
    }

    /// Applies the plan over `range`. One show edit, so one undo step at
    /// the caller. Slides are never split by the fill's own boundaries —
    /// each new slide is a plain trim — but see the one-slide case below.
    public static func apply(_ plan: RangeFillPlan, to show: Show, timeline: ShowTimeline,
                             rhythms: [Int64: SongRhythm], in range: ClosedRange<Double>) -> Show {
        guard !plan.itemIDs.isEmpty, range.upperBound > range.lowerBound else { return show }
        var out = show
        let segmentLengths = lengths(itemCount: plan.itemIDs.count, timing: plan.timing, show: show,
                                     rhythms: rhythms, in: range)
        var newSlides: [Slide] = zip(plan.itemIDs, segmentLengths).map { itemID, length in
            var settings = SlideSettings(length: .seconds((length * 1000).rounded() / 1000))
            settings.transition = plan.transition
            return Slide(id: 0, itemID: itemID, settings: settings)
        }

        func insertAfterStart(_ startID: Int64) {
            if let i = out.slides.firstIndex(where: { $0.id == startID }) {
                out.slides.insert(contentsOf: newSlides, at: i + 1)
            } else {
                out.slides += newSlides
            }
        }
        func trimLength(_ id: Int64, to length: Double) {
            guard let i = out.slides.firstIndex(where: { $0.id == id }) else { return }
            out.slides[i].settings.length = .seconds(max((length * 1000).rounded() / 1000, 0.001))
        }

        // The slide the range starts inside. Past every slide: just append.
        guard let startIdx = timeline.slides.firstIndex(where: { $0.start + $0.length > range.lowerBound + 1e-9 })
        else {
            out.slides += newSlides
            return out
        }
        let startSlide = timeline.slides[startIdx]
        trimLength(startSlide.slide.id, to: max(range.lowerBound - startSlide.start, 0))

        guard case .replace = plan.mode else {
            insertAfterStart(startSlide.slide.id)
            return out
        }

        // The slide the range ends inside. Past every slide: nothing to
        // shorten at the far end, same as Displace from here.
        guard let endIdx = timeline.slides.firstIndex(where: { $0.start + $0.length >= range.upperBound - 1e-9 })
        else {
            insertAfterStart(startSlide.slide.id)
            return out
        }
        let endSlide = timeline.slides[endIdx]

        if endIdx == startIdx {
            // The whole range lies inside one slide. Its end-trim above
            // already ends it at the range's start; preserving the show's
            // length (settled) needs something to stand in for what
            // continues past the range's end. That's a second use of the
            // same file, picking up where the range ends — not a split of
            // this slide's own array entry, the ordinary way a file
            // appears more than once in a show. Left out if what's left is
            // under 50ms (not a real slide, just rounding).
            let tailLength = startSlide.end - range.upperBound
            if tailLength > 0.05 {
                var tail = Slide(id: 0, itemID: startSlide.item.id, settings: startSlide.slide.settings)
                tail.settings.length = .seconds((tailLength * 1000).rounded() / 1000)
                // Its incoming join is new (from the last fill image, not
                // from wherever this slide's own predecessor was), so it
                // takes the fill's own transition choice like the rest.
                tail.settings.transition = plan.transition
                if startSlide.item.kind != .image {
                    let v = max(startSlide.clipStart + (range.upperBound - startSlide.start), 0)
                    tail.settings.clipStart = v < 0.001 ? nil : v
                }
                newSlides.append(tail)
            }
        } else {
            // Slides wholly inside the range are removed outright.
            if endIdx > startIdx + 1 {
                let betweenIDs = Set(timeline.slides[(startIdx + 1)..<endIdx].map { $0.slide.id })
                out.slides.removeAll { betweenIDs.contains($0.id) }
            }
            // Shorten the end slide at its front so it starts at the
            // range's end — a video/animation skips ahead into its clip,
            // exactly like a Trim Start drag; a still just gets shorter.
            if let i = out.slides.firstIndex(where: { $0.id == endSlide.slide.id }) {
                out.slides[i].settings.length = .seconds(max(((endSlide.end - range.upperBound) * 1000).rounded() / 1000, 0.001))
                if endSlide.item.kind != .image {
                    let v = max(endSlide.clipStart + (range.upperBound - endSlide.start), 0)
                    out.slides[i].settings.clipStart = v < 0.001 ? nil : v
                }
            }
        }
        insertAfterStart(startSlide.slide.id)
        return out
    }
}
