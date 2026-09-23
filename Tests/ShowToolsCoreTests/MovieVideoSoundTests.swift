import XCTest
import AVFoundation
import CoreImage
@testable import ShowToolsCore

/// Video export E5b: a video slide's own sound (spec/video-export.md,
/// spec/video-audio.md). The level line is the control, and it starts at
/// the floor — a clip dropped into a show set to music must never suddenly
/// blast its own audio.
final class MovieVideoSoundTests: XCTestCase {

    let format = MovieSoundTrack.format()

    func scratch(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieVideoSoundTests-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A movie with a picture and a full-scale tone, so any level in the
    /// mix is the level line's doing.
    func makeVideo(seconds: Double = 4) throws -> URL {
        let url = scratch("mp4")
        let size = CGSize(width: 160, height: 120)
        let item = MediaItem(id: 1, relativePath: "1", hash: "h1", kind: .image,
                             pixelWidth: 100, pixelHeight: 100, duration: nil,
                             ingestedAt: Date(), sourcePath: "")
        var show = Show(id: 1, name: "v", defaults: ShowDefaults(), slides: [])
        show.defaults.transition = Transition(style: .cut, duration: 0)
        show.slides = [Slide(id: 1, itemID: 1, settings: SlideSettings(length: .seconds(seconds), fit: .fill))]
        let timeline = ShowTimeline(show: show, items: [1: item])

        // A tone as the movie's sound: a song clip at full volume.
        let tone = scratch("caf")
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        let file = try AVAudioFile(forWriting: tone, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<Int(format.channelCount) {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(frames) { p[i] = Float(sin(2 * .pi * 440 * Double(i) / format.sampleRate)) }
        }
        try file.write(from: buffer)

        var clip = AudioClip(itemID: 2, start: 0, length: seconds)
        clip.volume = 1
        try MovieExport.write(
            timeline: timeline, songs: [MovieSong(clip: clip, url: tone)], to: url,
            settings: MovieExportSettings(size: size, frameRate: .fps30),
            showAspect: size.width / size.height) { _ in
                CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                    .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            }
        return url
    }

    func slide(_ url: URL, start: Double = 0, length: Double = 4,
               clipStart: Double = 0, curve: LevelCurve) -> MovieVideoSound {
        MovieVideoSound(slideID: 1, url: url, start: start, length: length,
                        clipStart: clipStart, curve: curve)
    }

    func peak(_ b: AVAudioPCMBuffer, from: Double, to: Double) -> Double {
        let rate = b.format.sampleRate
        let lo = max(Int(from * rate), 0), hi = min(Int(to * rate), Int(b.frameLength))
        guard lo < hi, let p = b.floatChannelData?[0] else { return -1 }
        var m = 0.0
        for i in lo..<hi { m = max(m, Double(abs(p[i]))) }
        return m
    }

    // MARK: - Silent by default

    /// The decision from `spec/video-audio.md`: a new video slide is
    /// silent, so an export must not bring its original audio in uninvited.
    func testAVideoSlideWithNoLevelLineContributesNothing() throws {
        let url = try makeVideo()
        let s = slide(url, curve: LevelCurve())
        XCTAssertTrue(s.isSilent)
        XCTAssertNil(try MovieVideoAudio.buffer(for: s, format: format))
    }

    func testAShowsVideoSlidesAreOnlyGatheredWhenTurnedUp() throws {
        let url = try makeVideo()
        let item = MediaItem(id: 1, relativePath: "v.mp4", hash: "hv", kind: .video,
                             pixelWidth: 160, pixelHeight: 120, duration: 4,
                             ingestedAt: Date(), sourcePath: "")
        var silent = SlideSettings(length: .seconds(4))
        var loud = SlideSettings(length: .seconds(4))
        loud.audio = LevelCurve(points: [LevelPoint(time: 0, level: 0.8)])

        var show = Show(id: 1, name: "s", defaults: ShowDefaults(), slides: [])
        show.slides = [Slide(id: 1, itemID: 1, settings: silent),
                       Slide(id: 2, itemID: 1, settings: loud)]
        let found = MovieVideoSound.all(of: show, items: [1: item]) { _ in url }
        XCTAssertEqual(found.count, 1, "only the slide with a level line")
        XCTAssertEqual(found.first?.slideID, 2)

        // And nothing at all when none are turned up.
        silent.audio = nil
        show.slides = [Slide(id: 1, itemID: 1, settings: silent)]
        XCTAssertTrue(MovieVideoSound.all(of: show, items: [1: item]) { _ in url }.isEmpty)
    }

    // MARK: - The level line is the level

    func testTheLevelLineSetsTheLevel() throws {
        let url = try makeVideo()
        let s = slide(url, curve: LevelCurve(points: [LevelPoint(time: 0, level: 0.5)]))
        let b = try XCTUnwrap(try MovieVideoAudio.buffer(for: s, format: format))
        XCTAssertEqual(b.frameLength, AVAudioFrameCount(4 * format.sampleRate))
        XCTAssertEqual(peak(b, from: 0.5, to: 3.5), 0.5, accuracy: 0.05)
    }

    /// The point of the feature: keep the part where someone speaks, drop
    /// the part where the dogs bark.
    func testAStretchTheLineDropsIsSilentAndTheRestIsNot() throws {
        let url = try makeVideo()
        // Up for the first second, down for the second, up again after.
        let curve = LevelCurve(points: [LevelPoint(time: 0, level: 1),
                                        LevelPoint(time: 1, level: 1),
                                        LevelPoint(time: 1.2, level: 0),
                                        LevelPoint(time: 2.3, level: 0),
                                        LevelPoint(time: 2.5, level: 1)])
        let s = slide(url, curve: curve)
        let b = try XCTUnwrap(try MovieVideoAudio.buffer(for: s, format: format))
        XCTAssertEqual(peak(b, from: 0.2, to: 0.9), 1, accuracy: 0.05, "kept")
        XCTAssertEqual(peak(b, from: 1.4, to: 2.2), 0, accuracy: 0.02, "dropped")
        XCTAssertEqual(peak(b, from: 2.7, to: 3.8), 1, accuracy: 0.05, "kept again")
    }

    func testClipStartPicksUpInsideTheVideo() throws {
        let url = try makeVideo(seconds: 4)
        let s = slide(url, length: 1, clipStart: 2,
                      curve: LevelCurve(points: [LevelPoint(time: 0, level: 1)]))
        let b = try XCTUnwrap(try MovieVideoAudio.buffer(for: s, format: format))
        XCTAssertEqual(b.frameLength, AVAudioFrameCount(format.sampleRate))
        XCTAssertEqual(peak(b, from: 0.1, to: 0.9), 1, accuracy: 0.05)
    }

    /// Sound follows the picture's own rule: a slide held longer than its
    /// video loops, and so does what you hear.
    func testALongSlideLoopsItsSoundWithItsPicture() throws {
        let url = try makeVideo(seconds: 4)
        let s = slide(url, length: 10, curve: LevelCurve(points: [LevelPoint(time: 0, level: 1)]))
        let b = try XCTUnwrap(try MovieVideoAudio.buffer(for: s, format: format))
        XCTAssertEqual(b.frameLength, AVAudioFrameCount(10 * format.sampleRate))
        // Still sounding well past the video's own 4s, because it loops.
        XCTAssertEqual(peak(b, from: 5, to: 6), 1, accuracy: 0.05, "the second pass")
        XCTAssertEqual(peak(b, from: 8.5, to: 9.5), 1, accuracy: 0.05, "the third")
    }

    /// Held past the end without looping, the picture freezes — a held
    /// frame isn't a held note, so the sound stops.
    func testHeldPastTheEndTheSoundStopsEvenThoughThePictureHolds() throws {
        let url = try makeVideo(seconds: 4)
        // 4.05 s is inside the 0.1 s tolerance, so it holds rather than loops.
        let s = slide(url, length: 4.05, curve: LevelCurve(points: [LevelPoint(time: 0, level: 1)]))
        let b = try XCTUnwrap(try MovieVideoAudio.buffer(for: s, format: format))
        XCTAssertEqual(peak(b, from: 1, to: 3.5), 1, accuracy: 0.05, "while the video runs")
        XCTAssertEqual(peak(b, from: 4.0, to: 4.05), 0, accuracy: 0.02, "after it ends")
    }

    func testAVideoWithNoSoundTrackGivesNothing() throws {
        // A movie written with no songs has no audio track at all.
        let url = scratch("mp4")
        let item = MediaItem(id: 1, relativePath: "1", hash: "h1", kind: .image,
                             pixelWidth: 100, pixelHeight: 100, duration: nil,
                             ingestedAt: Date(), sourcePath: "")
        var show = Show(id: 1, name: "v", defaults: ShowDefaults(), slides: [])
        show.slides = [Slide(id: 1, itemID: 1, settings: SlideSettings(length: .seconds(2), fit: .fill))]
        try MovieExport.write(
            timeline: ShowTimeline(show: show, items: [1: item]), to: url,
            settings: MovieExportSettings(size: CGSize(width: 160, height: 120)),
            showAspect: 4.0 / 3.0) { _ in CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50)) }

        let s = slide(url, length: 2, curve: LevelCurve(points: [LevelPoint(time: 0, level: 1)]))
        XCTAssertNil(try MovieVideoAudio.buffer(for: s, format: format))
    }

    // MARK: - In the mix, beside the music

    /// A straight mix, each at its own level — no ducking (settled with
    /// Jason). A show with only a video slide's sound still gets a track.
    func testAVideoSlidesSoundReachesTheMixOnItsOwn() throws {
        let url = try makeVideo()
        let out = scratch("caf")
        let s = slide(url, start: 1, length: 3,
                      curve: LevelCurve(points: [LevelPoint(time: 0, level: 0.6)]))
        let result = try MovieSoundTrack.write(songs: [], videos: [s], duration: 6, to: out)
        XCTAssertEqual(result.videoSlidesMixed, 1)
        XCTAssertEqual(result.songsMixed, 0)

        let file = try AVAudioFile(forReading: out)
        let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                 frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: b)
        XCTAssertEqual(peak(b, from: 0, to: 0.9), 0, accuracy: 0.02, "before the slide")
        XCTAssertEqual(peak(b, from: 1.5, to: 3.5), 0.6, accuracy: 0.06, "while it plays")
        XCTAssertEqual(peak(b, from: 4.3, to: 6), 0, accuracy: 0.02, "after it ends")
    }
}
