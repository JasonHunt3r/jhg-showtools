import SwiftUI
import ShowToolsCore

/// The Rhythm tool's drum-machine view (plan, Phase 3 step 7): one row of
/// squares per bar, a lit square where a slide changes. It's its own input:
/// clicking a square rewrites the pattern (the gaps become note values), so
/// the letters it writes may be spelled differently from the ones typed,
/// for the same changes.
struct RhythmGridView: View {
    @Binding var text: String
    /// Straight or triplet, for a pattern that fits both (an empty one).
    @AppStorage("rhythmGridFeel") private var feelPref: RhythmGrid.Feel = .straight
    @State private var note: String?

    private var pattern: RhythmPattern { RhythmPattern(text: text) }

    private var grid: RhythmGrid? {
        let p = pattern
        if p.notes.isEmpty { return .empty(feelPref) }
        return RhythmGrid(p, feel: feelPref) ?? RhythmGrid.fitting(p)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let g = grid {
                rows(g)
                controls(g)
                if let note { Text(note).font(.callout).foregroundStyle(.orange) }
            } else {
                Text("This pattern mixes straight and triplet notes, so it has no grid. Edit it in Notes.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rows(_ g: RhythmGrid) -> some View {
        let per = g.feel.rawValue
        let size: CGFloat = g.feel == .straight ? 17 : 23
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<g.bars, id: \.self) { bar in
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { beat in
                        HStack(spacing: 2) {
                            ForEach(0..<per, id: \.self) { k in
                                let i = bar * g.stepsPerBar + beat * per + k
                                if i < g.cells.count { square(g, i, size: size, onBeat: k == 0) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func square(_ g: RhythmGrid, _ i: Int, size: CGFloat, onBeat: Bool) -> some View {
        let lit = g.cells[i]
        return RoundedRectangle(cornerRadius: 3)
            .fill(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(onBeat ? .tertiary : .quaternary))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .onTapGesture {
                var next = g
                next.cells[i].toggle()
                set(next)
            }
            .accessibilityElement()
            .accessibilityLabel("Bar \(i / g.stepsPerBar + 1), step \(i % g.stepsPerBar + 1)")
            .accessibilityValue(lit ? "on" : "off")
            .accessibilityAddTraits(.isButton)
    }

    private func controls(_ g: RhythmGrid) -> some View {
        HStack {
            Picker("", selection: Binding(get: { g.feel }, set: { setFeel($0, g) })) {
                Text("Straight").tag(RhythmGrid.Feel.straight)
                Text("Triplet").tag(RhythmGrid.Feel.triplet)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .help("Straight: 16 steps a bar (sixteenths). Triplet: 12 (triplet eighths).")
            Spacer()
            Stepper(value: Binding(get: { g.bars }, set: { set(g.resized(bars: $0)) }), in: 1...8) {
                Text("\(g.bars) bar\(g.bars == 1 ? "" : "s")").monospacedDigit()
            }
        }
    }

    private func set(_ g: RhythmGrid) {
        note = nil
        feelPref = g.feel
        text = g.pattern.text
    }

    private func setFeel(_ f: RhythmGrid.Feel, _ g: RhythmGrid) {
        if let c = g.converted(to: f) {
            set(c)
        } else {
            note = "Some squares fall between the \(f == .triplet ? "triplet" : "straight") steps. Clear them first."
        }
    }
}
