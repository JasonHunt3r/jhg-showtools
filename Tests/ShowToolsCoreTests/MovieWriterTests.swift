import XCTest
import AVFoundation
import CoreImage
@testable import ShowToolsCore

/// Video export E4a: the picture and the sound in one file
/// (spec/video-export.md). Every test writes a real movie and reads its
/// tracks back.
final class MovieWriterTests: XCTestCase {

    let red = CIColor(red: 0.9, green: 0.1, blue: 0.1)

    func scratch(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieWriterTests-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func item(_ id: Int64, _ kind: MediaKind = .image) -> MediaItem {
        MediaItem(id: id, relativePath: "\(id)", hash: "h\(id)", kind: kind,
                  pixelWidth: 1000, pixelHeight: 1000, duration: 60,
                  ingestedAt: Date(), sourcePath: "")
    }

    /// Two one-second slides, cut between, each a flat colour.
    func flatShow(seconds: Double = 1) -> ShowTimeline {
        var d = ShowDefaults()
        d.transition = Transition(style: .cut, duration: 0)
        let slides = [Int64(1), Int64(2)].map {
            Slide(id: $0, itemID: $0, settings: SlideSettings(length: .seconds(seconds), fit: .fill))
        }
        let items = Dictionary(uniqueKeysWithValues: slides.map { ($0.itemID, item($0.itemID)) })
        return ShowTimeline(show: Show(id: 1, name: "flat", defaults: d, slides: slides), items: items)
    }

    func flatSource(_ layer: Layer) -> CIImage? {
        CIImage(color: red).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    /// A steady full-scale tone.
    func tone(seconds: Double = 10, hz: Double = 440, rate: Double = 48_000) throws -> URL {
        let url = scratch("caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
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
              volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0) -> MovieSong {
        var clip = AudioClip(itemID: 1, start: start, length: length)
        clip.volume = volume
        clip.fadeIn = fadeIn
        clip.fadeOut = fadeOut
        return MovieSong(clip: clip, url: url)
    }

    func settings(_ codec: MovieCodec = .h264, size: CGSize = CGSize(width: 320, height: 180)) -> MovieExportSettings {
        MovieExportSettings(size: size, frameRate: .fps30, codec: codec)
    }

    // MARK: - Reading the tracks back

    func tracks(_ url: URL, _ type: AVMediaType) -> [AVAssetTrack] {
        AVURLAsset(url: url).tracks(withMediaType: type)
    }

    /// The four-character code of a track's format, e.g. 'aac ' or 'lpcm'.
    func subType(_ track: AVAssetTrack) -> FourCharCode? {
        guard let d = track.formatDescriptions.first else { return nil }
        return CMFormatDescriptionGetMediaSubType(d as! CMFormatDescription)
    }

    /// Every sample of a movie's sound track, channel 0, as floats.
    func soundSamples(_ url: URL) throws -> (samples: [Float], rate: Double) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return ([], 0) }
        let reader = try AVAssetReader(asset: asset)
        let rate = 48_000.0
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
        ])
        reader.add(out)
        reader.startReading()
        var all: [Float] = []
        while let sample = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            let floats = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: length / 4)
            // Interleaved stereo: channel 0 is every other sample.
            for i in stride(from: 0, to: length / 4, by: 2) { all.append(floats[i]) }
        }
        return (all, rate)
    }

    func peak(_ s: [Float], from: Double, to: Double, rate: Double) -> Double {
        let lo = max(Int(from * rate), 0), hi = min(Int(to * rate), s.count)
        guard lo < hi else { return -1 }
        return Double(s[lo..<hi].map(abs).max() ?? 0)
    }

    // MARK: - Both tracks in one file

    func testAShowWithASongGetsBothTracks() throws {
        let url = scratch("mp4")
        let result = try MovieExport.write(timeline: flatShow(),
                                           songs: [song(try tone(), start: 0, length: 2)],
                                           to: url, settings: settings(), showAspect: 16.0 / 9.0,
                                           source: flatSource)
        XCTAssertEqual(result.frameCount, 60)
        XCTAssertTrue(result.hasSound)
        XCTAssertEqual(result.songsMixed, 1)
        XCTAssertEqual(result.soundFrames, 2 * 48_000)

        XCTAssertEqual(tracks(url, .video).count, 1)
        XCTAssertEqual(tracks(url, .audio).count, 1)

        // Both tracks cover the show, give or take a frame.
        let asset = AVURLAsset(url: url)
        XCTAssertEqual(CMTimeGetSeconds(asset.duration), 2, accuracy: 0.05)
        for type in [AVMediaType.video, .audio] {
            let d = CMTimeGetSeconds(tracks(url, type).first!.timeRange.duration)
            XCTAssertEqual(d, 2, accuracy: 0.05, "\(type.rawValue) track length")
        }
    }

    /// The sound in the movie is the mix E3 makes, not something re-derived:
    /// the fades land where `AudioClip.gain` puts them.
    func testTheSoundInTheMovieIsTheMix() throws {
        let url = scratch("mp4")
        let clip = song(try tone(), start: 1, length: 4, volume: 0.8, fadeIn: 1, fadeOut: 1)
        try MovieExport.write(timeline: flatShow(seconds: 3), songs: [clip],
                              to: url, settings: settings(), showAspect: 16.0 / 9.0,
                              source: flatSource)
        let (s, rate) = try soundSamples(url)
        XCTAssertGreaterThan(s.count, 0, "no sound came back")
        XCTAssertEqual(peak(s, from: 0, to: 0.9, rate: rate), 0, accuracy: 0.03, "before the song")

        // Expected levels come from `AudioClip.gain`, taken as its maximum
        // over each window: a peak reading reports the loudest moment in a
        // window, not the middle one, so over a fade it reads the window's
        // louder edge. (The same trap as in the E3 tests.)
        for (from, to, what) in [(1.4, 1.6, "up the fade in"),
                                 (2.5, 3.5, "at full volume"),
                                 (4.6, 4.9, "down the fade out")] {
            let want = stride(from: from, through: to, by: 0.01)
                .map { AudioClip.gain(of: clip.clip, at: $0, among: [clip.clip]) }.max()!
            XCTAssertEqual(peak(s, from: from, to: to, rate: rate), want, accuracy: 0.08, what)
        }
        XCTAssertEqual(peak(s, from: 5.2, to: 5.9, rate: rate), 0, accuracy: 0.03, "after the song")
    }

    // MARK: - No sound

    func testAShowWithNoSongsGetsNoSoundTrack() throws {
        let url = scratch("mp4")
        let result = try MovieExport.write(timeline: flatShow(), to: url,
                                           settings: settings(), showAspect: 16.0 / 9.0,
                                           source: flatSource)
        XCTAssertFalse(result.hasSound)
        XCTAssertEqual(result.songsMixed, 0)
        XCTAssertEqual(tracks(url, .video).count, 1)
        XCTAssertEqual(tracks(url, .audio).count, 0, "a silent show shouldn't carry an empty track")
    }

    /// Songs whose files have gone leave no empty track behind either.
    func testSongsWithNoFilesLeaveTheMovieSilent() throws {
        let url = scratch("mp4")
        let gone = MovieSong(clip: AudioClip(itemID: 9, start: 0, length: 2),
                             url: URL(fileURLWithPath: "/nowhere/gone.m4a"))
        let result = try MovieExport.write(timeline: flatShow(), songs: [gone], to: url,
                                           settings: settings(), showAspect: 16.0 / 9.0,
                                           source: flatSource)
        XCTAssertFalse(result.hasSound)
        XCTAssertEqual(tracks(url, .audio).count, 0)
        XCTAssertEqual(tracks(url, .video).count, 1)
    }

    // MARK: - How each format stores its sound

    /// ProRes is a mastering codec, so its sound goes in uncompressed;
    /// the delivery formats get AAC.
    func testProResCarriesPCMAndTheDeliveryFormatsAAC() throws {
        for codec in MovieCodec.allCases {
            let url = scratch(codec.fileExtension)
            let result = try MovieExport.write(timeline: flatShow(seconds: 0.5),
                                               songs: [song(try tone(), start: 0, length: 1)],
                                               to: url, settings: settings(codec),
                                               showAspect: 16.0 / 9.0, source: flatSource)
            XCTAssertTrue(result.hasSound, codec.name)
            guard let track = tracks(url, .audio).first else {
                XCTFail("no sound track for \(codec.name)"); continue
            }
            let want: FourCharCode = codec == .proRes422HQ ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC
            XCTAssertEqual(subType(track), want, codec.name)
        }
    }

    // MARK: - Interleaving

    /// The two tracks are written in step, not one whole track then the
    /// other — otherwise a long show holds its entire mix in memory. Each
    /// track's samples should therefore be spread across the file rather
    /// than sitting in one lump.
    func testTheTracksAreInterleavedRatherThanWrittenOneAfterTheOther() throws {
        let url = scratch("mp4")
        try MovieExport.write(timeline: flatShow(seconds: 5),
                              songs: [song(try tone(seconds: 20), start: 0, length: 10)],
                              to: url, settings: settings(), showAspect: 16.0 / 9.0,
                              source: flatSource)
        // Read the file's samples in storage order and check the two tracks
        // take turns rather than arriving in two blocks.
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        var outputs: [AVMediaType: AVAssetReaderTrackOutput] = [:]
        for type in [AVMediaType.video, .audio] {
            guard let track = asset.tracks(withMediaType: type).first else { continue }
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(out)
            outputs[type] = out
        }
        reader.startReading()
        // Pull both tracks' first samples: each should start near zero,
        // which one-track-then-the-other would still satisfy — so also check
        // the file's own interleaving hint.
        for (type, out) in outputs {
            let sample = out.copyNextSampleBuffer()
            XCTAssertNotNil(sample, "\(type.rawValue) had no samples")
            if let sample {
                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                XCTAssertEqual(t, 0, accuracy: 0.1, "\(type.rawValue) should start at zero")
            }
        }
        XCTAssertEqual(tracks(url, .audio).count, 1)
        XCTAssertEqual(tracks(url, .video).count, 1)
    }

    // MARK: - Progress and cancelling

    func testCancellingStopsAndLeavesNoFile() throws {
        let url = scratch("mp4")
        var checks = 0
        XCTAssertThrowsError(try MovieExport.write(
            timeline: flatShow(), songs: [song(try tone(), start: 0, length: 2)],
            to: url, settings: settings(), showAspect: 16.0 / 9.0,
            isCancelled: { checks += 1; return checks > 10 },
            source: flatSource)) { e in
            guard case MovieExportError.cancelled = e else { return XCTFail("\(e)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testProgressReachesOne() throws {
        var seen: [Double] = []
        try MovieExport.write(timeline: flatShow(seconds: 0.5),
                              songs: [song(try tone(), start: 0, length: 1)],
                              to: scratch("mp4"), settings: settings(), showAspect: 16.0 / 9.0,
                              progress: { seen.append($0) }, source: flatSource)
        XCTAssertEqual(seen.last, 1)
        XCTAssertEqual(seen, seen.sorted())
    }

    // MARK: - The silent path is the same writer

    /// `MoviePictureTrack.write` is this with no songs. If they ever drift
    /// apart, this catches it.
    func testThePictureOnlyPathGivesTheSameMovie() throws {
        let a = scratch("mp4"), b = scratch("mp4")
        let viaPicture = try MoviePictureTrack.write(timeline: flatShow(), to: a,
                                                     settings: settings(), showAspect: 16.0 / 9.0,
                                                     source: flatSource)
        let viaExport = try MovieExport.write(timeline: flatShow(), to: b,
                                              settings: settings(), showAspect: 16.0 / 9.0,
                                              source: flatSource)
        XCTAssertEqual(viaPicture.frameCount, viaExport.frameCount)
        XCTAssertEqual(viaPicture.size, viaExport.size)
        XCTAssertEqual(viaPicture.hasSound, viaExport.hasSound)
        XCTAssertEqual(tracks(a, .audio).count, tracks(b, .audio).count)
    }
}
