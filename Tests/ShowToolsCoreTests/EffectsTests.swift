import XCTest
@testable import ShowToolsCore

final class EffectsTests: XCTestCase {

    // MARK: Old shows still load

    func testKenBurnsSavedBeforeAccelerationKeepsItsFrames() throws {
        // Exactly what a Phase 2 save wrote: no "acceleration" key.
        let kb = KenBurns(start: KenBurnsFrame(x: 0.3, y: 0.4, zoom: 1.5),
                          end: KenBurnsFrame(x: 0.6, y: 0.5, zoom: 2), easing: .linear)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(kb)) as! [String: Any]
        json.removeValue(forKey: "acceleration")
        let old = try JSONDecoder().decode(KenBurns.self,
                                           from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old, kb)
        XCTAssertEqual(old.acceleration, 0)
    }

    func testSettingsSavedBeforePhase2aDecodeWithNoNewEffects() throws {
        let s = try JSONDecoder().decode(SlideSettings.self,
                                         from: Data(#"{"fit":"fit","clipStart":2}"#.utf8))
        XCTAssertEqual(s.fit, .fit)
        XCTAssertEqual(s.clipStart, 2)
        XCTAssertNil(s.rotation)
        XCTAssertNil(s.background)
        let d = try JSONDecoder().decode(ShowDefaults.self, from: Data(#"{"length":7}"#.utf8))
        XCTAssertEqual(d.length, 7)
        XCTAssertEqual(d.background, .black)
    }

    func testOneBadRotationFieldDoesNotResetTheRest() throws {
        let json = #"{"mode":"angles","startAngle":10,"endAngle":"ninety","pivotLocked":false}"#
        let r = try JSONDecoder().decode(Rotation.self, from: Data(json.utf8))
        XCTAssertEqual(r.mode, .angles)
        XCTAssertEqual(r.startAngle, 10)
        XCTAssertEqual(r.endAngle, 0)           // the bad one falls back alone
        XCTAssertFalse(r.pivotLocked)
    }

    func testRotationRoundTripsThroughSettings() throws {
        var r = Rotation()
        r.mode = .speed; r.speed = -45; r.acceleration = 0.8
        r.pivotStart = ImagePoint(x: -0.2, y: 1.3); r.pivotLocked = false
        let s = SlideSettings(background: SRGBColor(red: 1, green: 0.5, blue: 0), rotation: r)
        let back = try JSONDecoder().decode(SlideSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: Motion

    func testAccelerationKeepsTheEndsAndOnlyReshapesTiming() {
        for a in [-1, -0.5, 0, 0.5, 1.0] {
            XCTAssertEqual(Acceleration.shape(0, amount: a), 0, accuracy: 1e-12)
            XCTAssertEqual(Acceleration.shape(1, amount: a), 1, accuracy: 1e-12)
            var last = -1.0
            for i in 0...20 {
                let v = Acceleration.shape(Double(i) / 20, amount: a)
                XCTAssertGreaterThanOrEqual(v, last)   // never runs backwards
                last = v
            }
        }
        XCTAssertEqual(Acceleration.shape(0.3, amount: 0), 0.3, accuracy: 1e-12)
        XCTAssertLessThan(Acceleration.shape(0.5, amount: 1), 0.5)       // slow start
        XCTAssertGreaterThan(Acceleration.shape(0.5, amount: -1), 0.5)   // slow finish
    }

    func testZeroAccelerationLeavesKenBurnsAsBefore() {
        let kb = KenBurns(start: .centred, end: KenBurnsFrame(x: 0.7, y: 0.5, zoom: 2))
        let p = 0.3, e = Easing.easeInOut.apply(p)
        XCTAssertEqual(kb.frame(at: p).zoom, 1 + e, accuracy: 1e-12)
    }

    func testAnglesModeEndsOnItsEndAngleWhateverTheLength() {
        var r = Rotation()
        r.startAngle = 10; r.endAngle = 100; r.acceleration = 0.7
        for span in [2.0, 9.0] {
            XCTAssertEqual(r.angle(at: 0, span: span), 10, accuracy: 1e-9)
            XCTAssertEqual(r.angle(at: 1, span: span), 100)   // exactly
        }
    }

    func testSpeedModeTurnsSpeedTimesSpan() {
        var r = Rotation()
        r.mode = .speed; r.startAngle = 5; r.speed = 30
        XCTAssertEqual(r.angle(at: 1, span: 4), 125, accuracy: 1e-9)
        XCTAssertEqual(r.angle(at: 0.5, span: 4), 65, accuracy: 1e-9)
        r.acceleration = 1                       // same total, later arrival
        XCTAssertEqual(r.angle(at: 1, span: 4), 125, accuracy: 1e-9)
        XCTAssertLessThan(r.angle(at: 0.5, span: 4), 65)
    }

    func testLockedPivotStaysPut() {
        var r = Rotation()
        r.pivotStart = ImagePoint(x: 0.2, y: 0.8); r.pivotEnd = ImagePoint(x: 0.9, y: 0.1)
        XCTAssertEqual(r.pivot(at: 0.6), r.pivotStart)
        r.pivotLocked = false
        XCTAssertEqual(r.pivot(at: 1), r.pivotEnd)
    }

    // MARK: Through the timeline

    func testTimelineSamplesRotationOnlyWhenEnabled() {
        var r = Rotation()
        r.startAngle = 0; r.endAngle = 90
        var show = Show(id: 1, name: "t")
        show.defaults.transition = Transition(style: .cut, duration: 0)
        show.defaults.loop = false
        show.slides = [Slide(id: 1, itemID: 1, settings: SlideSettings(
            length: .seconds(4), background: SRGBColor(red: 0, green: 0, blue: 1), rotation: r))]
        let item = MediaItem(id: 1, relativePath: "a.jpg", hash: "h", kind: .image,
                             pixelWidth: 100, pixelHeight: 100, duration: nil,
                             ingestedAt: Date(), sourcePath: "")
        func layer(_ show: Show) -> Layer? {
            if case .still(let l) = ShowTimeline(show: show, items: [1: item]).frame(at: 2) { return l }
            return nil
        }
        XCTAssertEqual(layer(show)?.rotationAngle ?? -1, 45, accuracy: 1e-9)
        XCTAssertEqual(layer(show)?.slide.background, SRGBColor(red: 0, green: 0, blue: 1))
        show.slides[0].settings.rotation?.enabled = false
        XCTAssertEqual(layer(show)?.rotationAngle, 0)
    }
}

extension EffectsTests {
    func testKenBurnsLandsExactlyOnItsEndFrame() {
        let end = KenBurnsFrame(x: 0.9, y: 0.1, zoom: 2.3)
        for a in [-0.6, 0, 1.0] {
            let kb = KenBurns(start: KenBurnsFrame(x: 0.2, y: 0.8, zoom: 1), end: end, acceleration: a)
            XCTAssertEqual(kb.frame(at: 1), end)
        }
    }
}

extension EffectsTests {
    /// Two 4s slides joined by a 1s dissolve: B starts at 4 and the dissolve
    /// runs 4…5. A is first, so on the first pass nothing dissolves into it
    /// and, frozen, it moves 0…4.
    func twoSlides(_ a: SlideSettings, _ b: SlideSettings = SlideSettings(),
                   loop: Bool = false) -> ShowTimeline {
        var show = Show(id: 1, name: "t")
        show.defaults.transition = Transition(style: .dissolve, duration: 1)
        show.defaults.loop = loop
        show.slides = [Slide(id: 1, itemID: 1, settings: a), Slide(id: 2, itemID: 2, settings: b)]
        let item = { (id: Int64) in MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)",
            kind: .image, pixelWidth: 100, pixelHeight: 100, duration: nil,
            ingestedAt: Date(), sourcePath: "") }
        return ShowTimeline(show: show, items: [1: item(1), 2: item(2)])
    }

    func testFreezeOnTransitionReachesTheEndFrameAsTheDissolveBegins() {
        var r = Rotation(); r.endAngle = 90
        var frozen = r; frozen.freezeOnTransition = true
        func outgoing(_ tl: ShowTimeline, at t: Double) -> Layer? {
            switch tl.frame(at: t) {
            case .still(let l): l
            case .transition(let from, _, _, _): from
            case .empty: nil
            }
        }
        let loose = twoSlides(SlideSettings(length: .seconds(4), rotation: r))
        let held = twoSlides(SlideSettings(length: .seconds(4), rotation: frozen))
        // Unfrozen: still turning through the dissolve (4…5).
        XCTAssertLessThan(outgoing(loose, at: 4.5)!.rotationAngle, 90)
        // Frozen: at the end angle for the whole dissolve…
        XCTAssertEqual(outgoing(held, at: 4.0)!.rotationAngle, 90)
        XCTAssertEqual(outgoing(held, at: 4.5)!.rotationAngle, 90)
        // …and moving before it.
        XCTAssertEqual(outgoing(held, at: 2.0)!.rotationAngle, 45, accuracy: 1e-9)
    }

    func testFreezeHoldsTheStartFrameThroughTheTransitionIn() {
        let kb = KenBurns(start: .centred, end: KenBurnsFrame(x: 0.5, y: 0.5, zoom: 2),
                          easing: .linear, freezeOnTransition: true)
        let tl = twoSlides(SlideSettings(length: .seconds(4)),
                           SlideSettings(length: .seconds(4), kenBurns: .custom(kb)))
        guard case .transition(_, let b, _, _) = tl.frame(at: 4.5) else { return XCTFail() }
        XCTAssertEqual(b.kenBurnsFrame, .centred)
        guard case .still(let b2) = tl.frame(at: 6.5) else { return XCTFail() }
        // B moves from 5 (dissolve over) to 8 (its own end; it's last, no transition out).
        XCTAssertEqual(b2.kenBurnsFrame.zoom, 1.5, accuracy: 1e-9)
    }
}

extension EffectsTests {
    func testFirstSlideOfALoopingShowStartsAtOnceThenHoldsAfterTheWrap() {
        var r = Rotation(); r.endAngle = 90; r.freezeOnTransition = true
        // Loops: A 0…4, B 4…8, then B dissolves back into A over 8…9.
        let tl = twoSlides(SlideSettings(length: .seconds(4), rotation: r),
                           SlideSettings(length: .seconds(4)), loop: true)
        func a(at t: Double) -> Layer? {
            switch tl.frame(at: t) {
            case .still(let l): l.slide.index == 0 ? l : nil
            case .transition(let from, let to, _, _): from.slide.index == 0 ? from : to.slide.index == 0 ? to : nil
            case .empty: nil
            }
        }
        // First pass: nothing comes in, so A turns from the very start.
        // It holds its end over its dissolve out (4…5), so it moves 0…4.
        XCTAssertEqual(a(at: 0)!.rotationAngle, 0)
        XCTAssertEqual(a(at: 2)!.rotationAngle, 45, accuracy: 1e-9)
        // After the wrap B dissolves into A (8…9): A holds its start…
        XCTAssertEqual(a(at: 8.5)!.rotationAngle, 0)
        // …then moves 9…12, so 10.5 is halfway.
        XCTAssertEqual(a(at: 10.5)!.rotationAngle, 45, accuracy: 1e-9)
    }

    func testOneSlideShowHasNothingToFreezeFor() {
        var r = Rotation(); r.endAngle = 90; r.freezeOnTransition = true
        var show = Show(id: 1, name: "t")
        show.defaults.transition = Transition(style: .dissolve, duration: 1)
        show.slides = [Slide(id: 1, itemID: 1, settings: SlideSettings(length: .seconds(4), rotation: r))]
        let item = MediaItem(id: 1, relativePath: "1.jpg", hash: "h", kind: .image, pixelWidth: 100,
                             pixelHeight: 100, duration: nil, ingestedAt: Date(), sourcePath: "")
        let tl = ShowTimeline(show: show, items: [1: item])
        guard case .still(let l) = tl.frame(at: 0.5) else { return XCTFail() }
        XCTAssertGreaterThan(l.rotationAngle, 0)   // moving, not held
    }
}

extension EffectsTests {
    func testNewShowsFitButSavedShowsKeepTheirFit() throws {
        XCTAssertEqual(ShowDefaults().fit, .fit)
        // Every earlier save wrote its fit, and the old default was fill.
        let old = try JSONDecoder().decode(ShowDefaults.self, from: Data(#"{"fit":"fill","length":5}"#.utf8))
        XCTAssertEqual(old.fit, .fill)
    }

    func testTransformDefaultsToIdentityAndSurvivesABadField() throws {
        let tl = twoSlides(SlideSettings(length: .seconds(4)))
        guard case .still(let l) = tl.frame(at: 1) else { return XCTFail() }
        XCTAssertEqual(l.slide.transform, .identity)

        let t = try JSONDecoder().decode(Transform.self,
            from: Data(#"{"offsetX":0.1,"scale":"big","rotation":12}"#.utf8))
        XCTAssertEqual(t.offsetX, 0.1)
        XCTAssertEqual(t.scale, 1)
        XCTAssertEqual(t.rotation, 12)
    }
}

extension EffectsTests {
    /// A 400×300 image fitted into 800×600: 2× scale, filling the frame.
    func place(_ p: ImagePoint, transform: Transform = .identity,
               spin: (angle: Double, pivot: ImagePoint)? = nil) -> CGPoint {
        let e = CGRect(x: 0, y: 0, width: 400, height: 300)
        let m = Compositor.placement(imageExtent: e, fit: .fit, kb: .centred, transform: transform,
                                     spin: spin, outputSize: CGSize(width: 800, height: 600))!
        return CGPoint(x: e.minX + p.x * 400, y: e.minY + (1 - p.y) * 300).applying(m)
    }

    func assertNear(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, file: file, line: line)
    }

    func testIdentityTransformIsJustTheFit() {
        // Top-left of the image → top-left of the frame (Core Image y is up).
        assertNear(place(ImagePoint(x: 0, y: 0)), CGPoint(x: 0, y: 600))
        assertNear(place(.centre), CGPoint(x: 400, y: 300))
    }

    func testTransformOffsetsRightAndDown() {
        var t = Transform(); t.offsetX = 0.25; t.offsetY = 0.5
        assertNear(place(.centre, transform: t), CGPoint(x: 600, y: 0))
    }

    func testTransformScalesAndTurnsClockwiseAroundItsAnchor() {
        var t = Transform(); t.anchor = ImagePoint(x: 0, y: 0); t.scale = 0.5
        assertNear(place(ImagePoint(x: 0, y: 0), transform: t), CGPoint(x: 0, y: 600))   // anchor stays
        assertNear(place(ImagePoint(x: 1, y: 1), transform: t), CGPoint(x: 400, y: 300))
        t.scale = 1; t.rotation = 90; t.anchor = .centre
        // Clockwise on screen: the top-centre point swings to the right.
        assertNear(place(ImagePoint(x: 0.5, y: 0), transform: t), CGPoint(x: 700, y: 300))
    }

    func testSpinTurnsAroundItsPivotAndTheAnchorDoesNotWobble() {
        let pivot = ImagePoint(x: 1, y: 1)                    // bottom-right corner
        assertNear(place(pivot, spin: (angle: 37, pivot: pivot)), CGPoint(x: 800, y: 0))
        // With a scaled Transform on top, the pivot's image point lands where
        // the Transform alone puts it, at every angle.
        var t = Transform(); t.scale = 0.5
        let still = place(pivot, transform: t)
        for a in [0.0, 45, 170, 300] {
            assertNear(place(pivot, transform: t, spin: (angle: a, pivot: pivot)), still)
        }
    }
}

// MARK: - Handle maths

final class TransformEditTests: XCTestCase {
    let size = CGSize(width: 800, height: 450)
    let image = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// On screen, y down, for an image point in Core Image pixels.
    func screen(_ q: CGPoint, _ t: Transform, spin: (angle: Double, pivot: ImagePoint)? = nil) -> CGPoint {
        let m = Compositor.placement(imageExtent: image, fit: .fit, kb: .centred, transform: t,
                                     spin: spin, outputSize: size)!
        let p = q.applying(m)
        return CGPoint(x: p.x, y: size.height - p.y)
    }
    var corners: [CGPoint] { [CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300), CGPoint(x: 400, y: 0), .zero] }
    /// The anchor before the Transform, on screen.
    func anchorBase(_ t: Transform) -> CGPoint {
        screen(CGPoint(x: t.anchor.x * 400, y: (1 - t.anchor.y) * 300), .identity)
    }
    func near(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, file: file, line: line)
    }
    var messy: Transform {
        var t = Transform()
        t.offsetX = 0.07; t.offsetY = -0.12; t.scale = 0.8; t.rotation = 23
        t.anchor = ImagePoint(x: 0.3, y: 0.65)
        return t
    }

    func testScalingFromACornerKeepsTheOppositeCornerPut() {
        let t = messy
        let fixed = screen(corners[2], t)                 // bottom right stays
        let before = screen(corners[0], t)
        let out = TransformEdit.scaled(t, by: 1.7, about: fixed, anchor: anchorBase(t), size: size)
        near(screen(corners[2], out), fixed)
        near(screen(corners[0], out), CGPoint(x: fixed.x + 1.7 * (before.x - fixed.x),
                                              y: fixed.y + 1.7 * (before.y - fixed.y)))
        XCTAssertEqual(out.rotation, t.rotation)
    }

    func testScalingAboutTheCentreKeepsTheCentrePut() {
        let t = messy
        let c = corners.map { screen($0, t) }
        let centre = CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4)
        let out = TransformEdit.scaled(t, by: 0.5, about: centre, anchor: anchorBase(t), size: size)
        let c2 = corners.map { screen($0, out) }
        near(CGPoint(x: c2.map(\.x).reduce(0, +) / 4, y: c2.map(\.y).reduce(0, +) / 4), centre)
    }

    func testMovingTheAnchorLeavesTheImageWhereItWas() {
        let t = messy
        let target = CGPoint(x: 612, y: 90)
        let (out, B) = TransformEdit.movingAnchor(t, to: target, anchor: anchorBase(t), size: size)
        // B back to an image point, as the overlay does.
        let base = Compositor.placement(imageExtent: image, fit: .fit, kb: .centred, transform: .identity,
                                        spin: nil, outputSize: size)!
        let ci = CGPoint(x: B.x, y: size.height - B.y).applying(base.inverted())
        var moved = out
        moved.anchor = ImagePoint(x: ci.x / 400, y: 1 - ci.y / 300)
        for q in corners { near(screen(q, moved), screen(q, t)) }
        // …and the crosshair (anchor before the Transform, plus the offset) is at the target.
        let o = TransformEdit.offset(moved, size: size)
        near(CGPoint(x: anchorBase(moved).x + o.x, y: anchorBase(moved).y + o.y), target)
    }

    func testMovingTheAnchorWorksWithASpinToo() {
        let t = messy
        let spin = (angle: 40.0, pivot: ImagePoint(x: 0.9, y: 0.1))
        let (out, B) = TransformEdit.movingAnchor(t, to: CGPoint(x: 200, y: 300), anchor: anchorBase(t), size: size)
        let base = Compositor.placement(imageExtent: image, fit: .fit, kb: .centred, transform: .identity,
                                        spin: nil, outputSize: size)!
        let ci = CGPoint(x: B.x, y: size.height - B.y).applying(base.inverted())
        var moved = out
        moved.anchor = ImagePoint(x: ci.x / 400, y: 1 - ci.y / 300)
        for q in corners { near(screen(q, moved, spin: spin), screen(q, t, spin: spin)) }
    }
}

// MARK: - Soft at this zoom

final class SoftnessTests: XCTestCase {
    let screen = CGSize(width: 2880, height: 1800)

    func resolved(_ settings: SlideSettings, w: Int = 4000, h: Int = 3000) -> ResolvedSlide {
        var show = Show(id: 1, name: "t")
        show.defaults.loop = false
        show.slides = [Slide(id: 1, itemID: 1, settings: settings)]
        let item = MediaItem(id: 1, relativePath: "a.jpg", hash: "h", kind: .image, pixelWidth: w,
                             pixelHeight: h, duration: nil, ingestedAt: Date(), sourcePath: "")
        return ShowTimeline(show: show, items: [1: item]).slides[0]
    }

    func testAFittedLargePhotoIsSharp() {
        // Fit: min(2880/4000, 1800/3000) = 0.6.
        let r = resolved(SlideSettings(kenBurns: .off, fit: .fit))
        XCTAssertEqual(r.peakMagnification(outputSize: screen), 0.6, accuracy: 1e-9)
        XCTAssertFalse(r.isSoft(outputSize: screen))
    }

    func testTransformZoomMakesItSoft() {
        var t = Transform(); t.scale = 3; t.rotation = 30
        let r = resolved(SlideSettings(kenBurns: .off, fit: .fit, transform: t))
        XCTAssertEqual(r.peakMagnification(outputSize: screen), 1.8, accuracy: 1e-9)
        XCTAssertTrue(r.isSoft(outputSize: screen))
    }

    func testKenBurnsCountsAtItsClosest() {
        // Fill: max(0.72, 0.6) = 0.72; zoomed to 2.5 at the end → 1.8.
        let kb = KenBurns(start: .centred, end: KenBurnsFrame(x: 0.5, y: 0.5, zoom: 2.5))
        let r = resolved(SlideSettings(kenBurns: .custom(kb), fit: .fill))
        XCTAssertEqual(r.peakMagnification(outputSize: screen), 1.8, accuracy: 1e-9)
    }

    func testASmallFileIsSoftEvenFitted() {
        let r = resolved(SlideSettings(kenBurns: .off, fit: .fit), w: 800, h: 600)
        XCTAssertEqual(r.peakMagnification(outputSize: screen), 3, accuracy: 1e-9)
    }
}

// MARK: - Transition lead (Phase 2c)

final class TransitionLeadTests: XCTestCase {
    /// Two (or more) 4 s slides; every transition a 1 s dissolve with `lead`.
    func timeline(lengths: [Double] = [4, 4], lead: Double, loop: Bool = false,
                  settings: [SlideSettings]? = nil) -> ShowTimeline {
        var show = Show(id: 1, name: "t")
        show.defaults.transition = Transition(style: .dissolve, duration: 1, lead: lead)
        show.defaults.loop = loop
        show.defaults.kenBurns = .off
        var items: [Int64: MediaItem] = [:]
        for (i, l) in lengths.enumerated() {
            let id = Int64(i + 1)
            var s = settings?[i] ?? SlideSettings()
            s.length = .seconds(l)
            show.slides.append(Slide(id: id, itemID: id, settings: s))
            items[id] = MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: .image,
                                  pixelWidth: 100, pixelHeight: 100, duration: nil,
                                  ingestedAt: Date(), sourcePath: "")
        }
        return ShowTimeline(show: show, items: items)
    }

    func describe(_ s: FrameState) -> String {
        switch s {
        case .empty: "empty"
        case .still(let l): "still \(l.slide.index)"
        case .transition(let a, let b, _, let p): "\(a.slide.index)→\(b.slide.index) \(String(format: "%.2f", p))"
        }
    }

    func testTransitionsSavedBeforeLeadKeepTheirSettings() throws {
        let t = try JSONDecoder().decode(Transition.self,
            from: Data(#"{"style":"push","duration":2.5,"direction":"up"}"#.utf8))
        XCTAssertEqual(t, Transition(style: .push, duration: 2.5, direction: .up, lead: 0))
    }

    func testLeadZeroStartsAtTheJoinAsBefore() {
        let tl = timeline(lead: 0)
        XCTAssertEqual(describe(tl.frame(at: 3.9)), "still 0")
        XCTAssertEqual(describe(tl.frame(at: 4.5)), "0→1 0.50")
        XCTAssertEqual(describe(tl.frame(at: 5.0)), "still 1")
    }

    func testAStraddlingTransitionOverlapsEitherSideOfTheJoin() {
        let tl = timeline(lead: 0.5)                      // overlap 3.5 … 4.5
        XCTAssertEqual(describe(tl.frame(at: 3.4)), "still 0")
        XCTAssertEqual(describe(tl.frame(at: 3.5)), "0→1 0.00")
        XCTAssertEqual(describe(tl.frame(at: 3.9)), "0→1 0.40")
        XCTAssertEqual(describe(tl.frame(at: 4.0)), "0→1 0.50")
        XCTAssertEqual(describe(tl.frame(at: 4.25)), "0→1 0.75")
        XCTAssertEqual(describe(tl.frame(at: 4.5)), "still 1")
        // The show is still the slides' lengths, join to join.
        XCTAssertEqual(tl.duration, 8)
    }

    func testATransitionCanEndAtTheJoin() {
        let tl = timeline(lead: 1)                        // overlap 3 … 4
        XCTAssertEqual(describe(tl.frame(at: 3.5)), "0→1 0.50")
        XCTAssertEqual(describe(tl.frame(at: 4.0)), "still 1")
        XCTAssertEqual(tl.settledTime(of: 1), 4)
    }

    func testTheIncomingSlidesClockStartsWhenItAppears() {
        let tl = timeline(lead: 0.5)
        guard case .transition(let a, let b, _, _) = tl.frame(at: 3.75) else { return XCTFail() }
        XCTAssertEqual(b.localTime, 0.25, accuracy: 1e-9)   // appeared at 3.5
        XCTAssertEqual(a.localTime, 3.75, accuracy: 1e-9)   // slide 0 counts from 0
        // Slide 1 is on screen 3.5 … 8 (the show doesn't loop, nothing follows).
        XCTAssertEqual(tl.slides[1].visibleSpan, 4.5, accuracy: 1e-9)
        XCTAssertEqual(tl.slides[0].visibleSpan, 4.5, accuracy: 1e-9)  // 0 … 4.5
    }

    func testTheOutgoingSlideReachesItsEndFrameAsTheOverlapEnds() {
        var r = Rotation(); r.endAngle = 90
        let tl = timeline(lead: 0.5, settings: [SlideSettings(rotation: r), SlideSettings()])
        guard case .transition(let a, _, _, _) = tl.frame(at: 4.499) else { return XCTFail() }
        XCTAssertEqual(a.rotationAngle, 90, accuracy: 0.05)
    }

    func testALoopingShowWrapsSmoothlyIntoSlideOne() {
        let tl = timeline(lead: 0.5, loop: true)          // into slide 0: 7.5 … 8.5
        XCTAssertEqual(describe(tl.frame(at: 7.4)), "still 1")
        XCTAssertEqual(describe(tl.frame(at: 7.75)), "1→0 0.25")
        XCTAssertEqual(describe(tl.frame(at: 8.25)), "1→0 0.75")
        XCTAssertEqual(describe(tl.frame(at: 8.5)), "still 0")
        // On the first pass nothing comes before slide 0.
        XCTAssertEqual(describe(tl.frame(at: 0.1)), "still 0")
    }

    func testLeadsNeverLetTwoTransitionsOverlap() {
        // Slide 1 is 1 s long. Its own transition in (lead 0.8) still covers
        // 0.2 s of it, leaving 0.8 s for the transition into slide 2 to start
        // early: the 0.8 asked for fits.
        let early = timeline(lengths: [4, 1, 4], lead: 0.8)
        XCTAssertEqual(early.slides[1].transitionIn.lead, 0.8, accuracy: 1e-9)
        XCTAssertEqual(early.slides[2].transitionIn.lead, 0.8, accuracy: 1e-9)

        // With lead 0 into slide 1, its transition fills all of it, so the
        // transition into slide 2 has no room and its 0.8 is cut to 0.
        let into1 = SlideSettings(transition: Transition(style: .dissolve, duration: 1, lead: 0))
        let into2 = SlideSettings(transition: Transition(style: .dissolve, duration: 1, lead: 0.8))
        let tight = timeline(lengths: [4, 1, 4], lead: 0, settings: [SlideSettings(), into1, into2])
        XCTAssertEqual(tight.slides[2].transitionIn.lead, 0)

        // Either way, every overlap ends before the next one begins.
        for tl in [early, tight] {
            for i in 1..<tl.slides.count - 1 {
                let endIn = tl.slides[i].visibleStart + tl.slides[i].transitionIn.duration
                XCTAssertLessThanOrEqual(endIn, tl.slides[i + 1].visibleStart + 1e-9)
            }
        }
    }

    func testALeadCantExceedItsDuration() {
        let tl = timeline(lead: 3)
        XCTAssertEqual(tl.slides[1].transitionIn.lead, 1)
    }
}

extension TransitionLeadTests {
    func testNewShowsDefaultToATwoSecondDissolveCentredOnTheJoin() throws {
        XCTAssertEqual(ShowDefaults().transition, Transition(style: .dissolve, duration: 2, lead: 1))
        // Saved shows wrote their default out in full, so they keep it.
        let old = try JSONDecoder().decode(ShowDefaults.self, from: Data(
            #"{"transition":{"style":"dissolve","duration":1,"direction":"left"},"length":5}"#.utf8))
        XCTAssertEqual(old.transition, Transition(style: .dissolve, duration: 1, lead: 0))
    }
}

// MARK: - The lane's images row

final class OverlayTests: XCTestCase {
    func item(_ id: Int64) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id).png", hash: "h\(id)", kind: .image, pixelWidth: 100,
                  pixelHeight: 100, duration: nil, ingestedAt: Date(), sourcePath: "")
    }

    func timeline(_ clips: [OverlayClip], loop: Bool = false) -> ShowTimeline {
        var show = Show(id: 1, name: "t")
        show.defaults.loop = loop
        show.slides = [Slide(id: 1, itemID: 1, settings: SlideSettings(length: .seconds(10)))]
        show.overlays = clips
        return ShowTimeline(show: show, items: [1: item(1), 2: item(2)])
    }

    func testAnOverlayShowsInItsWindowAndFades() {
        var c = OverlayClip(itemID: 2, start: 2, length: 4)
        c.fadeIn = 1; c.fadeOut = 1; c.opacity = 0.8
        let tl = timeline([c])
        XCTAssertNil(tl.overlay(at: 1.9))
        XCTAssertEqual(tl.overlay(at: 2.5)!.opacity, 0.4, accuracy: 1e-9)   // halfway in
        XCTAssertEqual(tl.overlay(at: 4)!.opacity, 0.8, accuracy: 1e-9)
        XCTAssertEqual(tl.overlay(at: 5.5)!.opacity, 0.4, accuracy: 1e-9)   // halfway out
        XCTAssertEqual(tl.overlay(at: 3)!.localTime, 1, accuracy: 1e-9)
        XCTAssertNil(tl.overlay(at: 6))
    }

    func testAMissingFileIsLeftOut() {
        let tl = timeline([OverlayClip(itemID: 99, start: 0, length: 5)])
        XCTAssertTrue(tl.overlays.isEmpty)
        XCTAssertNil(tl.overlay(at: 1))
    }

    /// The pixel at the centre of a 4×4 render.
    func centre(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return (Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
    }

    func testNormalAtHalfOpacityAndMultiply() {
        let size = CGSize(width: 4, height: 4)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        var c = OverlayClip(itemID: 2, start: 0, length: 5)
        c.fit = .fill
        let tl = timeline([c])
        let half = OverlayLayer(overlay: tl.overlays[0], localTime: 1, opacity: 0.5)
        let n = centre(Compositor.laid(half, image: blue, over: red, size: size))
        // Core Image mixes in linear light, as the dissolves do: an even
        // mix is 0.5 linear, which is about 0.735 once encoded as sRGB.
        XCTAssertEqual(n.r, 0.735, accuracy: 0.02)
        XCTAssertEqual(n.b, 0.735, accuracy: 0.02)
        XCTAssertLessThan(n.g, 0.02)

        // Multiply: yellow over grey is darker yellow, and blue vanishes.
        c.blend = .multiply
        let tl2 = timeline([c])
        let full = OverlayLayer(overlay: tl2.overlays[0], localTime: 1, opacity: 1)
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(origin: .zero, size: size))
        let yellow = CIImage(color: CIColor(red: 1, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let m = centre(Compositor.laid(full, image: yellow, over: grey, size: size))
        XCTAssertEqual(m.r, m.g, accuracy: 0.02)
        XCTAssertLessThan(m.r, 0.7)
        XCTAssertLessThan(m.b, 0.05)
    }
}

extension OverlayTests {
    func testFreeSpanIsTheGapBetweenImages() {
        let a = OverlayClip(itemID: 2, start: 2, length: 3)      // 2 … 5
        let b = OverlayClip(itemID: 2, start: 8, length: 2)      // 8 … 10
        XCTAssertEqual(OverlayPlacement.freeSpan(at: 6, in: [a, b], duration: 20), 5...8)
        XCTAssertEqual(OverlayPlacement.freeSpan(at: 1, in: [a, b], duration: 20), 0...2)
        XCTAssertEqual(OverlayPlacement.freeSpan(at: 12, in: [a, b], duration: 20), 10...20)
        XCTAssertNil(OverlayPlacement.freeSpan(at: 3, in: [a, b], duration: 20))
        // Moving `a` itself: its own space counts as free.
        XCTAssertEqual(OverlayPlacement.freeSpan(at: 3, in: [a, b], duration: 20, ignoring: a.id), 0...8)
    }

    func testPlacingStopsAtTheNextImage() {
        let b = OverlayClip(itemID: 2, start: 8, length: 2)
        XCTAssertEqual(OverlayPlacement.place(itemID: 3, at: 6, length: 5, in: [b], duration: 20)?.length, 2)
        XCTAssertEqual(OverlayPlacement.place(itemID: 3, at: 12, length: 5, in: [b], duration: 20)?.length, 5)
        XCTAssertNil(OverlayPlacement.place(itemID: 3, at: 9, length: 5, in: [b], duration: 20))
        XCTAssertNil(OverlayPlacement.place(itemID: 3, at: 7.9, length: 5, in: [b], duration: 20))
    }
}

extension TransitionLeadTests {
    /// Slides of these lengths, every join the new-show default (a 2 s
    /// dissolve centred on the join).
    func defaultTimeline(_ lengths: [Double], loop: Bool) -> ShowTimeline {
        var show = Show(id: 1, name: "t")
        show.defaults.loop = loop
        var items: [Int64: MediaItem] = [:]
        for (i, l) in lengths.enumerated() {
            let id = Int64(i + 1)
            show.slides.append(Slide(id: id, itemID: id, settings: SlideSettings(length: .seconds(l))))
            items[id] = MediaItem(id: id, relativePath: "\(id).jpg", hash: "h\(id)", kind: .image,
                                  pixelWidth: 100, pixelHeight: 100, duration: nil,
                                  ingestedAt: Date(), sourcePath: "")
        }
        return ShowTimeline(show: show, items: items)
    }

    /// Every transition as a span of show time, in play order, must end
    /// before the next begins. In a looping show the one into slide 0 plays
    /// at the end of each pass, and its tail runs into the start of the next.
    func assertNoOverlap(_ t: ShowTimeline, file: StaticString = #filePath, line: UInt = #line) {
        var spans: [(into: Int, begin: Double, end: Double)] = []
        for s in t.slides where s.index > 0 {
            spans.append((s.index, s.visibleStart, s.visibleStart + s.transitionIn.duration))
        }
        if t.loops, let first = t.slides.first {
            let tr = first.transitionIn
            spans.append((0, -tr.lead, tr.duration - tr.lead))
            spans.append((0, t.duration - tr.lead, t.duration - tr.lead + tr.duration))
        }
        spans = spans.filter { $0.end > $0.begin }.sorted { $0.begin < $1.begin }
        for (a, b) in zip(spans, spans.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.begin + 1e-9,
                                     "transition into \(a.into) runs past the start of the one into \(b.into)",
                                     file: file, line: line)
        }
    }

    /// Found in the 2026-09-21 audit: re-fitting slide 1's lead after slide
    /// 0's lengthened its tail, without re-checking slide 2, let two
    /// transitions overlap, and slide 0 vanished mid-dissolve.
    func testShortSlidesNeverOverlapTransitions() {
        let t = defaultTimeline([2.5, 2.2, 5], loop: false)
        assertNoOverlap(t)
        // Slide 0 is gone before slide 2 arrives: the dissolve into slide 1
        // (1.5…3.5 s) ends, slide 1 shows alone, then the next (from 3.7 s).
        XCTAssertEqual(describe(t.frame(at: 3.6)), "still 1")
        XCTAssertEqual(describe(t.frame(at: 3.8)), "1→2 0.05")
    }

    /// In a show that doesn't loop, slide 0's transition in never plays,
    /// so it mustn't take room from the transition into slide 1.
    func testUnplayedFirstTransitionTakesNoRoom() {
        let t = defaultTimeline([2.5, 2.2, 5], loop: false)
        XCTAssertEqual(t.slides[1].transitionIn.lead, 1, accuracy: 1e-9)
    }

    func testShortSlidesInALoopNeverOverlapTransitions() {
        for lengths in [[2.5, 2.2, 5], [5, 2.2, 1.5], [1.2, 1.1, 1.3, 1], [0.5, 4, 0.5]] {
            assertNoOverlap(defaultTimeline(lengths, loop: true))
            assertNoOverlap(defaultTimeline(lengths, loop: false))
        }
    }
}
