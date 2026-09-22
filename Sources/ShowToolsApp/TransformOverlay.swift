import SwiftUI
import AppKit
import ShowToolsCore
import ShowToolsPlayback

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
    /// What the handles edit: the still placement, or the Rotation effect
    /// (only offered when the slide has Rotation on).
    enum Target: Hashable { case transform, rotation }

    let engine: PlaybackEngine
    /// The picture's rect within this view.
    let frame: CGRect
    var target: Target = .transform
    @Binding var imageSlideID: Int64?
    /// An image from the lane's images row, selected instead of a slide.
    @Binding var selectedOverlay: UUID?
    @Binding var selection: Set<Int64>
    let mutate: ShowMutator

    /// The Transform being edited, drawn by the engine before it's saved.
    @State private var live: Transform?
    @State private var liveSubject: Subject?
    @State private var drag: Drag?
    /// Rotation mode's drag and the Rotation it's drawing live.
    @State private var rotDrag: RotDrag?
    @State private var liveRotation: Rotation?
    /// A run of key presses, committed a second after the last one.
    @State private var run: Task<Void, Never>?
    @State private var runAction = ""
    @FocusState private var focused: Bool

    private enum Zone: Equatable { case move, scale(corner: Int), rotate, anchor }

    /// What the Transform handles and keys edit: a slide's image, or an
    /// image from the lane (which has no Ken Burns or spin, but is placed
    /// by the same fit and Transform).
    enum Subject: Equatable {
        case slide(Int64)
        case overlay(UUID)
    }

    private var subject: Subject? {
        if let o = selectedOverlay { return .overlay(o) }
        return imageSlideID.map { .slide($0) }
    }

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
        let rot = target == .rotation ? imageSlideID.flatMap { rotationGeo($0) } : nil
        let geo = rot == nil ? subject.flatMap { selectedGeo($0) } : nil
        ZStack {
            if !engine.isPlaying {
                if let rot { rotationHandles(rot) } else if let geo { handles(geo) }
            }
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
            guard subject != nil else { return .ignored }
            deselect()
            return .handled
        }
        .onChange(of: engine.isPlaying) { _, playing in if playing { deselect() } }
        .onChange(of: selection) { _, s in
            if let id = imageSlideID, s != [id] { deselect() }
            if selectedOverlay != nil, !s.isEmpty { deselect() }
        }
        .onDisappear {
            // A drag cut short by the view going away keeps what it did.
            if let d = drag, d.moved, let zone = d.zone, let t = live {
                commit(t, subject: d.geo.subject, action: actionName(zone))
            }
            drag = nil
            if let r = rotDrag, r.moved, let new = liveRotation {
                commitRotation(new, slideID: r.geo.slideID, action: rotationActionName(r.zone, r.start))
            }
            rotDrag = nil
            commitRun()
            engine.endLiveEdit()
        }
    }

    // MARK: Geometry

    /// Where one layer's image sits in this view, and the maths to change
    /// its Transform. View coordinates: y runs down, so a positive angle in
    /// the usual rotation matrix turns clockwise, as the Transform's does.
    struct Geo {
        let subject: Subject
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
        guard let base = Compositor.placement(imageExtent: e, fit: layer.slide.fit, kb: layer.kenBurnsFrame,
                                              transform: .identity, spin: nil, outputSize: frame.size),
              let full = Compositor.placement(for: layer, imageExtent: e, outputSize: frame.size)
        else { return nil }
        return Geo(subject: .slide(layer.slide.slide.id), frame: frame, W: W, H: H, base: base, full: full,
                   transform: layer.slide.transform)
    }

    /// The lane's image showing now, placed like a slide with no motion.
    private func geo(_ o: OverlayLayer) -> Geo? {
        let W = CGFloat(o.overlay.item.pixelWidth), H = CGFloat(o.overlay.item.pixelHeight)
        guard W > 0, H > 0, frame.width > 0, frame.height > 0 else { return nil }
        let e = CGRect(x: 0, y: 0, width: W, height: H), c = o.overlay.clip
        guard let base = Compositor.placement(imageExtent: e, fit: c.fit, kb: .centred, transform: .identity,
                                              spin: nil, outputSize: frame.size),
              let full = Compositor.placement(imageExtent: e, fit: c.fit, kb: .centred, transform: c.transform,
                                              spin: nil, outputSize: frame.size)
        else { return nil }
        return Geo(subject: .overlay(c.id), frame: frame, W: W, H: H, base: base, full: full, transform: c.transform)
    }

    private var overlayNow: OverlayLayer? { engine.timeline.overlay(at: engine.now) }

    private var layersNow: [Layer] { engine.timeline.frame(at: engine.now).layers }

    /// The selected slide, if it's on screen now. The engine's timeline
    /// already carries a live edit, so this follows a drag as it happens.
    private func selectedGeo(_ subject: Subject) -> Geo? {
        switch subject {
        case .slide(let id): layersNow.last(where: { $0.slide.slide.id == id }).flatMap(geo)
        case .overlay(let id): overlayNow.flatMap { $0.overlay.clip.id == id ? geo($0) : nil }
        }
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
                if drag == nil, rotDrag == nil { begin(at: g.startLocation) }
                if var r = rotDrag {
                    if !r.moved {
                        guard hypot(g.translation.width, g.translation.height) >= 2 else { return }
                        r.moved = true
                    }
                    let new = applyRotation(&r, to: g.location, modifiers: NSEvent.modifierFlags)
                    rotDrag = r
                    setLiveRotation(new, slideID: r.geo.slideID)
                    return
                }
                guard var d = drag, d.zone != nil else { return }
                if !d.moved {
                    guard hypot(g.translation.width, g.translation.height) >= 2 else { return }
                    d.moved = true
                    drag = d
                }
                setLive(apply(d, to: g.location, modifiers: NSEvent.modifierFlags), subject: d.geo.subject)
            }
            .onEnded { _ in
                if let r = rotDrag {
                    rotDrag = nil
                    if r.moved, let new = liveRotation {
                        commitRotation(new, slideID: r.geo.slideID, action: rotationActionName(r.zone, r.start))
                    }
                    return
                }
                defer { drag = nil }
                guard let d = drag else { return }
                guard let zone = d.zone else { deselect(); return }
                if d.moved, let t = live { commit(t, subject: d.geo.subject, action: actionName(zone)) }
            }
    }

    private func begin(at p: CGPoint) {
        commitRun()
        if engine.isPlaying { engine.pause() }
        if target == .rotation, let id = imageSlideID, let g = rotationGeo(id), let z = rotationZone(g, at: p) {
            let pivot = g.ends[z.end].pivot
            rotDrag = RotDrag(zone: z, start: g.rotation, geo: g,
                              lastAtan: atan2(p.y - pivot.y, p.x - pivot.x))
            return
        }
        // In Rotation mode the Transform's corner and anchor handles aren't
        // drawn, so only a drag on the image itself (a move) reaches them.
        if let sub = subject, let g = selectedGeo(sub), let z = zone(g, at: p),
           target == .transform || z == .move {
            drag = Drag(zone: z, start: g.transform, geo: g, startPoint: p)
            return
        }
        // Not on the selected image's handles: select the image under the
        // click (the top one mid-transition), and let the same drag move it.
        // The lane's image is drawn on top, so it's found first.
        let candidates = [overlayNow.flatMap(geo)].compactMap { $0 } + layersNow.reversed().compactMap(geo)
        if let g = candidates.first(where: { $0.contains(p) }) {
            select(g.subject)
            drag = Drag(zone: .move, start: g.transform, geo: g, startPoint: p)
        } else {
            drag = Drag(zone: nil, start: .identity,
                        geo: Geo(subject: .slide(0), frame: frame, W: 1, H: 1, base: .identity, full: .identity,
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
        if target == .rotation, let id = imageSlideID, !engine.isPlaying, let g = rotationGeo(id) {
            switch rotationZone(g, at: p) {
            case .angle?: return Self.rotateCursor
            case .pivot?: return .pointingHand
            case nil: break
            }
        }
        guard let sub = subject, !engine.isPlaying, let g = selectedGeo(sub) else { return .arrow }
        if target == .rotation { return g.contains(p) ? (drag == nil ? .openHand : .closedHand) : .arrow }
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
        // Keys edit the Transform only; Rotation is set with its arms.
        guard target == .transform, let sub = subject, !engine.isPlaying,
              let g = selectedGeo(sub) else { return .ignored }
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
        setLive(t, subject: sub)
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
        if let t = live, let sub = liveSubject, drag == nil { commit(t, subject: sub, action: runAction) }
    }

    // MARK: Selecting and saving

    private func select(_ subject: Subject) {
        switch subject {
        case .slide(let id):
            selectedOverlay = nil
            imageSlideID = id
            selection = [id]
        case .overlay(let id):
            imageSlideID = nil
            selection = []
            selectedOverlay = id
        }
        focused = true
    }

    private func deselect() {
        commitRun()
        imageSlideID = nil
        selectedOverlay = nil
        focused = false
        NSCursor.arrow.set()
    }

    private func setLive(_ t: Transform, subject: Subject) {
        live = t
        liveSubject = subject
        var s = engine.show
        guard Self.write(t, to: subject, in: &s) else { return }
        engine.showLiveEdit(s)
    }

    /// Puts a Transform on its slide or lane image. False if it's gone.
    @discardableResult
    private static func write(_ t: Transform, to subject: Subject, in s: inout Show) -> Bool {
        switch subject {
        case .slide(let id):
            guard let i = s.slides.firstIndex(where: { $0.id == id }) else { return false }
            s.slides[i].settings.transform = t == .identity ? nil : t
        case .overlay(let id):
            guard let i = s.overlays.firstIndex(where: { $0.id == id }) else { return false }
            s.overlays[i].transform = t
        }
        return true
    }

    private func commit(_ t: Transform, subject: Subject, action: String) {
        controlLog.notice("\(action, privacy: .public) \(String(describing: subject), privacy: .public): offset \(t.offsetX), \(t.offsetY) scale \(t.scale) rotation \(t.rotation)")
        mutate(action) { s in Self.write(t, to: subject, in: &s) }
        live = nil
        liveSubject = nil
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

// MARK: - Rotation mode

extension TransformOverlay {
    /// One end of the Rotation effect, as it would sit on screen.
    struct RotEnd {
        /// The image's outline at this end's angle.
        let quad: [CGPoint]
        let pivot: CGPoint
        /// The arm's knob: out from the pivot along the image's "up".
        let knob: CGPoint
        /// Image pixels → picture pixels without the spin, which leaves the
        /// pivot where it is: inverted, it turns a pointer into an image point.
        let still: CGAffineTransform
    }

    struct RotGeo {
        let slideID: Int64
        let rotation: Rotation
        /// Seconds the rotation turns for (Speed mode's end depends on it).
        let span: Double
        /// Start, then end.
        let ends: [RotEnd]
        let W: CGFloat, H: CGFloat
        let frame: CGRect

        func imagePoint(atView v: CGPoint, end: Int) -> ImagePoint {
            let picture = CGPoint(x: v.x - frame.minX, y: frame.minY + frame.height - v.y)
            let ci = picture.applying(ends[end].still.inverted())
            return ImagePoint(x: Double(ci.x / W), y: Double(1 - ci.y / H))
        }
    }

    enum RotZone: Equatable {
        case angle(end: Int), pivot(end: Int)
        var end: Int { switch self { case .angle(let e), .pivot(let e): e } }
    }

    struct RotDrag {
        let zone: RotZone
        let start: Rotation
        let geo: RotGeo
        /// The pointer's angle round the pivot last time, and the whole turn
        /// so far: summed step by step, so dragging round twice is 720°.
        var lastAtan: CGFloat
        var turned: CGFloat = 0
        var moved = false
    }

    func rotationGeo(_ id: Int64) -> RotGeo? {
        guard let r = engine.timeline.slides.first(where: { $0.slide.id == id }), let rot = r.rotation else { return nil }
        let W = CGFloat(r.item.pixelWidth), H = CGFloat(r.item.pixelHeight)
        guard W > 0, H > 0, frame.width > 0, frame.height > 0 else { return nil }
        // Frozen, it turns only while the slide is on screen alone.
        let span = r.motionSpan(frozen: rot.freezeOnTransition)
        let e = CGRect(x: 0, y: 0, width: W, height: H)
        func view(_ p: CGPoint) -> CGPoint { CGPoint(x: frame.minX + p.x, y: frame.minY + frame.height - p.y) }
        func end(_ progress: Double) -> RotEnd? {
            let kb = r.kenBurns?.frame(at: progress) ?? .centred
            let pivot = rot.pivot(at: progress), angle = rot.angle(at: progress, span: span)
            guard let still = Compositor.placement(imageExtent: e, fit: r.fit, kb: kb, transform: r.transform,
                                                   spin: nil, outputSize: frame.size),
                  let turned = Compositor.placement(imageExtent: e, fit: r.fit, kb: kb, transform: r.transform,
                                                    spin: (angle: angle, pivot: pivot), outputSize: frame.size)
            else { return nil }
            let quad = [CGPoint(x: 0, y: H), CGPoint(x: W, y: H), CGPoint(x: W, y: 0), .zero]
                .map { view($0.applying(turned)) }
            let pv = view(CGPoint(x: CGFloat(pivot.x) * W, y: CGFloat(1 - pivot.y) * H).applying(still))
            let th = CGFloat(angle + r.transform.rotation) * .pi / 180
            return RotEnd(quad: quad, pivot: pv, knob: CGPoint(x: pv.x + 70 * sin(th), y: pv.y - 70 * cos(th)),
                          still: still)
        }
        guard let s = end(0), let f = end(1) else { return nil }
        return RotGeo(slideID: id, rotation: rot, span: span, ends: [s, f], W: W, H: H, frame: frame)
    }

    func rotationZone(_ g: RotGeo, at p: CGPoint) -> RotZone? {
        func near(_ a: CGPoint, _ r: CGFloat) -> Bool { hypot(a.x - p.x, a.y - p.y) <= r }
        // The end first: when both arms lie together, it's usually the one being set.
        if near(g.ends[1].knob, 9) { return .angle(end: 1) }
        if near(g.ends[0].knob, 9) { return .angle(end: 0) }
        if !g.rotation.pivotLocked, near(g.ends[1].pivot, 9) { return .pivot(end: 1) }
        if near(g.ends[0].pivot, 9) { return .pivot(end: 0) }
        return nil
    }

    func applyRotation(_ d: inout RotDrag, to p: CGPoint, modifiers: NSEvent.ModifierFlags) -> Rotation {
        var rot = d.start
        switch d.zone {
        case .angle(let end):
            let pivot = d.geo.ends[end].pivot
            let a = atan2(p.y - pivot.y, p.x - pivot.x)
            var step = a - d.lastAtan
            if step > .pi { step -= 2 * .pi } else if step < -.pi { step += 2 * .pi }
            d.turned += step
            d.lastAtan = a
            let from = end == 0 ? d.start.startAngle : d.start.angle(at: 1, span: d.geo.span)
            var value = from + Double(d.turned) * 180 / .pi
            if modifiers.contains(.shift) { value = (value / 15).rounded() * 15 }
            if end == 0 {
                rot.startAngle = value
            } else if rot.mode == .angles {
                rot.endAngle = value
            } else if d.geo.span > 0 {
                rot.speed = (value - rot.startAngle) / d.geo.span
            }
        case .pivot(let end):
            let point = d.geo.imagePoint(atView: p, end: end)
            if end == 0 || rot.pivotLocked { rot.pivotStart = point } else { rot.pivotEnd = point }
        }
        return rot
    }

    func rotationActionName(_ z: RotZone, _ r: Rotation) -> String {
        switch z {
        case .angle(end: 0): "Change Start Angle"
        case .angle: r.mode == .angles ? "Change End Angle" : "Change Speed"
        case .pivot: "Move Pivot"
        }
    }

    func setLiveRotation(_ r: Rotation, slideID: Int64) {
        liveRotation = r
        var s = engine.show
        guard let i = s.slides.firstIndex(where: { $0.id == slideID }) else { return }
        s.slides[i].settings.rotation = r
        engine.showLiveEdit(s)
    }

    func commitRotation(_ r: Rotation, slideID: Int64, action: String) {
        controlLog.notice("\(action, privacy: .public) slide \(slideID): start \(r.startAngle) end \(r.endAngle) speed \(r.speed)")
        mutate(action) { s in
            guard let i = s.slides.firstIndex(where: { $0.id == slideID }) else { return }
            s.slides[i].settings.rotation = r
        }
        liveRotation = nil
        engine.endLiveEdit()
    }

    /// The Ken Burns editor's colours: green for the start, red for the end.
    func rotationHandles(_ g: RotGeo) -> some View {
        Canvas { ctx, _ in
            func outlined(_ path: Path, _ colour: Color, width: CGFloat = 1.5) {
                ctx.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: width + 2)
                ctx.stroke(path, with: .color(colour), lineWidth: width)
            }
            func crosshair(_ a: CGPoint, _ colour: Color) {
                var cross = Path()
                cross.addEllipse(in: CGRect(x: a.x - 5, y: a.y - 5, width: 10, height: 10))
                cross.move(to: CGPoint(x: a.x - 10, y: a.y)); cross.addLine(to: CGPoint(x: a.x + 10, y: a.y))
                cross.move(to: CGPoint(x: a.x, y: a.y - 10)); cross.addLine(to: CGPoint(x: a.x, y: a.y + 10))
                outlined(cross, colour, width: 1)
            }
            let colours: [Color] = [.green, .red]
            for i in [0, 1] {
                let e = g.ends[i], c = colours[i]
                var quad = Path()
                quad.addLines(e.quad)
                quad.closeSubpath()
                outlined(quad, c.opacity(0.9))
                var arm = Path()
                arm.move(to: e.pivot); arm.addLine(to: e.knob)
                outlined(arm, c)
                let knob = Path(ellipseIn: CGRect(x: e.knob.x - 6, y: e.knob.y - 6, width: 12, height: 12))
                ctx.fill(knob, with: .color(c))
                ctx.stroke(knob, with: .color(.black.opacity(0.7)), lineWidth: 1)
                ctx.draw(Text(i == 0 ? "Start" : "End").font(.caption2.weight(.semibold)).foregroundColor(c),
                         at: CGPoint(x: e.knob.x, y: e.knob.y - 14))
            }
            if g.rotation.pivotLocked {
                crosshair(g.ends[0].pivot, .white)
            } else {
                crosshair(g.ends[0].pivot, .green)
                crosshair(g.ends[1].pivot, .red)
            }
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
