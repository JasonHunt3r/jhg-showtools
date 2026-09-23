import AppKit
import SwiftUI
import ShowToolsCore

/// A level line with any number of points, for a video slide's own sound
/// (spec/video-audio.md). `LevelLine` is the level-plus-fades version, used
/// by songs and lane images; this is the one that can keep someone speaking
/// and drop the dogs barking.
///
/// Gestures follow Apple's, which are split across two of its apps:
/// **⌥-click the line to add a point** (Final Cut), **drag a point** to
/// move it in time and level, and **double-click a point to remove it**
/// (Logic). A plain drag on the line moves the whole curve up or down, and
/// on a silent clip — an empty curve — it sets one flat level, so turning
/// a clip's sound up stays a single drag.
///
/// Times are seconds from the start of the slide's own block, so the line
/// always spans what you can see, whatever the clip is trimmed to.
struct CurveLine: View {
    let curve: LevelCurve
    /// The block's length in seconds, and the timeline's points per second.
    let length: Double
    let pps: Double
    let width: CGFloat
    let height: CGFloat
    let colour: Color
    /// "Volume", for the readout and help.
    let name: String
    /// Called when an edit begins, to select the slide.
    let begin: () -> Void
    /// Called once, on release: one value, one undo step.
    let commit: (_ curve: LevelCurve, _ action: String) -> Void

    @State private var live: LevelCurve?
    @State private var start: LevelCurve?
    @State private var dragging: LevelPoint.ID?
    @State private var hovering = false

    /// Full level sits this far below the block's top, so the line stays in
    /// view. Matches `LevelLine`.
    private static let pad: CGFloat = 5
    private static let dot: CGFloat = 7
    /// How close to the line counts as on it.
    private static let grab: CGFloat = 9

    private var current: LevelCurve { live ?? curve }

    private func y(_ level: Double) -> CGFloat {
        Self.pad + CGFloat(1 - level) * (height - 2 * Self.pad)
    }
    private func level(atY y: CGFloat) -> Double {
        let span = height - 2 * Self.pad
        guard span > 0 else { return 0 }
        return round(min(max(1 - Double((y - Self.pad) / span), 0), 1) * 100) / 100
    }
    private func x(_ time: Double) -> CGFloat { CGFloat(time * pps) }
    private func time(atX x: CGFloat) -> Double {
        guard pps > 0 else { return 0 }
        return round(min(max(Double(x) / pps, 0), max(length, 0)) * 10) / 10
    }

    /// The drawn line: flat in from each edge to the outermost points.
    private var linePoints: [CGPoint] {
        let c = current
        guard !c.isEmpty else { return [CGPoint(x: 0, y: y(0)), CGPoint(x: width, y: y(0))] }
        var pts = [CGPoint(x: 0, y: y(c.level(at: 0)))]
        for p in c.points where x(p.time) > 0 && x(p.time) < width {
            pts.append(CGPoint(x: x(p.time), y: y(p.level)))
        }
        pts.append(CGPoint(x: width, y: y(c.level(at: length))))
        return pts
    }

