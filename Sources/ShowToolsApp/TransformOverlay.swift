import SwiftUI
import AppKit
import ShowToolsCore

/// Click the image in the Edit Show preview to select it; then its handles
/// and the keyboard edit that slide's Transform (plan, Phase 2a):
///
/// - drag the image to move it; drag a corner to scale (proportional,
///   anchored on the opposite corner; Option scales around the centre);
///   drag just outside a corner to rotate around the anchor (Shift snaps to
///   15°); drag the crosshair to move the anchor without moving the image
/// - arrows nudge 1 px, Shift 10 px; Option+←/→ rotate 1° (Shift 15°);
///   Option+↑/↓ zoom 1% (Shift 10%). A run of presses is one undo step
/// - Esc, a click on the background, or playing deselects
///
/// It covers the whole stage, not just the picture, so handles on an image
/// that hangs past the frame can still be seen and grabbed.
struct TransformOverlay: View {
    let engine: PlaybackEngine
    /// The picture's rect within this view.
    let frame: CGRect
    @Binding var imageSlideID: Int64?
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator

    /// The Transform being edited, drawn by the engine before it's saved.
    @State private var live: Transform?
    @State private var liveSlideID: Int64?
    @State private var drag: Drag?
    /// A run of key presses, committed a second after the last one.
    @State private var run: Task<Void, Never>?
    @State private var runAction = ""
    @FocusState private var focused: Bool

    private enum Zone: Equatable { case move, scale(corner: Int), rotate, anchor }

    private struct Drag {
        /// Nil: the click landed on the background.
        let zone: Zone?
        let start: Transform
        let geo: Geo
        /// Where the pointer went down; every step is measured from here,
        /// so a drag never drifts.
        let startPoint: CGPoint
        var moved = false
    }

    var body: some View {
        // Read so the handles follow seeks and edits.
        let _ = engine.seekCount
        let _ = engine.revision
        let geo = imageSlideID.flatMap { selectedGeo($0) }
        ZStack {
            if let geo, !engine.isPlaying { handles(geo) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): cursor(for: p).set()
            case .ended: NSCursor.arrow.set()
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key($0) }
        .onKeyPress(.escape) {
            guard imageSlideID != nil else { return .ignored }
            deselect()
            return .handled
        }
        .onChange(of: engine.isPlaying) { _, playing in if playing { deselect() } }
        .onChange(of: selection) { _, s in
            if let id = imageSlideID, s != [id] { deselect() }
        }
        .onDisappear {
            commitRun()
            engine.endLiveEdit()
        }
    }

    // MARK: Geometry

    /// Where one layer's image sits in this view, and the maths to change
    /// its Transform. View coordinates: y runs down, so a positive angle in
    /// the usual rotation matrix turns clockwise, as the Transform's does.
    struct Geo {
        let slideID: Int64
        let frame: CGRect
        let W: CGFloat, H: CGFloat
        /// Image pixels (Core Image, y up) → picture pixels (y up), for fit
        /// and Ken Burns only, and with the spin and Transform too.
        let base: CGAffineTransform
        let full: CGAffineTransform
        let transform: Transform

        func view(_ p: CGPoint) -> CGPoint { CGPoint(x: frame.minX + p.x, y: frame.minY + frame.height - p.y) }
        func picture(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x - frame.minX, y: frame.minY + frame.height - v.y) }
        func imageCI(_ p: ImagePoint) -> CGPoint { CGPoint(x: CGFloat(p.x) * W, y: CGFloat(1 - p.y) * H) }

