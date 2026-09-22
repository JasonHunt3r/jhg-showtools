import AVFoundation
import ShowToolsCore

/// Plays a show's songs, and while it does, is the show's clock (plan:
/// "time comes from the music when a track is loaded"). Everything that
/// should sound from one moment on is scheduled at once, on one audio
/// engine, to start together; the time since then is read back from the
/// sound card's own sample count, so the picture follows what you hear
/// rather than the other way round.
@MainActor
final class MusicPlayer {
    /// One song's part of a play: from `fileStart` seconds into the file,
    /// for `duration`, starting `delay` seconds after the play starts.
    struct Segment {
        let url: URL
        let delay: Double
        let fileStart: Double
        let duration: Double
        let volume: Float
    }

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var files: [URL: AVAudioFile] = [:]
    /// When the scheduled sound starts, in host time.
    private var startHost: UInt64 = 0
    /// The output's sample count at `startHost`, worked out on first read.
    private var startSample: Double?
    private(set) var isRunning = false
    /// The output device changed (headphones in or out, say) and playback
    /// stopped: the owner restarts it from wherever the clock is.
    var onReset: (() -> Void)?
    private var observer: NSObjectProtocol?

    /// How far ahead of now the sound is scheduled, so every song starts on
    /// the same sample.
    private static let lead = 0.05

    init() {
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
    func start(_ segments: [Segment]) -> Bool {
        stop()
        var scheduled: [(AVAudioPlayerNode, AVAudioFile, Segment)] = []
        for seg in segments {
            guard let file = open(seg.url) else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            node.volume = seg.volume
            scheduled.append((node, file, seg))
        }
        guard !scheduled.isEmpty else { return false }
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
        nodes = scheduled.map(\.0)
        startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.lead)
        startSample = nil
        let when = AVAudioTime(hostTime: startHost)
        for node in nodes { node.play(at: when) }
        isRunning = true
        return true
    }

    func stop() {
        for node in nodes {
            node.stop()
            engine.detach(node)
        }
        nodes = []
        if engine.isRunning { engine.pause() }
        isRunning = false
    }

    /// Seconds of sound heard since the start, by the sound card's clock;
    /// nil when not playing. Never negative: during the short lead-in, the
    /// picture waits at the start.
    var elapsed: Double? {
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
