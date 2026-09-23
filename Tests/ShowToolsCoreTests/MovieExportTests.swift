import XCTest
import AVFoundation
@testable import ShowToolsCore

/// Video export E1: settings and codecs (spec/video-export.md).
final class MovieExportTests: XCTestCase {

    // MARK: - Codecs

    func testEachCodecMapsToItsAVCodecType() {
        XCTAssertEqual(MovieCodec.h264.avCodec, .h264)
        XCTAssertEqual(MovieCodec.hevc.avCodec, .hevc)
        XCTAssertEqual(MovieCodec.proRes422HQ.avCodec, .proRes422HQ)
    }

    /// The container rule: ProRes is QuickTime, never `.mp4`. An
    /// `AVAssetWriter` asked for that pair fails at the first sample.
    func testProResIsAlwaysMovAndTheOthersMp4() {
        XCTAssertEqual(MovieCodec.proRes422HQ.container, .mov)
        XCTAssertEqual(MovieCodec.proRes422HQ.fileExtension, "mov")
        XCTAssertEqual(MovieCodec.proRes422HQ.container.fileType, .mov)
        for codec in [MovieCodec.h264, .hevc] {
            XCTAssertEqual(codec.container, .mp4)
            XCTAssertEqual(codec.fileExtension, "mp4")
            XCTAssertEqual(codec.container.fileType, .mp4)
        }
    }

    func testNoCodecEverClaimsAnExtensionItsContainerCannotCarry() {
        for codec in MovieCodec.allCases {
            XCTAssertEqual(codec.fileExtension, codec.container.fileExtension)
            XCTAssertTrue(codec.menuTitle.hasSuffix("(.\(codec.fileExtension))"), codec.menuTitle)
        }
    }

    // MARK: - Frame rates

    func testTheOfferedRatesAreTwentyFourThirtyAndSixtyWithThirtyDefault() {
        XCTAssertEqual(MovieFrameRate.allCases.map(\.fps), [24, 30, 60])
        XCTAssertEqual(MovieFrameRate.default, .fps30)
    }

    func testAFrameDurationIsExactlyOneFrame() {
        for rate in MovieFrameRate.allCases {
            let whole = CMTimeMultiply(rate.frameDuration, multiplier: Int32(rate.fps))
            XCTAssertEqual(CMTimeGetSeconds(whole), 1, accuracy: 1e-9, "\(rate.fps) fps")
            XCTAssertEqual(rate.seconds, 1 / Double(rate.fps), accuracy: 1e-12)
        }
    }

    // MARK: - Even sizes

    func testAnOddSizeIsMadeEvenBecauseEncodersRequireIt() {
        let s = MovieExportSettings(size: CGSize(width: 1919, height: 1081))
        XCTAssertEqual(s.size, CGSize(width: 1918, height: 1080))
    }

    func testAStandardSizeIsLeftExactlyItself() {
        for preset in MovieSizePreset.standard {
            let s = MovieExportSettings(size: preset.size)
            XCTAssertEqual(s.size, preset.size, preset.name)
            XCTAssertEqual(s.size.width.truncatingRemainder(dividingBy: 2), 0)
            XCTAssertEqual(s.size.height.truncatingRemainder(dividingBy: 2), 0)
        }
        XCTAssertEqual(MovieSizePreset.standard.map(\.name), ["720p", "1080p", "4K"])
    }

    func testAScreenSizedShowComesOutEven() {
        // A Retina screen's odd pixel size, the kind `outputPixelSize` gives.
        var s = MovieExportSettings(size: CGSize(width: 3456, height: 2161))
        XCTAssertEqual(s.size, CGSize(width: 3456, height: 2160))
        s.setSize(CGSize(width: 2879, height: 1799))
        XCTAssertEqual(s.size, CGSize(width: 2878, height: 1798))
    }

