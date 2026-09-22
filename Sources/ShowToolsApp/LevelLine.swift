import SwiftUI

/// The level line on a timeline clip (plan, Phase 3): volume on a song,
/// opacity on a lane image. The line sits at the clip's level; drag it up
/// or down to change it. A handle at each end of the flat part drags
/// inward to lengthen that fade, and the line ramps down to nothing over
/// it. Drawn live while dragging; saved once, on release.
struct LevelLine: View {
    let level: Double
    let fadeIn: Double
    let fadeOut: Double
    /// The clip's length in seconds, and the timeline's points per second.
    let length: Double
    let pps: Double
    let width: CGFloat
    let height: CGFloat
    let colour: Color
    /// "Volume" or "Opacity", for the readout and help.
    let name: String
    /// Called when a drag begins, to select the clip.
    let begin: () -> Void
    let commit: (_ level: Double, _ fadeIn: Double, _ fadeOut: Double) -> Void

    private struct Live: Equatable {
        var level: Double, fadeIn: Double, fadeOut: Double
    }
    @State private var live: Live?
    @State private var start: Live?
    @State private var hovering = false

    /// Full level sits this far below the clip's top, so the line stays in view.
    private static let pad: CGFloat = 5
    private static let handle: CGFloat = 7

    private var current: Live { live ?? Live(level: level, fadeIn: fadeIn, fadeOut: fadeOut) }
    private func y(_ l: Double) -> CGFloat { Self.pad + CGFloat(1 - l) * (height - 2 * Self.pad) }

    var body: some View {
        let c = current
        let inX = min(CGFloat(c.fadeIn * pps), width), outX = max(width - CGFloat(c.fadeOut * pps), inX)
        let lineY = y(c.level), floorY = y(0)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: floorY))
                p.addLine(to: CGPoint(x: inX, y: lineY))
                p.addLine(to: CGPoint(x: outX, y: lineY))
                p.addLine(to: CGPoint(x: width, y: floorY))
            }
            .stroke(colour, style: StrokeStyle(lineWidth: live == nil ? 1.5 : 2, lineJoin: .round))
            .allowsHitTesting(false)

            // The flat part: drag up or down.
            Color.clear
                .frame(width: max(outX - inX - Self.handle * 2, 4), height: 8)
                .contentShape(Rectangle())
                .offset(x: inX + Self.handle, y: lineY - 4)
                .onHover { inside in
                    hovering = inside
                    if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
                .gesture(levelDrag)
                .help("\(name) \(Int((c.level * 100).rounded()))%. Drag up or down to change it.")

            fadeHandle(x: inX, y: lineY, isIn: true)
            fadeHandle(x: outX, y: lineY, isIn: false)

            if live != nil || hovering {
                Text("\(name) \(Int((c.level * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.black)
                    .fixedSize()
                    .offset(x: max(inX + 4, 2), y: lineY > height / 2 ? 1 : height - 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func fadeHandle(x: CGFloat, y: CGFloat, isIn: Bool) -> some View {
        Circle()
            .fill(colour)
            .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 0.5))
            .frame(width: Self.handle, height: Self.handle)
            .padding(3)                                     // a bigger target than it looks
            .contentShape(Rectangle())
            .offset(x: x - Self.handle / 2 - 3 + (isIn ? 1 : -1) * 2, y: y - Self.handle / 2 - 3)
            .onHover { if $0 { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() } }
            .gesture(fadeDrag(isIn: isIn))
            .help(isIn ? "Fade in: drag right to lengthen it" : "Fade out: drag left to lengthen it")
    }

    private var levelDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if start == nil { start = current; begin() }
                guard var l = start else { return }
                let dl = -Double(g.translation.height) / Double(height - 2 * Self.pad)
                l.level = (min(max(l.level + dl, 0), 1) * 100).rounded() / 100
                live = l
            }
            .onEnded { _ in finish() }
    }

    private func fadeDrag(isIn: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if start == nil { start = current; begin() }
                guard var l = start else { return }
                let dt = Double(g.translation.width) / pps
                if isIn {
                    l.fadeIn = min(max(l.fadeIn + dt, 0), max(length - l.fadeOut, 0))
                    l.fadeIn = (l.fadeIn * 10).rounded() / 10
                } else {
                    l.fadeOut = min(max(l.fadeOut - dt, 0), max(length - l.fadeIn, 0))
                    l.fadeOut = (l.fadeOut * 10).rounded() / 10
                }
                live = l
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        defer { live = nil; start = nil }
        guard let l = live, l != start else { return }
        commit(l.level, l.fadeIn, l.fadeOut)
    }
}
