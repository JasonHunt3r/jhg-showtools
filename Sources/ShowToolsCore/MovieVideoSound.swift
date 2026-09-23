import Foundation
import AVFoundation

// Video export (plan, `spec/video-export.md`). E5b: a video slide's own
// sound, mixed with the music.
//
// The live player sets `VideoSlot.volume` from the slide's `LevelCurve`
// each drawn frame (`spec/video-audio.md`). An export can't reach
// AVPlayer's audio, so it reads the slide's audio itself and applies the
// same curve — per sample rather than per frame, which is finer, not
// different.
//
// A video's audio can't be opened with `AVAudioFile`, so it comes out
// through an `AVAssetReader`, laid out along the slide's span by
// `VideoSlideTiming` so it loops and stops exactly where the picture does.

/// A video slide whose sound should go in the mix.
public struct MovieVideoSound: Sendable {
    public var slideID: Int64
    public var url: URL
    /// Where the slide starts on the show's clock.
    public var start: Double
    public var length: Double
    public var clipStart: Double
    /// The slide's own level line. Empty means silent, which is what a new
    /// video slide is (settled with Jason: dropping a clip into a show set
    /// to music must never suddenly blast its original audio).
    public var curve: LevelCurve

    public init(slideID: Int64, url: URL, start: Double, length: Double,
                clipStart: Double, curve: LevelCurve) {
        self.slideID = slideID
        self.url = url
        self.start = start
        self.length = length
        self.clipStart = clipStart
        self.curve = curve
    }

    /// Nothing to mix when the line never leaves the floor.
    public var isSilent: Bool { curve.isEmpty }

    /// The video slides of a show that have their sound turned up at all.
    public static func all(of show: Show, items: [Int64: MediaItem],
                           url: (MediaItem) -> URL?) -> [MovieVideoSound] {
        let timeline = ShowTimeline(show: show, items: items)
        return timeline.slides.compactMap { slide in
            guard slide.item.kind == .video, !slide.audio.isEmpty,
                  let u = url(slide.item) else { return nil }
            return MovieVideoSound(slideID: slide.slide.id, url: u, start: slide.start,
                                   length: slide.length, clipStart: slide.clipStart,
                                   curve: slide.audio)
        }
    }
}

public enum MovieVideoAudio {

    /// A video slide's sound, laid out along the slide and shaped by its
    /// level line — ready to drop into the mix at the slide's start.
    ///
    /// Returns nil when the file has no sound, or the line is at the floor
    /// throughout.
    ///
    /// The whole of the file's audio is decoded first, so a very long video
    /// slide costs memory in proportion to its file. Fine for slides;
    /// worth revisiting if whole films ever become slides.
    public static func buffer(for slide: MovieVideoSound,
                              format: AVAudioFormat) throws -> AVAudioPCMBuffer? {
        guard !slide.isSilent, slide.length > 0 else { return nil }
        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        guard let source = try decode(slide.url, format: format) else { return nil }
        let sourceFrames = source.count / channels
        guard sourceFrames > 0 else { return nil }

        let duration = Double(sourceFrames) / rate
        let frames = AVAudioFrameCount((slide.length * rate).rounded())
        guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        out.frameLength = frames
        guard let channelData = out.floatChannelData else { return nil }
        for c in 0..<channels { channelData[c].update(repeating: 0, count: Int(frames)) }

        for i in 0..<Int(frames) {
            let localTime = Double(i) / rate
            let level = Float(slide.curve.level(at: localTime))
            if level <= 0 { continue }
            // Where in the file this instant is — the same function the
            // picture asks, so sound and picture loop together.
            let at = VideoSlideTiming.position(localTime: localTime, slideLength: slide.length,
                                               clipStart: slide.clipStart, duration: duration)
            // Past the end of the video, the picture holds its last frame
            // and the sound stops: a held frame isn't a held note.
            if at.holding && !at.loops { continue }
            let index = Int(at.time * rate)
            guard index >= 0, index < sourceFrames else { continue }
            for c in 0..<channels {
                channelData[c][i] = source[index * channels + c] * level
            }
        }
        return out
    }

    /// Every sample of a file's sound track, interleaved, in `format`'s
    /// rate and channel count.
    static func decode(_ url: URL, format: AVAudioFormat) throws -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length,
                                              dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            let floats = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: length / 4)
            samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: length / 4))
        }
        return samples.isEmpty ? nil : samples
    }
}
