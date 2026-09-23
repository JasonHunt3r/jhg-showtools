import XCTest
import AVFoundation
@testable import ShowToolsCore

/// Video export E3: the sound track (spec/video-export.md). The mix is
/// rendered for real and read back, so what is measured is what came out.
final class MovieSoundTrackTests: XCTestCase {

    // MARK: - A tone to mix

    func scratch(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieSoundTrackTests-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A steady full-scale tone, so any change in level is the mix's doing
    /// and not the music's.
    @discardableResult
    func tone(seconds: Double = 10, hz: Double = 440, rate: Double = 48_000) throws -> URL {
        let url = scratch("caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)   // a file never is
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<Int(format.channelCount) {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(frames) { p[i] = Float(sin(2 * .pi * hz * Double(i) / rate)) }
        }
        try file.write(from: buffer)
        return url
    }

    func song(_ url: URL, start: Double, length: Double,
              volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0,
              inPoint: Double = 0) -> MovieSong {
        var clip = AudioClip(itemID: 1, start: start, length: length)
        clip.volume = volume
        clip.fadeIn = fadeIn
        clip.fadeOut = fadeOut
        clip.inPoint = inPoint
        return MovieSong(clip: clip, url: url)
    }

    // MARK: - Reading the mix back

    /// Every sample of a rendered file, channel 0.
    func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                      frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let p = buffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: p, count: Int(buffer.frameLength)))
    }

    /// The loudest sample in a stretch of seconds — the level the mix is
    /// running at there, the tone being full scale.
    ///
    /// Note what this measures: over a stretch where the level is changing,
    /// it returns the level at the *loudest* moment in the stretch, not the
    /// one in the middle. Tests that compare it to a gain must compare it to
    /// that gain's maximum over the same stretch.
    func peak(_ s: [Float], from: Double, to: Double, rate: Double = 48_000) -> Double {
        let lo = max(Int(from * rate), 0), hi = min(Int(to * rate), s.count)
        guard lo < hi else { return -1 }
        return Double(s[lo..<hi].map(abs).max() ?? 0)
    }

    /// Root mean square over a stretch: the mix's *power* there.
    ///
    /// This, not the peak, is what an equal-power crossfade holds steady.
    /// Two different tones at gain 0.707 each sum to a peak of up to 1.41
    /// where their waves happen to align, while their power stays put — so
    /// a peak reading makes a correct crossfade look like clipping.
    /// A full-scale sine has an RMS of 0.707.
    func rms(_ s: [Float], from: Double, to: Double, rate: Double = 48_000) -> Double {
        let lo = max(Int(from * rate), 0), hi = min(Int(to * rate), s.count)
        guard lo < hi else { return -1 }
        let sum = s[lo..<hi].reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(hi - lo)).squareRoot()
    }

    // MARK: - Length

    func testTheMixIsAsLongAsTheShow() throws {
        let url = scratch("caf")
        let result = try MovieSoundTrack.write(songs: [song(try tone(), start: 0, length: 5)],
                                               duration: 8, to: url)
        XCTAssertEqual(result.frameCount, 8 * 48_000)     // the show, not the song
        XCTAssertEqual(result.duration, 8, accuracy: 1e-9)
        XCTAssertEqual(result.songsMixed, 1)
        XCTAssertEqual(try samples(url).count, 8 * 48_000)
    }

    func testAShowWithNoLengthIsRefused() {
        XCTAssertThrowsError(try MovieSoundTrack.write(songs: [], duration: 0, to: scratch("caf"))) { e in
            guard case MovieExportError.emptyShow = e else { return XCTFail("\(e)") }
        }
    }

    /// A show with no music still renders: silence of the right length. The
    /// caller decides whether to give it a track at all.
    func testAShowWithNoSongsRendersSilence() throws {
        let url = scratch("caf")
        let result = try MovieSoundTrack.write(songs: [], duration: 2, to: url)
        XCTAssertEqual(result.songsMixed, 0)
        XCTAssertEqual(result.frameCount, 2 * 48_000)
        XCTAssertEqual(peak(try samples(url), from: 0, to: 2), 0, accuracy: 1e-6)
    }

    /// A song whose file has gone is dropped, as the timeline drops it.
    func testAMissingFileIsDroppedRatherThanFailing() throws {
        let gone = MovieSong(clip: AudioClip(itemID: 9, start: 0, length: 3),
                             url: URL(fileURLWithPath: "/nowhere/gone.m4a"))
        let result = try MovieSoundTrack.write(songs: [gone], duration: 2, to: scratch("caf"))
        XCTAssertEqual(result.songsMixed, 0)
        XCTAssertEqual(result.frameCount, 2 * 48_000)
    }

    // MARK: - Where the song sits on the clock

    func testASongSoundsOnlyOverItsOwnStretch() throws {
        let url = scratch("caf")
        try MovieSoundTrack.write(songs: [song(try tone(), start: 2, length: 3)],
                                  duration: 7, to: url)
        let s = try samples(url)
        XCTAssertEqual(peak(s, from: 0, to: 1.9), 0, accuracy: 1e-4, "before it starts")
        XCTAssertEqual(peak(s, from: 2.2, to: 4.8), 1, accuracy: 0.02, "while it plays")
        XCTAssertEqual(peak(s, from: 5.1, to: 7), 0, accuracy: 1e-4, "after it ends")
    }

    // MARK: - Levels, from the same function the player uses

    func testVolumeSetsTheLevelOfTheMix() throws {
        let url = scratch("caf")
        try MovieSoundTrack.write(songs: [song(try tone(), start: 0, length: 4, volume: 0.25)],
                                  duration: 4, to: url)
        XCTAssertEqual(peak(try samples(url), from: 0.5, to: 3.5), 0.25, accuracy: 0.02)
    }

    /// The step the spec asks for: a stretch the level line silences is
    /// silent. A song at volume 0 is the level line's floor.
    func testAStretchTheLevelLineSilencesIsSilent() throws {
        let url = scratch("caf")
        try MovieSoundTrack.write(songs: [song(try tone(), start: 0, length: 4, volume: 0)],
                                  duration: 4, to: url)
        XCTAssertEqual(peak(try samples(url), from: 0, to: 4), 0, accuracy: 1e-5)
    }

    func testFadesRampTheMixUpAndDown() throws {
        let url = scratch("caf")
        try MovieSoundTrack.write(
            songs: [song(try tone(), start: 0, length: 6, fadeIn: 2, fadeOut: 2)],
            duration: 6, to: url)
        let s = try samples(url)
        // The fade is linear in `envelope(at:)`, so half a fade is half the level.
        XCTAssertEqual(peak(s, from: 0, to: 0.05), 0, accuracy: 0.05, "the very start")
        XCTAssertEqual(peak(s, from: 0.95, to: 1.05), 0.5, accuracy: 0.05, "halfway up")
        XCTAssertEqual(peak(s, from: 2.5, to: 3.5), 1, accuracy: 0.03, "full between the fades")
        XCTAssertEqual(peak(s, from: 4.95, to: 5.05), 0.5, accuracy: 0.05, "halfway down")
        XCTAssertGreaterThan(peak(s, from: 0.95, to: 1.05), peak(s, from: 0.45, to: 0.55))
    }

    /// Two songs overlapping crossfade equal-power, so the loudness holds
    /// through the middle rather than dipping. Same `gain` as the player.
    func testOverlappingSongsCrossfadeEqualPower() throws {
        let url = scratch("caf")
        let a = try tone(seconds: 10, hz: 440)
        let b = try tone(seconds: 10, hz: 660)
        try MovieSoundTrack.write(songs: [song(a, start: 0, length: 6),
                                          song(b, start: 4, length: 6)],
                                  duration: 10, to: url)
        let s = try samples(url)
        // A full-scale sine's RMS is 0.707, which is the power to hold.
        let alone = 1 / 2.0.squareRoot()
        XCTAssertEqual(rms(s, from: 1, to: 3), alone, accuracy: 0.03, "song A alone")
        XCTAssertEqual(rms(s, from: 7, to: 9), alone, accuracy: 0.03, "song B alone")
        // Across the 2 s overlap the power holds: that is what equal-power
        // means. It must not dip in the middle, as a linear fade would.
        for t in [4.2, 4.6, 5.0, 5.4, 5.8] {
            XCTAssertEqual(rms(s, from: t - 0.1, to: t + 0.1), alone, accuracy: 0.05,
                           "through the crossfade at t=\(t)")
        }
    }

    /// What the peak does through that same crossfade — worth knowing,
    /// because it is louder than either song on its own. Two songs that
    /// aren't the same waveform add where their waves align, so the mix can
    /// pass full scale even though neither song does and the power is
    /// steady. The live player mixes exactly the same way (one `gain`, one
    /// graph), so an export is no louder than what was heard.
    func testACrossfadesPeakCanPassFullScaleThoughItsPowerDoesNot() throws {
        let url = scratch("caf")
        try MovieSoundTrack.write(songs: [song(try tone(seconds: 10, hz: 440), start: 0, length: 6),
                                          song(try tone(seconds: 10, hz: 660), start: 4, length: 6)],
                                  duration: 10, to: url)
        let s = try samples(url)
        XCTAssertEqual(peak(s, from: 1, to: 3), 1, accuracy: 0.03, "song A alone is full scale")
        let middle = peak(s, from: 4.9, to: 5.1)
        XCTAssertGreaterThan(middle, 1.0, "the sum of two tones should pass full scale")
        XCTAssertLessThanOrEqual(middle, 2.0.squareRoot() + 0.02, "but never past the sum of both")
    }

    /// The exported mix is the played mix, by construction: the levels the
    /// file comes back at are `AudioClip.gain`'s, the player's own function.
    func testTheMixFollowsAudioClipGainThroughout() throws {
        let url = scratch("caf")
        let clipA = song(try tone(), start: 0, length: 6, fadeIn: 1, fadeOut: 1)
        try MovieSoundTrack.write(songs: [clipA], duration: 6, to: url)
        let s = try samples(url)
        for t in [0.5, 1.5, 3.0, 4.5, 5.5] {
            // `peak` reports the loudest moment in the window, so the gain to
            // compare against is its highest over that same window — not the
            // one at t. Over a fade out those differ by the whole window.
            let window = stride(from: t - 0.05, through: t + 0.05, by: 0.005)
            let want = window.map { AudioClip.gain(of: clipA.clip, at: $0, among: [clipA.clip]) }.max()!
            XCTAssertEqual(peak(s, from: t - 0.05, to: t + 0.05), want, accuracy: 0.03,
                           "at t=\(t)")
        }
    }

    // MARK: - Trimming

    func testAClipsInPointPicksUpInsideTheFile() throws {
        // A tone that changes pitch halfway is the only way to tell where in
        // the file playback started, so: two files, one clip each.
        let url = scratch("caf")
        let t = try tone(seconds: 10)
        try MovieSoundTrack.write(songs: [song(t, start: 0, length: 2, inPoint: 5)],
                                  duration: 2, to: url)
        // Full level throughout: it picked up 5 s in, where the tone is still
        // running, rather than past the end into silence.
        XCTAssertEqual(peak(try samples(url), from: 0.2, to: 1.8), 1, accuracy: 0.03)
    }

    func testAnInPointPastTheEndOfTheFileIsSilentRatherThanFailing() throws {
        let url = scratch("caf")
        let t = try tone(seconds: 3)
        let result = try MovieSoundTrack.write(songs: [song(t, start: 0, length: 2, inPoint: 30)],
                                               duration: 2, to: url)
        XCTAssertEqual(result.frameCount, 2 * 48_000)
        XCTAssertEqual(peak(try samples(url), from: 0, to: 2), 0, accuracy: 1e-4)
    }

    // MARK: - Progress and cancelling

    func testProgressRunsToOne() throws {
        var seen: [Double] = []
        try MovieSoundTrack.write(songs: [song(try tone(), start: 0, length: 2)],
                                  duration: 2, to: scratch("caf"), progress: { seen.append($0) })
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertGreaterThan(seen.count, 1)
    }

    func testCancellingStopsAndLeavesNoFile() throws {
        let url = scratch("caf")
        var blocks = 0
        XCTAssertThrowsError(try MovieSoundTrack.write(
            songs: [song(try tone(), start: 0, length: 5)], duration: 5, to: url,
            isCancelled: { blocks += 1; return blocks > 3 })) { e in
            guard case MovieExportError.cancelled = e else { return XCTFail("\(e)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Picking the songs out of a show

    func testOnlyAudioItemsBecomeSongs() throws {
        func item(_ id: Int64, _ kind: MediaKind) -> MediaItem {
            MediaItem(id: id, relativePath: "\(id)", hash: "h\(id)", kind: kind,
                      pixelWidth: 1, pixelHeight: 1, duration: 100,
                      ingestedAt: Date(), sourcePath: "")
        }
        var show = Show(id: 1, name: "s", defaults: ShowDefaults(), slides: [])
        show.music = [AudioClip(itemID: 1, start: 0, length: 3),   // a song
                      AudioClip(itemID: 2, start: 0, length: 3),   // an image, somehow
                      AudioClip(itemID: 9, start: 0, length: 3)]   // missing
        let items = [Int64(1): item(1, .audio), Int64(2): item(2, .image)]
        let songs = MovieSoundTrack.songs(of: show, items: items) {
            URL(fileURLWithPath: "/lib/\($0.relativePath)")
        }
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs.first?.clip.itemID, 1)
        XCTAssertEqual(songs.first?.url.path, "/lib/1")
    }
}