        /// Top left, top right, bottom right, bottom left of the image.
        var corners: [CGPoint] {
            [CGPoint(x: 0, y: H), CGPoint(x: W, y: H), CGPoint(x: W, y: 0), .zero].map { view($0.applying(full)) }
        }
        var centre: CGPoint {
            let c = corners
            return CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4)
        }
        /// The offset in view points (right and down).
        var offset: CGPoint { CGPoint(x: transform.offsetX * frame.width, y: transform.offsetY * frame.height) }
        /// The anchor where fit and Ken Burns put it, before the Transform.
        var anchorBase: CGPoint { view(imageCI(transform.anchor).applying(base)) }
        /// Where the Transform turns around, on screen: the crosshair.
        var anchorOnScreen: CGPoint { anchorBase + offset }

        func contains(_ p: CGPoint) -> Bool {
            var path = Path()
            path.addLines(corners)
            path.closeSubpath()
            return path.contains(p)
        }

        func imagePoint(atView v: CGPoint) -> ImagePoint {
            let ci = picture(v).applying(base.inverted())
            return ImagePoint(x: Double(ci.x / W), y: Double(1 - ci.y / H))
        }
    }

    private func geo(_ layer: Layer) -> Geo? {
        let W = CGFloat(layer.slide.item.pixelWidth), H = CGFloat(layer.slide.item.pixelHeight)
        guard W > 0, H > 0, frame.width > 0, frame.height > 0 else { return nil }
        let e = CGRect(x: 0, y: 0, width: W, height: H)
        let spin = layer.slide.rotation == nil ? nil : (angle: layer.rotationAngle, pivot: layer.rotationPivot)
        guard let base = Compositor.placement(imageExtent: e, fit: layer.slide.fit, kb: layer.kenBurnsFrame,
                                              transform: .identity, spin: nil, outputSize: frame.size),
              let full = Compositor.placement(imageExtent: e, fit: layer.slide.fit, kb: layer.kenBurnsFrame,
                                              transform: layer.slide.transform, spin: spin, outputSize: frame.size)
        else { return nil }
        return Geo(slideID: layer.slide.slide.id, frame: frame, W: W, H: H, base: base, full: full,
                   transform: layer.slide.transform)
    }

    private var layersNow: [Layer] { engine.timeline.frame(at: engine.now).layers }

    /// The selected slide, if it's on screen now. The engine's timeline
    /// already carries a live edit, so this follows a drag as it happens.
    private func selectedGeo(_ id: Int64) -> Geo? {
        layersNow.last(where: { $0.slide.slide.id == id }).flatMap(geo)
    }

    private func zone(_ g: Geo, at p: CGPoint) -> Zone? {
        func near(_ a: CGPoint, _ r: CGFloat) -> Bool { hypot(a.x - p.x, a.y - p.y) <= r }
        if near(g.anchorOnScreen, 8) { return .anchor }
        let c = g.corners
        if let i = c.indices.first(where: { near(c[$0], 8) }) { return .scale(corner: i) }
        if !g.contains(p), c.contains(where: { near($0, 28) }) { return .rotate }
        return g.contains(p) ? .move : nil
    }

    // MARK: Mouse

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if drag == nil { begin(at: g.startLocation) }
                guard var d = drag, d.zone != nil else { return }
                if !d.moved {
                    guard hypot(g.translation.width, g.translation.height) >= 2 else { return }
                    d.moved = true
                    drag = d
                }
                setLive(apply(d, to: g.location, modifiers: NSEvent.modifierFlags), slideID: d.geo.slideID)
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let d = drag else { return }
                guard let zone = d.zone else { deselect(); return }
                if d.moved, let t = live { commit(t, slideID: d.geo.slideID, action: actionName(zone)) }
            }
    }

    private func begin(at p: CGPoint) {
        commitRun()
        if engine.isPlaying { engine.pause() }
        if let id = imageSlideID, let g = selectedGeo(id), let z = zone(g, at: p) {
            drag = Drag(zone: z, start: g.transform, geo: g, startPoint: p)
            return
        }
        // Not on the selected image's handles: select the image under the
        // click (the top one mid-transition), and let the same drag move it.
        if let g = layersNow.reversed().compactMap(geo).first(where: { $0.contains(p) }) {
            select(g.slideID)
            drag = Drag(zone: .move, start: g.transform, geo: g, startPoint: p)
        } else {
            drag = Drag(zone: nil, start: .identity,
                        geo: Geo(slideID: 0, frame: frame, W: 1, H: 1, base: .identity, full: .identity,
                                 transform: .identity),
                        startPoint: p)
        }
    }

    /// The maths is `TransformEdit`'s, in the core, where tests check that
    /// scaling keeps the fixed corner put and moving the anchor leaves the
    /// image where it was.
    private func apply(_ d: Drag, to p: CGPoint, modifiers: NSEvent.ModifierFlags) -> Transform {
        let g = d.geo
        var t = d.start
        let size = g.frame.size
        switch d.zone {
        case .move?:
            t = TransformEdit.withOffset(t, g.offset + (p - d.startPoint), size: size)
        case .scale(let i)?:
            let fixed = modifiers.contains(.option) ? g.centre : g.corners[(i + 2) % 4]
            let diag = g.corners[i] - fixed
            let len2 = diag.dot(diag)
            guard len2 > 0 else { return t }
            // How far along the diagonal the pointer is, as a multiple of it.
            let k = max(Double((p - fixed).dot(diag) / len2), 0.01 / max(d.start.scale, 0.01))
            t = TransformEdit.scaled(t, by: k, about: fixed, anchor: g.anchorBase, size: size)
        case .rotate?:
            let a = g.anchorOnScreen, s = d.startPoint
            let turn = Double(atan2(p.y - a.y, p.x - a.x) - atan2(s.y - a.y, s.x - a.x)) * 180 / .pi
            var r = d.start.rotation + turn
            if modifiers.contains(.shift) { r = (r / 15).rounded() * 15 }
            t.rotation = r
        case .anchor?:
            let (moved, B) = TransformEdit.movingAnchor(t, to: p, anchor: g.anchorBase, size: size)
            t = moved
            t.anchor = g.imagePoint(atView: B)
        case nil:
            break
        }
        return t
    }

    private func actionName(_ z: Zone) -> String {
        switch z {
        case .move: "Move Image"
        case .scale: "Scale Image"
        case .rotate: "Rotate Image"
        case .anchor: "Move Anchor"
        }
    }

    private func cursor(for p: CGPoint) -> NSCursor {
        guard let id = imageSlideID, !engine.isPlaying, let g = selectedGeo(id) else { return .arrow }
        switch zone(g, at: p) {
        case .move?: return drag == nil ? .openHand : .closedHand
        case .scale?: return .crosshair
        case .rotate?: return Self.rotateCursor
        case .anchor?: return .pointingHand
        case nil: return .arrow
        }
    }

    /// macOS has no rotate cursor, so one is drawn: an SF Symbol with a
    /// white halo so it reads on any picture.
    static let rotateCursor: NSCursor = {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            guard let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Rotate")?
                .withSymbolConfiguration(config) else { return false }
            let r = NSRect(x: (rect.width - symbol.size.width) / 2, y: (rect.height - symbol.size.height) / 2,
                           width: symbol.size.width, height: symbol.size.height)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] as [(CGFloat, CGFloat)] {
                tinted(symbol, .white).draw(in: r.offsetBy(dx: dx, dy: dy))
            }
            tinted(symbol, .black).draw(in: r)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 11, y: 11))
    }()

    private static func tinted(_ image: NSImage, _ colour: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Keys

    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard let id = imageSlideID, !engine.isPlaying, let g = selectedGeo(id) else { return .ignored }
        var t = g.transform
        let big = press.modifiers.contains(.shift)
        let turn: Double = big ? 15 : 1
        let zoom: Double = big ? 0.10 : 0.01
        // One pixel of the full-screen frame on the main display.
        let screen = NSScreen.main.map { ($0.frame.width * $0.backingScaleFactor, $0.frame.height * $0.backingScaleFactor) }
            ?? (1920, 1080)
        let px = Double(big ? 10 : 1)
        let action: String
        if press.modifiers.contains(.option) {
            switch press.key {
            case .leftArrow: t.rotation -= turn; action = "Rotate Image"
            case .rightArrow: t.rotation += turn; action = "Rotate Image"
            case .upArrow: t.scale += zoom; action = "Zoom Image"
            case .downArrow: t.scale = max(t.scale - zoom, 0.01); action = "Zoom Image"
            default: return .ignored
            }
        } else {
            switch press.key {
            case .leftArrow: t.offsetX -= px / screen.0
            case .rightArrow: t.offsetX += px / screen.0
            case .upArrow: t.offsetY -= px / screen.1
            case .downArrow: t.offsetY += px / screen.1
            default: return .ignored
            }
            action = "Nudge Image"
        }
        setLive(t, slideID: id)
        if run == nil { runAction = action }
        run?.cancel()
        run = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            commitRun()
        }
        return .handled
    }

    private func commitRun() {
        run?.cancel()
        run = nil
        if let t = live, let id = liveSlideID, drag == nil { commit(t, slideID: id, action: runAction) }
    }

    // MARK: Selecting and saving

    private func select(_ id: Int64) {
        imageSlideID = id
        selection = [id]
        focused = true
    }

    private func deselect() {
        commitRun()
        imageSlideID = nil
        focused = false
        NSCursor.arrow.set()
    }

    private func setLive(_ t: Transform, slideID: Int64) {
        live = t
        liveSlideID = slideID
        var s = engine.show
        guard let i = s.slides.firstIndex(where: { $0.id == slideID }) else { return }
        s.slides[i].settings.transform = t == .identity ? nil : t
        engine.showLiveEdit(s)
    }

    private func commit(_ t: Transform, slideID: Int64, action: String) {
        controlLog.notice("\(action, privacy: .public) slide \(slideID): offset \(t.offsetX), \(t.offsetY) scale \(t.scale) rotation \(t.rotation)")
        mutate(action) { s in
            guard let i = s.slides.firstIndex(where: { $0.id == slideID }) else { return }
            s.slides[i].settings.transform = t == .identity ? nil : t
        }
        live = nil
        liveSlideID = nil
        engine.endLiveEdit()
    }

    // MARK: Drawing

    private func handles(_ g: Geo) -> some View {
        Canvas { ctx, _ in
            func outlined(_ path: Path) {
                ctx.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 3)
                ctx.stroke(path, with: .color(.white), lineWidth: 1)
            }
            var quad = Path()
            quad.addLines(g.corners)
            quad.closeSubpath()
            outlined(quad)
            for c in g.corners {
                let r = Path(CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
                ctx.fill(r, with: .color(.white))
                ctx.stroke(r, with: .color(.black.opacity(0.7)), lineWidth: 1)
            }
            let a = g.anchorOnScreen
            var cross = Path()
            cross.addEllipse(in: CGRect(x: a.x - 5, y: a.y - 5, width: 10, height: 10))
            cross.move(to: CGPoint(x: a.x - 10, y: a.y)); cross.addLine(to: CGPoint(x: a.x + 10, y: a.y))
            cross.move(to: CGPoint(x: a.x, y: a.y - 10)); cross.addLine(to: CGPoint(x: a.x, y: a.y + 10))
            outlined(cross)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Point maths

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private extension CGPoint {
    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
}
