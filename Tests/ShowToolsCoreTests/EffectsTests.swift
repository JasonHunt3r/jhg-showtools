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
