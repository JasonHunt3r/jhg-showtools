import XCTest
@testable import ShowToolsCore

/// A video slide's own sound, as a level line (spec/video-audio.md).
final class LevelsTests: XCTestCase {

    // MARK: - Reading a level off the line

    func testAnEmptyCurveIsSilent() {
        // The default a video slide gets until its sound is turned up.
        let curve = LevelCurve()
        XCTAssertTrue(curve.isEmpty)
        XCTAssertEqual(curve.level(at: 0), 0)
        XCTAssertEqual(curve.level(at: 5), 0)
    }

    func testOnePointHoldsItsLevelEverywhere() {
        let curve = LevelCurve(points: [LevelPoint(time: 3, level: 0.4)])
        XCTAssertEqual(curve.level(at: 0), 0.4)
        XCTAssertEqual(curve.level(at: 3), 0.4)
        XCTAssertEqual(curve.level(at: 99), 0.4)
    }

    func testItRampsLinearlyBetweenPointsAndHoldsFlatOutsideThem() {
        let curve = LevelCurve(points: [LevelPoint(time: 1, level: 0),
                                        LevelPoint(time: 3, level: 1)])
        XCTAssertEqual(curve.level(at: 0), 0, accuracy: 1e-9)   // before the first
        XCTAssertEqual(curve.level(at: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 2), 0.5, accuracy: 1e-9) // halfway
        XCTAssertEqual(curve.level(at: 2.5), 0.75, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 9), 1, accuracy: 1e-9)   // after the last
    }

    func testPointsAreKeptInTimeOrderHoweverTheyArrive() {
        let curve = LevelCurve(points: [LevelPoint(time: 4, level: 1),
                                        LevelPoint(time: 0, level: 0),
                                        LevelPoint(time: 2, level: 0.5)])
        XCTAssertEqual(curve.points.map(\.time), [0, 2, 4])
        XCTAssertEqual(curve.level(at: 1), 0.25, accuracy: 1e-9)
    }

    func testLevelsAreClampedToZeroAndOneAndTimesNeverGoNegative() {
        let p = LevelPoint(time: -5, level: 3)
        XCTAssertEqual(p.time, 0)
        XCTAssertEqual(p.level, 1)
        XCTAssertEqual(LevelPoint(time: 1, level: -2).level, 0)
    }

    func testTwoPointsAtTheSameTimeStepRatherThanDivideByZero() {
        // A vertical step: a cut from loud to silent.
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 1),
                                        LevelPoint(time: 2, level: 1),
                                        LevelPoint(time: 2, level: 0),
                                        LevelPoint(time: 4, level: 0)])
        XCTAssertEqual(curve.level(at: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 3), 0, accuracy: 1e-9)
    }

    /// The point of the feature, in one test: keep the talking, drop the dogs.
    func testKeepingTheMiddleOfAClipAndDroppingTheRest() {
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 0),
                                        LevelPoint(time: 2, level: 1),
                                        LevelPoint(time: 6, level: 1),
                                        LevelPoint(time: 8, level: 0)])
        XCTAssertEqual(curve.level(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(curve.level(at: 10), 0, accuracy: 1e-9)
    }

    // MARK: - Editing

    func testAddingAPointOnTheLineDoesntMoveTheLine() {
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 0),
                                        LevelPoint(time: 4, level: 1)])
        let added = curve.addingOnLine(at: 2)
        XCTAssertEqual(added.points.count, 3)
        for t in stride(from: 0.0, through: 4.0, by: 0.25) {
            XCTAssertEqual(added.level(at: t), curve.level(at: t), accuracy: 1e-9)
        }
    }

    func testMovingAPointKeepsItsIdentityAndReordersIfItPassesAnother() {
        let a = LevelPoint(time: 0, level: 0), b = LevelPoint(time: 2, level: 1)
        let curve = LevelCurve(points: [a, b])
        let moved = curve.moving(a.id, toTime: 5, level: 0.5)
        XCTAssertEqual(moved.points.map(\.id), [b.id, a.id])
        XCTAssertEqual(moved.points.last?.level, 0.5)
    }

    func testRemovingAPoint() {
        let a = LevelPoint(time: 0, level: 0), b = LevelPoint(time: 2, level: 1)
        let curve = LevelCurve(points: [a, b]).removing(a.id)
        XCTAssertEqual(curve.points.map(\.id), [b.id])
    }

    // MARK: - Describing a level-plus-fades clip

    func testASongsCurveAgreesWithItsEnvelope() {
        var clip = AudioClip(itemID: 1, start: 10, length: 8)
        clip.volume = 0.8
        clip.fadeIn = 2
        clip.fadeOut = 3
        // The curve is clip-relative; the envelope is in show time.
        for local in stride(from: 0.0, through: 8.0, by: 0.1) {
            XCTAssertEqual(clip.curve.level(at: local),
                           clip.envelope(at: clip.start + local), accuracy: 1e-9,
                           "at \(local)s into the clip")
        }
    }

    func testACurveWithNoFadesIsFlat() {
        var clip = AudioClip(itemID: 1, start: 0, length: 4)
        clip.volume = 0.5
        XCTAssertEqual(clip.curve.points.map(\.level), [0.5, 0.5])
        XCTAssertEqual(clip.curve.level(at: 2), 0.5, accuracy: 1e-9)
    }

    func testALaneImagesCurveFollowsItsOpacityAndFades() {
        var clip = OverlayClip(itemID: 1, start: 0, length: 10)
        clip.opacity = 0.6
        clip.fadeIn = 1
        clip.fadeOut = 1
        XCTAssertEqual(clip.curve.level(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(clip.curve.level(at: 0.5), 0.3, accuracy: 1e-9)
        XCTAssertEqual(clip.curve.level(at: 5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(clip.curve.level(at: 10), 0, accuracy: 1e-9)
    }

    // MARK: - Saving and reading back

    func testARoundTripKeepsEveryPoint() throws {
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 0),
                                        LevelPoint(time: 1.5, level: 0.75),
                                        LevelPoint(time: 4, level: 0)])
        let data = try JSONEncoder().encode(curve)
        let back = try JSONDecoder().decode(LevelCurve.self, from: data)
        XCTAssertEqual(back.points.map(\.time), curve.points.map(\.time))
        XCTAssertEqual(back.points.map(\.level), curve.points.map(\.level))
        XCTAssertEqual(back.points.map(\.id), curve.points.map(\.id))
    }

    /// One unreadable point mustn't cost the rest of the line: the next
    /// save would make that loss permanent (CLAUDE.md, the settings rule).
    func testAnUnreadablePointIsSkippedAndTheRestSurvive() throws {
        let json = """
        {"points":[{"time":0,"level":0},{"level":0.5},{"time":2,"level":1}]}
        """
        let curve = try JSONDecoder().decode(LevelCurve.self, from: Data(json.utf8))
        XCTAssertEqual(curve.points.map(\.time), [0, 2])
        XCTAssertEqual(curve.level(at: 1), 0.5, accuracy: 1e-9)
    }

    // MARK: - On a slide

    func testASlideSavedBeforeThisFeatureReadsBackSilent() throws {
        // Every video slide in a show written by an earlier build.
        let json = """
        {"length":{"seconds":{"_0":4}},"fit":"fill"}
        """
        let settings = try JSONDecoder().decode(SlideSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.audio)
        XCTAssertEqual(settings.audio?.level(at: 1) ?? 0, 0)
        // The other fields still read.
        XCTAssertEqual(settings.fit, .fill)
        XCTAssertEqual(settings.length, .seconds(4))
    }

    func testASlidesAudioSurvivesARoundTrip() throws {
        var settings = SlideSettings(length: .seconds(6))
        settings.audio = LevelCurve(points: [LevelPoint(time: 0, level: 0),
                                             LevelPoint(time: 2, level: 1)])
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(SlideSettings.self, from: Data(data))
        XCTAssertEqual(back.audio?.points.count, 2)
        XCTAssertEqual(back.audio?.level(at: 1), 0.5)
        XCTAssertEqual(back.length, .seconds(6))
    }

    /// An unreadable curve must not reset the slide's other settings.
    func testAnUnreadableAudioFieldLeavesTheRestOfTheSlideAlone() throws {
        let json = """
        {"length":{"seconds":{"_0":4}},"audio":"not a curve"}
        """
        let settings = try JSONDecoder().decode(SlideSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.audio)
        XCTAssertEqual(settings.length, .seconds(4))
    }

    // MARK: - Through the timeline to the player

    private func videoShow(_ audio: LevelCurve?) -> (Show, [Int64: MediaItem]) {
        var settings = SlideSettings(length: .seconds(4))
        settings.audio = audio
        let slides = [Slide(id: 1, itemID: 1, settings: settings),
                      Slide(id: 2, itemID: 2, settings: SlideSettings(length: .seconds(4)))]
        func make(_ id: Int64, _ kind: MediaKind) -> MediaItem {
            MediaItem(id: id, relativePath: "\(id)", hash: "h\(id)", kind: kind,
                      pixelWidth: 1280, pixelHeight: 720, duration: kind == .video ? 4 : nil,
                      ingestedAt: Date(), sourcePath: "")
        }
        return (Show(id: 1, name: "t", slides: slides), [1: make(1, .video), 2: make(2, .image)])
    }

    func testAVideoSlidesCurveReachesTheResolvedSlide() {
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 0),
                                        LevelPoint(time: 2, level: 1)])
        let (show, items) = videoShow(curve)
        let t = ShowTimeline(show: show, items: items)
        XCTAssertEqual(t.slides[0].audio.points.count, 2)
        XCTAssertEqual(t.slides[0].audio.level(at: 1), 0.5, accuracy: 1e-9)
    }

    func testAVideoSlideWithoutACurveIsSilentAndAStillNeverHasOne() {
        let (show, items) = videoShow(nil)
        let t = ShowTimeline(show: show, items: items)
        XCTAssertTrue(t.slides[0].audio.isEmpty)
        XCTAssertEqual(t.slides[0].audio.level(at: 1), 0)   // silent, not full
        XCTAssertTrue(t.slides[1].audio.isEmpty)            // the still
    }
}
