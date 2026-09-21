import SwiftUI
import ShowToolsCore

/// The inspector's Effects timeline: a slide's time on screen, from its
/// transition in beginning to its transition out ending, with a bar for each
/// thing acting on the picture then (Final Cut's Video Animation, but for
/// reading, not dragging). The slide's own block, join to join, is the
/// lighter band behind; hatched stretches of a motion bar are where freeze
/// on transition holds it still.
struct EffectsTimeline: View {
    let slide: ResolvedSlide
    let timeline: ShowTimeline

    struct Bar: Identifiable {
        let id: String
        let label: String
        let detail: String
        let from: Double, to: Double
        let colour: Color
        /// Held still over these stretches (freeze on transition).
        var frozen: [ClosedRange<Double>] = []
    }

    private var span: ClosedRange<Double> {
        slide.visibleStart...(slide.visibleStart + slide.visibleSpan)
    }

    /// Whether the transition in plays at all: not into the first slide of
    /// a show that doesn't loop.
    private var inPlays: Bool {
        timeline.slides.count > 1 && (slide.index > 0 || timeline.loops) && slide.transitionIn.duration > 0
    }

    private var bars: [Bar] {
        let s = span
        let tin = inPlays ? slide.transitionIn.duration : 0
        let tout = slide.transitionOut
        let frozenWindows = [s.lowerBound...(s.lowerBound + tin), (s.upperBound - tout)...s.upperBound]
            .filter { $0.upperBound > $0.lowerBound }
        var out: [Bar] = []
        if tin > 0 {
            let t = slide.transitionIn
            out.append(Bar(id: "in", label: "In", detail: "\(t.style.title), \(formatSeconds(t.duration))",
                           from: s.lowerBound, to: s.lowerBound + tin, colour: .white.opacity(0.8)))
        }
        if let kb = slide.kenBurns {
            out.append(Bar(id: "kb", label: "Ken Burns",
                           detail: String(format: "zoom %.2f → %.2f", kb.start.zoom, kb.end.zoom),
                           from: s.lowerBound, to: s.upperBound, colour: .green,
                           frozen: kb.freezeOnTransition ? frozenWindows : []))
        }
        if let r = slide.rotation {
            let end = r.angle(at: 1, span: slide.motionSpan(frozen: r.freezeOnTransition))
            out.append(Bar(id: "rot", label: "Rotation",
                           detail: String(format: "%.0f° → %.0f°", r.startAngle, end),
                           from: s.lowerBound, to: s.upperBound, colour: .orange,
                           frozen: r.freezeOnTransition ? frozenWindows : []))
        }
        for o in timeline.overlays where o.end > s.lowerBound && o.start < s.upperBound {
            out.append(Bar(id: o.clip.id.uuidString, label: "Image",
                           detail: "\(o.item.fileName), \(o.clip.blend.title) \(Int(o.clip.opacity * 100))%",
                           from: max(o.start, s.lowerBound), to: min(o.end, s.upperBound),
                           colour: Color(red: 0.7, green: 0.5, blue: 0.85)))
        }
        if tout > 0 {
            let next = timeline.slides.indices.contains(slide.index + 1) ? timeline.slides[slide.index + 1]
                     : timeline.slides.first
            if let t = next?.transitionIn {
                out.append(Bar(id: "out", label: "Out", detail: "\(t.style.title), \(formatSeconds(t.duration))",
                               from: s.upperBound - tout, to: s.upperBound, colour: .white.opacity(0.8)))
            }
        }
        return out
    }

    var body: some View {
        let s = span
        let length = max(s.upperBound - s.lowerBound, 0.001)
        VStack(alignment: .leading, spacing: 4) {
            // The time scale: on screen from 0 to its full visible length.
            HStack(spacing: 6) {
                Color.clear.frame(width: 62, height: 1)
                HStack {
                    Text("0s")
                    Spacer()
                    Text(formatSeconds(length))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if bars.isEmpty {
                Text("Nothing moves or covers this slide.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(bars) { bar in row(bar, span: s, length: length) }
        }
        .padding(.vertical, 2)
    }
}

extension EffectsTimeline {
    private func row(_ bar: Bar, span s: ClosedRange<Double>, length: Double) -> some View {
        HStack(spacing: 6) {
            Text(bar.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            GeometryReader { g in
                let w = g.size.width
                let x: (Double) -> CGFloat = { t in CGFloat((t - s.lowerBound) / length) * w }
                ZStack(alignment: .leading) {
                    // The slide's own block, join to join.
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: max(x(slide.end) - x(slide.start), 0))
                        .offset(x: x(slide.start))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bar.colour.opacity(0.75))
                        .frame(width: max(x(bar.to) - x(bar.from), 2))
                        .offset(x: x(bar.from))
                    ForEach(Array(bar.frozen.enumerated()), id: \.offset) { _, f in
                        Hatch()
                            .stroke(Color.black.opacity(0.45), lineWidth: 1)
                            .frame(width: max(x(f.upperBound) - x(f.lowerBound), 0))
                            .clipped()
                            .offset(x: x(f.lowerBound))
                    }
                }
            }
            .frame(height: 12)
            .help("\(bar.label): \(bar.detail), \(formatSeconds(bar.from - s.lowerBound))–\(formatSeconds(bar.to - s.lowerBound))"
                  + (bar.frozen.isEmpty ? "" : " (held still during transitions)"))
        }
    }
}

/// Diagonal lines, for stretches held still.
private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return p
    }
}
