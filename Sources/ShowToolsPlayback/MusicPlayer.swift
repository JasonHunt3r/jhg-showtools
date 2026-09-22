import AVFoundation
import ShowToolsCore

/// Plays a show's songs, and while it does, is the show's clock (plan:
/// "time comes from the music when a track is loaded"). Everything that
/// should sound from one moment on is scheduled at once, on one audio
/// engine, to start together; the time since then is read back from the
/// sound card's own sample count, so the picture follows what you hear
/// rather than the other way round.
@MainActor
public final class MusicPlayer {
    /// One song's part of a play: from `fileStart` seconds into the file,
    /// for `duration`, starting `delay` seconds after the play starts.
    public struct Segment {
        let clipID: UUID
        let url: URL
        let delay: Double
        let fileStart: Double
        let duration: Double
    }

    private let engine = AVAudioEngine()
    private var nodes: [(clipID: UUID, node: AVAudioPlayerNode)] = []
    /// The Rhythm tool's Listen (plan, Phase 3 step 7): a click on each
    /// pattern note, on the same engine as the songs, so it keeps time.
    private var clickNode: AVAudioPlayerNode?
    private static let clickSound: AVAudioPCMBuffer? = {
        // 25 ms of a 1.6 kHz tone, falling away fast: a woodblock-ish tick.
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * 0.025))
        else { return nil }
        buf.frameLength = buf.frameCapacity
        let out = buf.floatChannelData![0]
        for i in 0..<Int(buf.frameLength) {
            let t = Double(i) / rate
            out[i] = Float(0.6 * sin(2 * .pi * 1600 * t) * exp(-t * 180))
        }
        return buf
    }()
    /// Each song's level at a show time (its volume, fades and crossfades),
    /// applied many times a second while it plays.
    private var gain: ((UUID, Double) -> Float)?
    /// The show time (within the pass) the play started from.
    private var startLocal: Double = 0
    private var levelTimer: Timer?
    private var files: [URL: AVAudioFile] = [:]
    /// When the scheduled sound starts, in host time.
    private var startHost: UInt64 = 0
    /// The output's sample count at `startHost`, worked out on first read.
    private var startSample: Double?
    public private(set) var isRunning = false
    /// The output device changed (headphones in or out, say) and playback
    /// stopped: the owner restarts it from wherever the clock is.
    public var onReset: (() -> Void)?
    private var observer: NSObjectProtocol?

    /// How far ahead of now the sound is scheduled, so every song starts on
    /// the same sample.
    private static let lead = 0.05

    public init() {
        _ = engine.mainMixerNode        // builds the output chain
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stop()
                self.onReset?()
            }
        }
    }

    /// Starts the segments playing together. False if nothing could be
    /// played (no segments, or no file would open): the show then runs on
    /// the system clock.
    ///
    /// `clicks` are seconds after the start, for Listen: they sound even
    /// with no song.
    public func start(_ segments: [Segment], clicks: [Double] = [], from local: Double,
               gain: @escaping (UUID, Double) -> Float) -> Bool {
        stop()
        var scheduled: [(AVAudioPlayerNode, AVAudioFile, Segment)] = []
        for seg in segments {
            guard let file = open(seg.url) else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            node.volume = gain(seg.clipID, local + seg.delay)
            scheduled.append((node, file, seg))
        }
        let clickSound = clicks.isEmpty ? nil : Self.clickSound
        guard !scheduled.isEmpty || clickSound != nil else { return false }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            scheduled.forEach { engine.detach($0.0) }
            return false
        }
        for (node, file, seg) in scheduled {
            let rate = file.processingFormat.sampleRate
            let first = AVAudioFramePosition(seg.fileStart * rate)
            guard first < file.length else { continue }
            let count = min(AVAudioFramePosition(seg.duration * rate), file.length - first)
            guard count > 0 else { continue }
            node.scheduleSegment(file, startingFrame: first, frameCount: AVAudioFrameCount(count),
                                 at: AVAudioTime(sampleTime: AVAudioFramePosition(seg.delay * rate), atRate: rate))
        }
        if let sound = clickSound {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: sound.format)
            let rate = sound.format.sampleRate
            for c in clicks.prefix(2000) where c >= 0 {
                node.scheduleBuffer(sound, at: AVAudioTime(sampleTime: AVAudioFramePosition(c * rate), atRate: rate))
            }
            clickNode = node
        }
        nodes = scheduled.map { ($0.2.clipID, $0.0) }
        self.gain = gain
        startLocal = local
        startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.lead)
        startSample = nil
        let when = AVAudioTime(hostTime: startHost)
        for n in nodes { n.node.play(at: when) }
        clickNode?.play(at: when)
        isRunning = true
        // In the common modes, so fades keep moving while something's dragged.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLevels() }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
        return true
    }

    private func applyLevels() {
        guard let gain, let e = elapsed else { return }
        let t = startLocal + e
        for n in nodes { n.node.volume = gain(n.clipID, t) }
    }

    public func stop() {
        levelTimer?.invalidate()
        levelTimer = nil
        gain = nil
        for n in nodes {
            n.node.stop()
            engine.detach(n.node)
        }
        nodes = []
        if let c = clickNode {
            c.stop()
            engine.detach(c)
            clickNode = nil
        }
        if engine.isRunning { engine.pause() }
        isRunning = false
    }

    /// Seconds of sound heard since the start, by the sound card's clock;
    /// nil when not playing. Never negative: during the short lead-in, the
    /// picture waits at the start.
    public var elapsed: Double? {
        guard isRunning, let r = engine.outputNode.lastRenderTime, r.isSampleTimeValid, r.isHostTimeValid
        else { return nil }
        let rate = r.sampleRate
        let renderSeconds = AVAudioTime.seconds(forHostTime: r.hostTime)
        if startSample == nil {
            startSample = Double(r.sampleTime) + (AVAudioTime.seconds(forHostTime: startHost) - renderSeconds) * rate
        }
        // Between render cycles, the host clock fills in; the output's
        // latency is taken off so the picture lines up with what's heard.
        let sinceRender = AVAudioTime.seconds(forHostTime: mach_absolute_time()) - renderSeconds
        let t = (Double(r.sampleTime) - startSample!) / rate + sinceRender - engine.outputNode.presentationLatency
        return max(0, t)
    }

    private func open(_ url: URL) -> AVAudioFile? {
        if let f = files[url] { return f }
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        files[url] = f
        return f
    }
}
