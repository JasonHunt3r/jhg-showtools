import SwiftUI
import OSLog
import ShowToolsCore
import ShowToolsPlayback

/// Every commit from these controls is logged, so a value that changes
/// unexpectedly can be traced to the control that wrote it:
///   log show --last 1h --predicate 'subsystem == "com.jhg.showtools"'
/// (Added 2026-09-21 after a change in testing that turned out to be Jason
/// trying the app; kept because it answers "what wrote this?" at once.)
let controlLog = Logger(subsystem: "com.jhg.showtools", category: "inspector")

/// A slider plus a number field. The slider commits once, on release, so a
/// drag is one undo step (the repo rule for drags); the field commits on ↩.
struct CommitSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    /// Shown value = stored value × `display` (100 shows fractions as %).
    var display: Double = 1
    var unit: String = ""
    /// The field can go past the slider's ends (two full turns, say).
    var fieldRange: ClosedRange<Double>? = nil
    let commit: (Double) -> Void
    /// Shows the value in the preview while the knob is moving, without
    /// saving it. The drag still commits once, on release, so it stays one
    /// undo step — this only draws. Left out where there's nothing to
    /// preview (Edit Slides has no preview canvas).
    var preview: ((Double) -> Void)? = nil

    @State private var dragging: Double?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(value: Binding(get: { min(max(dragging ?? value, range.lowerBound), range.upperBound) },
                                      set: { dragging = $0; preview?($0) }),
                       in: range) { editing in
                    if !editing, let d = dragging {
                        dragging = nil
                        send(d, from: "slider")
                    }
                }
                // The inspector column is narrow; without this the fields
                // take the width and the slider shrinks to its knob.
                .frame(minWidth: 90)
                .layoutPriority(1)
                TextField("", value: Binding(get: { (dragging ?? value) * display }, set: { v in
                    let r = fieldRange ?? range
                    send(min(max(v / display, r.lowerBound), r.upperBound), from: "field")
                }), format: .number.precision(.fractionLength(0...1)))
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
            }
        }
    }

    /// Skips a commit that changes nothing: it would still be a save and an
    /// undo step.
    private func send(_ new: Double, from source: String) {
        guard new != value else { return }
        controlLog.notice("\(title, privacy: .public) \(source, privacy: .public): \(value) → \(new)")
        commit(new)
    }
}