    var body: some View {
        let pts = linePoints
        let c = current
        ZStack(alignment: .topLeading) {
            // Drawn twice: a dark outline under the line, then the line. A
            // video block is a strip of the film itself, and an orange line
            // on an orange frame is invisible without it (measured).
            let path = Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for q in pts.dropFirst() { p.addLine(to: q) }
            }
            let weight: CGFloat = live == nil ? 1.5 : 2
            path.stroke(.black.opacity(0.55),
                        style: StrokeStyle(lineWidth: weight + 2, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
            path.stroke(c.isEmpty ? colour.opacity(0.7) : colour,
                        style: StrokeStyle(lineWidth: weight, lineJoin: .round))
                .allowsHitTesting(false)

            // The line itself: ⌥-click to add a point, drag to move it all.
            Color.clear
                .contentShape(LineBand(points: pts, thickness: Self.grab))
                .onHover { inside in
                    hovering = inside
                    if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
                .onTapGesture { location in clickedLine(at: location) }
                .gesture(lineDrag)
                .help(c.isEmpty
                      ? "Silent. Drag up to turn it up, or ⌥-click to add a point."
                      : "\(name) \(percent(c.level(at: 0)))%. Drag to move it, ⌥-click to add a point.")

            ForEach(c.points) { point in
                dot(point)
            }

            if live != nil || hovering {
                readout(c)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func percent(_ l: Double) -> Int { Int((l * 100).rounded()) }

    /// Where a point's diamond is drawn, kept far enough from the block's
    /// edges to be whole.
    ///
    /// A point at the very start or end sits at x=0 or x=width, so half its
    /// diamond hung outside the block and over the gap to the next one.
    /// Only the handle moves: the line itself still runs to the true x, so
    /// nothing about the timing is redrawn, and because the line is flat
    /// between an edge and the outermost point, the nudged handle still sits
    /// exactly on it. Insetting the line instead would have shifted every
    /// point against the ruler by about half a diamond.
    private func dotX(_ time: Double) -> CGFloat {
        // A square turned 45° is √2 times as wide as its side, so half of
        // one is dot/√2, not dot/2 — plus the block's border.
        let margin = Self.dot / 2 * 1.414 + 1
        guard width > margin * 2 else { return x(time) }
        return min(max(x(time), margin), width - margin)
    }

    private func dot(_ point: LevelPoint) -> some View {
        // A diamond, as Final Cut draws a volume keyframe.
        Rectangle()
            .fill(colour)
            .rotationEffect(.degrees(45))
            .overlay(Rectangle().strokeBorder(.black.opacity(0.5), lineWidth: 0.5).rotationEffect(.degrees(45)))
            .frame(width: Self.dot, height: Self.dot)
            .padding(3)                                     // a bigger target than it looks
            .contentShape(Rectangle())
            .offset(x: dotX(point.time) - Self.dot / 2 - 3, y: y(point.level) - Self.dot / 2 - 3)
            .onHover { if $0 { NSCursor.openHand.set() } else { NSCursor.arrow.set() } }
            // Checked on the event rather than with a double-tap gesture,
            // which would hold every single click back while it waits for a
            // second (the same reason the storyline's blocks do it here).
            .onTapGesture {
                guard (NSApp.currentEvent?.clickCount ?? 1) >= 2 else { return }
                begin()
                commit(curve.removing(point.id), "Remove \(name) Point")
            }
            .gesture(pointDrag(point))
            .help("\(name) \(percent(point.level))% at \(formatSeconds(point.time)). Double-click to remove it.")
    }

    private func readout(_ c: LevelCurve) -> some View {
        let level = dragging.flatMap { id in c.points.first { $0.id == id }?.level } ?? c.level(at: 0)
        let atY = y(level)
        return Text("\(name) \(percent(level))%")
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.yellow, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.black)
            .fixedSize()
            .offset(x: 2, y: atY > height / 2 ? 1 : height - 14)
            .allowsHitTesting(false)
    }

    /// ⌥-click adds a point where the line already is, so clicking never
    /// moves the line (Final Cut). A plain click just selects the slide.
    private func clickedLine(at location: CGPoint) {
        begin()
        guard NSEvent.modifierFlags.contains(.option) else { return }
        let t = time(atX: location.x)
        commit(curve.isEmpty ? curve.adding(time: t, level: level(atY: location.y))
                             : curve.addingOnLine(at: t),
               "Add \(name) Point")
    }

    /// Dragging the line: on a silent clip it sets one flat level; otherwise
    /// it moves every point together, stopping when one reaches an end.
    private var lineDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                if start == nil { start = curve; begin() }
                guard let from = start else { return }
                if from.isEmpty {
                    let l = level(atY: g.location.y)
                    live = LevelCurve(points: [LevelPoint(time: 0, level: l),
                                               LevelPoint(time: max(length, 0), level: l)])
                    return
                }
                let span = height - 2 * Self.pad
                guard span > 0 else { return }
                var dl = -Double(g.translation.height) / Double(span)
                // Move as one: stop when the highest or lowest point lands.
                let levels = from.points.map(\.level)
                dl = min(dl, 1 - (levels.max() ?? 1))
                dl = max(dl, -(levels.min() ?? 0))
                live = LevelCurve(points: from.points.map {
                    var p = LevelPoint(time: $0.time, level: round(($0.level + dl) * 100) / 100)
                    p.id = $0.id
                    return p
                })
            }
            .onEnded { _ in finish(start?.isEmpty == true ? "Change \(name)" : "Move \(name) Line") }
    }

    /// Dragging a point moves it in time and level at once (Logic).
    private func pointDrag(_ point: LevelPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if start == nil { start = curve; begin() }
                dragging = point.id
                live = (start ?? curve).moving(point.id,
                                               toTime: time(atX: x(point.time) + g.translation.width),
                                               level: level(atY: y(point.level) + g.translation.height))
            }
            .onEnded { _ in finish("Move \(name) Point") }
    }

    private func finish(_ action: String) {
        defer { live = nil; start = nil; dragging = nil }
        guard let c = live, c != start else { return }
        commit(c, action)
    }
}

/// The band around a polyline that counts as being on it, so only the line
/// takes the mouse and the rest of the block still selects and drags.
private struct LineBand: Shape {
    let points: [CGPoint]
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        return p.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
    }
}