    func testARidiculousSizeStillHasEvenSidesAndIsNeverZero() {
        XCTAssertEqual(MovieExportSettings(size: CGSize(width: 1, height: 1)).size,
                       CGSize(width: 2, height: 2))
        XCTAssertEqual(MovieExportSettings(size: CGSize(width: 0, height: -10)).size,
                       CGSize(width: 2, height: 2))
        XCTAssertEqual(MovieExportSettings(size: CGSize(width: CGFloat.nan, height: CGFloat.infinity)).size,
                       CGSize(width: 2, height: 2))
    }

    // MARK: - Letterboxing, never cropping

    func testAMatchingShapeFillsTheWholeFrame() {
        let s = MovieExportSettings(size: CGSize(width: 1920, height: 1080))
        let plan = s.plan(showAspect: 16.0 / 9.0)
        XCTAssertEqual(plan.picture, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(plan.isLetterboxed)
    }

    /// Jason's shows are roughly 16:10, which is *narrower* than 1080p's
    /// 16:9 — so at 1080p they pillarbox to 1728×1080. The picture is never
    /// cut: every slide and every Ken Burns move is framed for 16:10.
    func testASixteenTenShowPillarboxesInsideTenEightyRatherThanCropping() {
        let s = MovieExportSettings(size: CGSize(width: 1920, height: 1080))
        let plan = s.plan(showAspect: 16.0 / 10.0)
        XCTAssertTrue(plan.isLetterboxed)
        XCTAssertEqual(plan.picture.height, 1080)          // full height kept
        XCTAssertEqual(plan.picture.width, 1728)           // 1080 × 1.6
        XCTAssertEqual(plan.picture.midX, 960, accuracy: 1)
        XCTAssertEqual(plan.picture.midY, 540, accuracy: 1)
        XCTAssertLessThanOrEqual(plan.picture.maxX, 1920)
    }

    /// The other way round: a show wider than the frame keeps its full
    /// width and gets bars above and below.
    func testAWideShowLetterboxesInsideASquarerFrame() {
        let s = MovieExportSettings(size: CGSize(width: 1920, height: 1080))
        let plan = s.plan(showAspect: 2.35)
        XCTAssertTrue(plan.isLetterboxed)
        XCTAssertEqual(plan.picture.width, 1920)
        XCTAssertEqual(plan.picture.height, 816)           // 1920 / 2.35, even
        XCTAssertEqual(plan.picture.midY, 540, accuracy: 1)
    }

    func testATallerShowPillarboxesInsideAWideFrame() {
        let s = MovieExportSettings(size: CGSize(width: 1920, height: 1080))
        let plan = s.plan(showAspect: 1)             // a square show
        XCTAssertTrue(plan.isLetterboxed)
        XCTAssertEqual(plan.picture.height, 1080)
        XCTAssertEqual(plan.picture.width, 1080)
        XCTAssertEqual(plan.picture.midX, 960, accuracy: 1)
    }

    func testTheLetterboxedPictureIsItselfEvenAndInsideTheFrame() {
        for aspect in [16.0 / 10.0, 4.0 / 3.0, 1.0, 2.35, 0.75, 1.6] {
            for preset in MovieSizePreset.standard {
                let plan = MovieExportSettings(size: preset.size).plan(showAspect: aspect)
                XCTAssertEqual(plan.picture.width.truncatingRemainder(dividingBy: 2), 0)
                XCTAssertEqual(plan.picture.height.truncatingRemainder(dividingBy: 2), 0)
                XCTAssertLessThanOrEqual(plan.picture.maxX, plan.canvas.width)
                XCTAssertLessThanOrEqual(plan.picture.maxY, plan.canvas.height)
                XCTAssertGreaterThan(plan.picture.width, 0)
                XCTAssertGreaterThan(plan.picture.height, 0)
                // The whole picture is there: its shape is still the show's.
                XCTAssertEqual(plan.picture.width / plan.picture.height, aspect, accuracy: 0.01)
            }
        }
    }

    func testAnImpossibleAspectFallsBackToTheWholeFrame() {
        let s = MovieExportSettings(size: CGSize(width: 1920, height: 1080))
        for bad in [0, -1, CGFloat.nan] {
            let plan = s.plan(showAspect: bad)
            XCTAssertEqual(plan.picture, CGRect(origin: .zero, size: s.size))
        }
    }
}
