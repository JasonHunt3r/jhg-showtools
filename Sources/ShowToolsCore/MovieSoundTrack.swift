import Foundation
import AVFoundation

// Video export (plan, `spec/video-export.md`). E3: the sound track.
//
// The same graph the live `MusicPlayer` builds — one player node per song
// into the main mixer, each node's volume set from `AudioClip.gain` — but
// on an engine in manual rendering mode, pulled as fast as it will go
// instead of in real time.
//
// **One source for levels stays one source.** Volume, fades and the
// equal-power crossfade all come from `AudioClip.gain(of:at:among:)`, the
// function the player uses, so an exported mix is by construction what was
// heard. Nothing here re-implements a fade.

/// A song to mix: its clip (timing, volume, fades) and where its file is.
public struct MovieSong: Sendable {
    public var clip: AudioClip
    public var url: URL

    public init(clip: AudioClip, url: URL) {
        self.clip = clip
        self.url = url
    }
}

public struct MovieSoundResult: Hashable, Sendable {
    public var frameCount: AVAudioFramePosition
    public var sampleRate: Double
    public var channels: Int
    /// How many of the songs asked for actually opened.
    public var songsMixed: Int
    /// How many video slides contributed their own sound (E5b).
    public var videoSlidesMixed: Int = 0

    public var duration: Double { sampleRate > 0 ? Double(frameCount) / sampleRate : 0 }
}

/// The mix, a block at a time, pulled rather than pushed.
///
/// The muxer (E4) needs to take audio only when the writer asks for it, in
/// step with the picture, so the render loop can't own the calling thread.
/// `MovieSoundTrack.render` is a loop over this; both go through the same
/// engine, the same scheduling and the same `AudioClip.gain`.
///
/// **Not thread-safe, and off the main thread** — one renderer, one thread.
public final class MovieSoundRenderer {
    /// One block of the mix, and where it belongs on the show's clock.
    public struct Block {
        public var buffer: AVAudioPCMBuffer
        /// The frame this block starts at, from the top of the show.
        public var frame: AVAudioFramePosition
        public var time: Double
    }

    private let engine = AVAudioEngine()
    private let players: [(node: AVAudioPlayerNode, song: MovieSong, file: AVAudioFile)]
    private let clips: [AudioClip]
    private let buffer: AVAudioPCMBuffer
    private let total: AVAudioFramePosition
    private let blockFrames: AVAudioFrameCount

    public let format: AVAudioFormat
    public private(set) var framesRendered: AVAudioFramePosition = 0
    /// How many video slides put their own sound in the mix.
    public private(set) var videoSlidesMixed = 0
    private var finished = false

    public var progress: Double { total > 0 ? min(Double(framesRendered) / Double(total), 1) : 1 }

    public var result: MovieSoundResult {
        MovieSoundResult(frameCount: framesRendered, sampleRate: format.sampleRate,
                         channels: Int(format.channelCount), songsMixed: players.count,
                         videoSlidesMixed: videoSlidesMixed)
    }

    public init(songs: [MovieSong], videos: [MovieVideoSound] = [], duration: Double,
                format: AVAudioFormat = MovieSoundTrack.format(),
                blockFrames: AVAudioFrameCount = 1024) throws {
        let rate = format.sampleRate
        total = AVAudioFramePosition((duration * rate).rounded())
        guard total > 0 else { throw MovieExportError.emptyShow }
        self.format = format
        self.blockFrames = blockFrames
        clips = songs.map(\.clip)

        // Touching mainMixerNode builds it; it must exist before the format
        // is fixed by enableManualRenderingMode.
        let mixer = engine.mainMixerNode
        var built: [(AVAudioPlayerNode, MovieSong, AVAudioFile)] = []
        for song in songs {
            guard let file = try? AVAudioFile(forReading: song.url) else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: file.processingFormat)
            built.append((node, song, file))
        }
        players = built

