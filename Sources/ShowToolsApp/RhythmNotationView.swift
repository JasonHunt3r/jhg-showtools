import SwiftUI
import CoreText
import ShowToolsCore

/// A rhythm pattern drawn as notation (plan, Phase 3 step 7): one line, no
/// pitches, in Bravura (bundled; see make-app.sh). `RhythmNotation.layout`
/// says where everything goes, in staff spaces; this draws it. Sizes and
/// thicknesses are Bravura's engraving defaults (its metadata, Bravura.json).
/// Glyphs are drawn as their outlines, so they sit exactly on the line
/// (a Text is placed by the font's line box, which for a music font is huge).
struct RhythmNotationView: View {
    let pattern: RhythmPattern

    /// One staff space, in points. The font's em is four of them.
    static let space: CGFloat = 5.5
    /// Where the line is, from the top: room above for stems, beams and
    /// triplet marks, below for rests.
    static let lineY: CGFloat = space * 6
    static let height: CGFloat = space * 9

    var body: some View {
        let layout = RhythmNotation.layout(pattern)
        ScrollView(.horizontal, showsIndicators: false) {
            Canvas { ctx, _ in Self.draw(layout, in: &ctx) }
                .frame(width: max(CGFloat(layout.end + 3) * Self.space, 40), height: Self.height)
        }
        // Notes are added at the end, so that's the part to show.
        .defaultScrollAnchor(.trailing)
        .frame(height: Self.height)
        .accessibilityLabel("The pattern as notation")
    }

    // MARK: Drawing

    private static let font = CTFontCreateWithName("Bravura" as CFString, space * 4, nil)
    private static var glyphs: [UInt32: Path] = [:]

    /// A SMuFL glyph's outline, with its origin at (0, 0) and y down.
    private static func glyph(_ code: UInt32) -> Path {
        if let p = glyphs[code] { return p }
        var chars = Array(String(UnicodeScalar(code)!).utf16)
        var g = [CGGlyph](repeating: 0, count: chars.count)
        var path = Path()
        if CTFontGetGlyphsForCharacters(font, &chars, &g, chars.count), let cg = CTFontCreatePathForGlyph(font, g[0], nil) {
            path = Path(cg).applying(CGAffineTransform(scaleX: 1, y: -1))
        }
        glyphs[code] = path
        return path
    }

    /// Staff spaces (x from the left, y up from the line) to points.
    private static func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x) * space, y: lineY - CGFloat(y) * space)
    }

    private static func put(_ code: UInt32, _ x: Double, _ y: Double, in ctx: inout GraphicsContext) {
        let p = pt(x, y)
        ctx.fill(glyph(code).applying(CGAffineTransform(translationX: p.x, y: p.y)), with: .foreground)
    }

    /// A filled box between two corners, in staff spaces.
    private static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, in ctx: inout GraphicsContext) {
        let a = pt(min(x0, x1), max(y0, y1)), b = pt(max(x0, x1), min(y0, y1))
        ctx.fill(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)), with: .foreground)
    }

    // SMuFL code points.
    private static let noteheadWhole: UInt32 = 0xE0A2, noteheadHalf: UInt32 = 0xE0A3, noteheadBlack: UInt32 = 0xE0A4
    private static let flag8thUp: UInt32 = 0xE240, flag16thUp: UInt32 = 0xE242
    private static let dot: UInt32 = 0xE1E7, tuplet3: UInt32 = 0xE883
    private static func rest(_ v: RhythmPattern.Value) -> UInt32 {
        switch v {
        case .whole: 0xE4E3
        case .half: 0xE4E4
        case .quarter: 0xE4E5
        case .eighth: 0xE4E6
        case .sixteenth: 0xE4E7
        }
    }

    // Bravura's engraving defaults and anchors, in staff spaces.
    private static let stemThickness = 0.12, beamThickness = 0.5, beamSpacing = 0.25
    private static let lineThickness = 0.13, barThickness = 0.16, bracketThickness = 0.16
    private static let headWidth = 1.18, stemAttachY = 0.168, stemTop = 3.5

    private static func draw(_ l: RhythmNotation.Layout, in ctx: inout GraphicsContext) {
        guard !l.items.isEmpty else { return }
        // The line.
        box(0, -lineThickness / 2, l.end + 1.6, lineThickness / 2, in: &ctx)

        let beamed = Set(l.beams.flatMap { Array($0) })
        for (i, item) in l.items.enumerated() {
            let n = item.note, x = item.x
            if n.rest {
                put(rest(n.value), x, 0, in: &ctx)
                if n.dotted { put(dot, x + 1.6, 0.5, in: &ctx) }
                continue
            }
            switch n.value {
            case .whole:
                put(noteheadWhole, x, 0, in: &ctx)
            default:
                put(n.value == .half ? noteheadHalf : noteheadBlack, x, 0, in: &ctx)
                let sx = x + headWidth
                box(sx - stemThickness, stemAttachY, sx, stemTop, in: &ctx)
                if !beamed.contains(i) {
                    if n.value == .eighth { put(flag8thUp, sx - stemThickness, stemTop, in: &ctx) }
                    if n.value == .sixteenth { put(flag16thUp, sx - stemThickness, stemTop, in: &ctx) }
                }
            }
            if n.dotted { put(dot, x + (n.value == .whole ? 1.69 : headWidth) + 0.35, 0.5, in: &ctx) }
        }

        // Beams: flat, all notes being on the one line.
        for g in l.beams {
            let stem = { (i: Int) in l.items[i].x + headWidth }
            box(stem(g.lowerBound) - stemThickness, stemTop - beamThickness, stem(g.upperBound), stemTop, in: &ctx)
            // Sixteenths: a second beam joining neighbours, or a stub.
            let y1 = stemTop - beamThickness - beamSpacing, y0 = y1 - beamThickness
            let sixteenth = { (i: Int) in g.contains(i) && l.items[i].note.value == .sixteenth }
            for i in g where sixteenth(i) {
                if sixteenth(i + 1) {
                    box(stem(i) - stemThickness, y0, stem(i + 1), y1, in: &ctx)
                } else if !sixteenth(i - 1) {
                    // Alone: a stub pointing into the group.
                    let toward = i < g.upperBound ? 1.1 : -1.1
                    box(stem(i) - (toward > 0 ? stemThickness : 0), y0, stem(i) + toward, y1, in: &ctx)
                }
            }
        }

        // Triplets: a 3 over the notes, bracketed unless one beam holds them.
        for t in l.tuplets {
            let x0 = l.items[t.lowerBound].x, x1 = l.items[t.upperBound].x + headWidth
            let mid = (x0 + x1) / 2
            let bracketed = !l.beams.contains(t)
            let y = stemTop + 0.8
            put(tuplet3, mid - 0.6, y - 0.4, in: &ctx)
            if bracketed {
                let top = y + 0.35
                box(x0, top - bracketThickness, mid - 0.9, top, in: &ctx)
                box(mid + 0.9, top - bracketThickness, x1, top, in: &ctx)
                box(x0, top - 0.6, x0 + bracketThickness, top, in: &ctx)
                box(x1 - bracketThickness, top - 0.6, x1, top, in: &ctx)
            }
        }

        for b in l.barLines { box(b, -2, b + barThickness, 2, in: &ctx) }

        // The closing repeat: dots, a thin line and a thick one.
        let e = l.end
        put(dot, e, 0.5, in: &ctx)
        put(dot, e, -0.5, in: &ctx)
        box(e + 0.7, -2, e + 0.7 + barThickness, 2, in: &ctx)
        box(e + 1.1, -2, e + 1.6, 2, in: &ctx)
    }
}