/// A compact 0…1 slider for the controls over the picture: a label, the
/// slider and a percentage, saving once on release like `CommitSlider`.
struct BarSlider: View {
    let title: String
    let value: Double
    let commit: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            Slider(value: Binding(get: { dragging ?? value }, set: { dragging = $0 }), in: 0...1) { editing in
                if !editing, let d = dragging {
                    dragging = nil
                    if d != value {
                        controlLog.notice("\(title, privacy: .public) bar: \(value) → \(d)")
                        commit(d)
                    }
                }
            }
            .controlSize(.small)
            .frame(width: 90)
            Text("\(Int(((dragging ?? value) * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// The centre-zero acceleration slider: left slows the move down, right
/// speeds it up, 0 is constant speed.
struct AccelerationSlider: View {
    let value: Double
    let commit: (Double) -> Void
    var preview: ((Double) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommitSlider(title: "Acceleration", value: value, range: -1...1, display: 100, unit: "%",
                         commit: commit, preview: preview)
            HStack {
                Text("◀ slows down")
                Spacer()
                Button("0") { commit(0) }.buttonStyle(.link).help("Constant speed")
                Spacer()
                Text("speeds up ▶")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// The polar pivot pad: the image's centre is the origin, and dragging pushes
/// the point out from it. The image's outline is drawn to scale, so you can
/// see when the point leaves the image (it's allowed to). The pad reaches one
/// long side of the image out from the centre in every direction.
struct PolarPad: View {
    let title: String
    /// Absolute, in the image's 0…1 terms; 0.5, 0.5 is the centre.
    let point: ImagePoint
    let imageSize: CGSize
    let commit: (ImagePoint) -> Void

    @State private var dragging: ImagePoint?
    private let side: CGFloat = 104

    private var W: CGFloat { max(imageSize.width, 1) }
    private var H: CGFloat { max(imageSize.height, 1) }
    /// Pad points per image pixel.
    private var unit: CGFloat { side / 2 / max(W, H) }
    private var mid: CGPoint { CGPoint(x: side / 2, y: side / 2) }

    private func toPad(_ q: ImagePoint) -> CGPoint {
        CGPoint(x: mid.x + CGFloat(q.x - 0.5) * W * unit, y: mid.y + CGFloat(q.y - 0.5) * H * unit)
    }

    private func fromPad(_ v: CGPoint) -> ImagePoint {
        let x = min(max(v.x, 0), side), y = min(max(v.y, 0), side)
        return ImagePoint(x: 0.5 + Double((x - mid.x) / unit / W), y: 0.5 + Double((y - mid.y) / unit / H))
    }

    var body: some View {
        let p = dragging ?? point
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Canvas { ctx, _ in
                let faint = GraphicsContext.Shading.color(.secondary.opacity(0.25))
                for r in stride(from: 0.25, through: 1.0, by: 0.25) {
                    let d = side * r
                    ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - d / 2, y: mid.y - d / 2, width: d, height: d)), with: faint)
                }
                var axes = Path()
                axes.move(to: CGPoint(x: mid.x, y: 0)); axes.addLine(to: CGPoint(x: mid.x, y: side))
                axes.move(to: CGPoint(x: 0, y: mid.y)); axes.addLine(to: CGPoint(x: side, y: mid.y))
                ctx.stroke(axes, with: faint)
                let outline = CGRect(x: mid.x - W * unit / 2, y: mid.y - H * unit / 2, width: W * unit, height: H * unit)
                ctx.stroke(Path(outline), with: .color(.secondary), lineWidth: 1)

                let q = toPad(p)
                var arm = Path()
                arm.move(to: mid); arm.addLine(to: q)
                ctx.stroke(arm, with: .color(.accentColor), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(.accentColor))
            }
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragging = fromPad($0.location) }
                .onEnded { _ in
                    if let d = dragging {
                        dragging = nil
                        guard d != point else { return }
                        controlLog.notice("\(title, privacy: .public) pad: (\(point.x), \(point.y)) → (\(d.x), \(d.y))")
                        commit(d)
                    }
                })
            HStack(spacing: 6) {
                Text(readout(p)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Centre") { commit(.centre) }
                    .buttonStyle(.link).font(.caption)
                    .disabled(p == .centre)
            }
        }
    }

    /// Distance as a share of the image's long side, and the direction as a
    /// compass bearing (0° up, clockwise).
    private func readout(_ q: ImagePoint) -> String {
        let dx = CGFloat(q.x - 0.5) * W, dy = CGFloat(q.y - 0.5) * H
        let dist = (dx * dx + dy * dy).squareRoot() / max(W, H)
        guard dist > 0.0005 else { return "centre" }
        var bearing = atan2(dx, -dy) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return "\(Int((dist * 100).rounded()))% · \(Int(bearing.rounded()))°"
    }
}

/// A colour well that commits once the colour stops changing: the colour
/// panel reports every step of a drag, and each would otherwise be a save
/// and an undo step.
struct SettledColorPicker: View {
    let title: String
    let colour: SRGBColor
    let commit: (SRGBColor) -> Void

    @State private var pending: SRGBColor?
    @State private var settle: Task<Void, Never>?

    var body: some View {
        ColorPicker(title, selection: Binding(get: { cgColor(pending ?? colour) }, set: { c in
            let rgb = srgbColor(c)
            pending = rgb
            settle?.cancel()
            settle = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                pending = nil
                guard rgb != colour else { return }
                controlLog.notice("\(title, privacy: .public) colour → \(rgb.red) \(rgb.green) \(rgb.blue)")
                commit(rgb)
            }
        }), supportsOpacity: false)
    }

    private func cgColor(_ c: SRGBColor) -> CGColor {
        CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private func srgbColor(_ c: CGColor) -> SRGBColor {
        let s = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let k = s?.components ?? [0, 0, 0]
        return k.count >= 3 ? SRGBColor(red: k[0], green: k[1], blue: k[2])
                            : SRGBColor(red: k[0], green: k[0], blue: k[0])
    }
}
