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
        let s = SlideSettings(background: RGBColor(red: 1, green: 0.5, blue: 0), rotation: r)
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
            length: .seconds(4), background: RGBColor(red: 0, green: 0, blue: 1), rotation: r))]
        let item = MediaItem(id: 1, relativePath: "a.jpg", hash: "h", kind: .image,
                             pixelWidth: 100, pixelHeight: 100, duration: nil,
                             ingestedAt: Date(), sourcePath: "")
        func layer(_ show: Show) -> Layer? {
            if case .still(let l) = ShowTimeline(show: show, items: [1: item]).frame(at: 2) { return l }
            return nil
        }
        XCTAssertEqual(layer(show)?.rotationAngle ?? -1, 45, accuracy: 1e-9)
        XCTAssertEqual(layer(show)?.slide.background, RGBColor(red: 0, green: 0, blue: 1))
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