        // Video slides' own sound (E5b). Their level line is already baked
        // into the samples, so these nodes play at 1 — one curve, applied
        // once. A slide whose line is at the floor never gets here.
        var videoBuffers: [(node: AVAudioPlayerNode, buffer: AVAudioPCMBuffer, start: Double)] = []
        for slide in videos {
            guard let buffer = try? MovieVideoAudio.buffer(for: slide, format: format) else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: format)
            videoBuffers.append((node, buffer, slide.start))
        }
        videoSlidesMixed = videoBuffers.count

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
        do { try engine.start() } catch {
            throw MovieExportError.writerFailed("the offline audio engine wouldn't start: \(error.localizedDescription)")
        }

        // Schedule each song where it sits on the show's clock. The frame
        // positions inside the file are in the file's own rate; the time it
        // starts is in the render format's.
        for p in players {
            let fileRate = p.file.processingFormat.sampleRate
            let first = AVAudioFramePosition(p.song.clip.inPoint * fileRate)
            guard first < p.file.length else { continue }
            let wanted = AVAudioFramePosition(p.song.clip.length * fileRate)
            let count = min(wanted, p.file.length - first)
            guard count > 0 else { continue }
            let at = AVAudioTime(sampleTime: AVAudioFramePosition(max(p.song.clip.start, 0) * rate), atRate: rate)
            p.node.scheduleSegment(p.file, startingFrame: first,
                                   frameCount: AVAudioFrameCount(count), at: at)
            p.node.play()
        }

        for v in videoBuffers {
            let at = AVAudioTime(sampleTime: AVAudioFramePosition(max(v.start, 0) * rate), atRate: rate)
            v.node.scheduleBuffer(v.buffer, at: at, options: [])
            v.node.volume = 1
            v.node.play()
        }

        guard let b = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                       frameCapacity: blockFrames) else {
            throw MovieExportError.noPixelBuffer
        }
        buffer = b
    }

    deinit {
        engine.stop()
        engine.disableManualRenderingMode()
    }

    /// The next block, or nil once the show's length has been rendered.
    /// The buffer is reused, so a caller that keeps one must copy it.
    public func next() throws -> Block? {
        guard !finished, framesRendered < total else { finish(); return nil }

        // The levels for this block, from the one shared function.
        let at = framesRendered
        let t = Double(at) / format.sampleRate
        for p in players {
            p.node.volume = Float(AudioClip.gain(of: p.song.clip, at: t, among: clips))
        }

        let n = AVAudioFrameCount(min(AVAudioFramePosition(blockFrames), total - at))
        switch try engine.renderOffline(n, to: buffer) {
        case .success:
            framesRendered += AVAudioFramePosition(buffer.frameLength)
            return Block(buffer: buffer, frame: at, time: t)
        case .insufficientDataFromInputNode:
            // No live input here; nothing more is coming.
            framesRendered = total
            finish()
            return nil
        case .cannotDoInCurrentContext, .error:
            throw MovieExportError.writerFailed("the offline audio engine stopped after \(at) frames")
        @unknown default:
            throw MovieExportError.writerFailed("the offline audio engine returned an unknown status")
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        engine.stop()
    }
}

public enum MovieSoundTrack {

    /// The mix's format. 48 kHz stereo: what the video containers expect,
    /// and what every encoder here takes without resampling twice.
    public static func format(sampleRate: Double = 48_000) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    /// The songs of a show, paired with their files. Clips whose file is
    /// missing from the library are dropped, exactly as the timeline drops
    /// them when working out the show's length.
    public static func songs(of show: Show, items: [Int64: MediaItem],
                             url: (MediaItem) -> URL) -> [MovieSong] {
        show.music.compactMap { clip in
            guard let item = items[clip.itemID], item.kind == .audio else { return nil }
            return MovieSong(clip: clip, url: url(item))
        }
    }

    /// Mixes the show's music offline, handing each block of samples to
    /// `receive` as it comes out.
    ///
    /// **Call this off the main thread** — like the picture track, it runs
    /// straight through. Levels are set once per block (about 21 ms at the
    /// default), finer than the live player's 60 Hz timer.
    ///
    /// With no songs it renders silence for the show's length, which is a
    /// real answer: the caller decides whether a silent show gets a sound
    /// track at all.
    @discardableResult
    public static func render(songs: [MovieSong],
                              videos: [MovieVideoSound] = [],
                              duration: Double,
                              format: AVAudioFormat = MovieSoundTrack.format(),
                              blockFrames: AVAudioFrameCount = 1024,
                              progress: ((Double) -> Void)? = nil,
                              isCancelled: (() -> Bool)? = nil,
                              receive: (AVAudioPCMBuffer) throws -> Void) throws -> MovieSoundResult {
        let renderer = try MovieSoundRenderer(songs: songs, videos: videos, duration: duration,
                                              format: format, blockFrames: blockFrames)
        while let block = try renderer.next() {
            if isCancelled?() == true { throw MovieExportError.cancelled }
            try receive(block.buffer)
            progress?(renderer.progress)
        }
        return renderer.result
    }

    /// The mix as a standalone audio file. `stcli` uses it, and it is how
    /// the tests listen to what came out.
    @discardableResult
    public static func write(songs: [MovieSong],
                             videos: [MovieVideoSound] = [],
                             duration: Double,
                             to url: URL,
                             format: AVAudioFormat = MovieSoundTrack.format(),
                             progress: ((Double) -> Void)? = nil,
                             isCancelled: (() -> Bool)? = nil) throws -> MovieSoundResult {
        try? FileManager.default.removeItem(at: url)
        // The engine's buffers are non-interleaved, but a file on disk never
        // is: passing that key straight through only earns a warning.
        var settings = format.settings
        settings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        do {
            return try render(songs: songs, videos: videos, duration: duration, format: format,
                              progress: progress, isCancelled: isCancelled) { buffer in
                try file.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
