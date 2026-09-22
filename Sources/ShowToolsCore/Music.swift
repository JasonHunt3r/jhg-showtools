import Foundation
import AVFoundation

/// A song in the music row (plan, Phase 3). Like a lane image, it sits at a
/// time on the show's clock; it plays `length` seconds of its file starting
/// `inPoint` seconds in (trimming the front edge moves both).
public struct AudioClip: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var itemID: Int64
    /// Seconds from the start of the show.
    public var start: Double
    /// Seconds into the song where the clip begins.
    public var inPoint: Double = 0
    public var length: Double
    /// 0…1.
    public var volume: Double = 1
    /// Seconds to fade in from silence and out to silence.
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    /// Markers placed by beat detection (plan, Phase 3 step 6), in *song*
    /// time, so they belong to the song and move with it. One outside the
    /// clip (trimmed past) hides, and comes back if the trim is undone.
    public var markers: [Marker] = []

    public init(itemID: Int64, start: Double, length: Double) {
        self.itemID = itemID
        self.start = start
        self.length = length
    }

    public var end: Double { start + length }

    /// Field by field, like every saved type. The file and the timing have no
    /// sensible fallback, so without them it fails, and `decodeList` skips it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        itemID = try c.decode(Int64.self, forKey: .itemID)
        start = try c.decode(Double.self, forKey: .start)
        length = try c.decode(Double.self, forKey: .length)
        id = get(.id, UUID())
        inPoint = get(.inPoint, 0)
        volume = get(.volume, 1)
        fadeIn = get(.fadeIn, 0)
        fadeOut = get(.fadeOut, 0)
        // Each marker on its own: one unreadable one doesn't cost the rest.
        var list = try? c.nestedUnkeyedContainer(forKey: .markers)
        var read: [Marker] = []
        while let l = list, !l.isAtEnd {
            if let m = try? list!.decode(Marker.self) { read.append(m) } else { _ = try? list!.decode(Skip.self) }
        }
        markers = read
    }

    /// Decodes anything, to step past an unreadable list element.
    private struct Skip: Decodable {}

    /// Song time to show time, and back.
    public func showTime(ofSongTime t: Double) -> Double { start + (t - inPoint) }
    public func songTime(ofShowTime t: Double) -> Double { inPoint + (t - start) }

    /// Its detected markers that fall inside the clip, at their show times.
    public var visibleMarkers: [(marker: Marker, time: Double)] {
        markers.compactMap { m in
            m.time >= inPoint - 1e-9 && m.time <= inPoint + length + 1e-9 ? (m, showTime(ofSongTime: m.time)) : nil
        }
    }

    /// A saved list, keeping every clip that can be read.
    public static func decodeList(_ json: String) -> [AudioClip] {
        guard let items = try? JSONDecoder().decode([Lenient].self, from: Data(json.utf8)) else { return [] }
        return items.compactMap(\.clip)
    }

    private struct Lenient: Decodable {
        let clip: AudioClip?
        init(from decoder: Decoder) throws { clip = try? AudioClip(from: decoder) }
    }

    /// The clip's own level at show time `t`: its volume, ramped from
    /// silence over the fade in and back down over the fade out.
    public func envelope(at t: Double) -> Double {
        guard t >= start, t < end else { return 0 }
        var g = min(max(volume, 0), 1)
        if fadeIn > 0 { g *= min((t - start) / fadeIn, 1) }
        if fadeOut > 0 { g *= min((end - t) / fadeOut, 1) }
        return max(g, 0)
    }

    /// Where two songs overlap because the later one starts inside the
    /// earlier and runs past its end, they crossfade across the overlap:
    /// the earlier fades out as the later fades in, equal-power so the
    /// loudness holds through the middle. A song lying wholly inside another
    /// just plays over it (its own fades still apply).
    public static func gain(of clip: AudioClip, at t: Double, among clips: [AudioClip]) -> Double {
        var g = clip.envelope(at: t)
        guard g > 0 else { return 0 }
        for other in clips where other.id != clip.id {
            if let o = crossfade(earlier: clip, later: other), o.contains(t) {
                g *= cos((t - o.lowerBound) / (o.upperBound - o.lowerBound) * .pi / 2)
            } else if let o = crossfade(earlier: other, later: clip), o.contains(t) {
                g *= sin((t - o.lowerBound) / (o.upperBound - o.lowerBound) * .pi / 2)
            }
        }
        return max(g, 0)
    }

    /// The span two songs crossfade over, if `later` starts inside
    /// `earlier` and ends after it.
    public static func crossfade(earlier: AudioClip, later: AudioClip) -> ClosedRange<Double>? {
        guard later.start > earlier.start, later.start < earlier.end, later.end > earlier.end else { return nil }
        return later.start...earlier.end
    }

    /// Every span where two songs overlap, crossfading or not, for drawing.
    public static func overlaps(_ clips: [AudioClip]) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        for (i, a) in clips.enumerated() {
            for b in clips[(i + 1)...] {
                let lo = max(a.start, b.start), hi = min(a.end, b.end)
                if hi > lo { out.append(lo...hi) }
            }
        }
        return out
    }

    /// What should play when the show's clock reads `local` (inside one pass
    /// of the show), up to `until`: how long from now it starts, where in the
    /// file, and for how long. Nil if nothing of it is left to play.
    public func segment(from local: Double, until: Double) -> (delay: Double, fileStart: Double, duration: Double)? {
        let from = max(local, start)
        let to = min(end, until)
        guard to - from > 0.001 else { return nil }
        return (delay: from - local, fileStart: inPoint + (from - start), duration: to - from)
    }
}

/// A marker dropped by hand, on the show's clock (plan, Phase 3). A time
/// only, for now.
public struct Marker: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    /// Seconds from the start of the show.
    public var time: Double
    /// Its own line down through the rows (with the show's marker lines on).
    public var showsLine = true

    public init(time: Double) { self.time = time }

    /// Field by field, like every saved type. Without its time there's no
    /// marker, so it fails, and `decodeList` skips it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Double.self, forKey: .time)
        id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        showsLine = ((try? c.decodeIfPresent(Bool.self, forKey: .showsLine)) ?? nil) ?? true
    }

    public static func decodeList(_ json: String) -> [Marker] {
        guard let items = try? JSONDecoder().decode([Lenient].self, from: Data(json.utf8)) else { return [] }
        return items.compactMap(\.marker)
    }

    private struct Lenient: Decodable {
        let marker: Marker?
        init(from decoder: Decoder) throws { marker = try? Marker(from: decoder) }
    }
}

/// Snapping (plan, Phase 3): an edge being dragged lands on a marker when
/// it comes within a few points of one.
public enum Snap {
    /// The target nearest `t`, if one is within `tolerance` seconds.
    public static func nearest(_ t: Double, in targets: [Double], within tolerance: Double) -> Double? {
        var best: Double?
        for x in targets where abs(x - t) <= tolerance {
            if best == nil || abs(x - t) < abs(best! - t) { best = x }
        }
        return best
    }
}

/// A song's loudness over time, for drawing: the loudest sample in each
/// slice, 0…255. Read from the file once and cached beside the library
/// (plan: "decoded once and cached").
public struct Waveform: Sendable, Equatable {
    public static let slicesPerSecond = 100.0
    public let peaks: [UInt8]

    public init(peaks: [UInt8]) { self.peaks = peaks }

    public var duration: Double { Double(peaks.count) / Self.slicesPerSecond }

    /// The loudest peak, 0…1, between two times in the song.
    public func peak(from t0: Double, to t1: Double) -> Double {
        guard !peaks.isEmpty else { return 0 }
        let a = max(0, min(peaks.count - 1, Int(t0 * Self.slicesPerSecond)))
        let b = max(a + 1, min(peaks.count, Int((t1 * Self.slicesPerSecond).rounded(.up))))
        var m: UInt8 = 0
        for i in a..<b where peaks[i] > m { m = peaks[i] }
        return Double(m) / 255
    }

    /// Decodes the whole file, all channels, in chunks.
    public static func read(_ url: URL) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let perSlice = max(1, Int(format.sampleRate / slicesPerSecond))
        let chunk = AVAudioFrameCount(perSlice * 256)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return Waveform(peaks: []) }
        var peaks: [UInt8] = []
        peaks.reserveCapacity(Int(Double(file.length) / Double(perSlice)) + 1)
        var sliceMax: Float = 0, inSlice = 0
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            guard n > 0, let channels = buffer.floatChannelData else { break }
            for i in 0..<n {
                for c in 0..<Int(format.channelCount) {
                    let v = abs(channels[c][i])
                    if v > sliceMax { sliceMax = v }
                }
                inSlice += 1
                if inSlice == perSlice {
                    peaks.append(UInt8(min(sliceMax, 1) * 255))
                    sliceMax = 0; inSlice = 0
                }
            }
        }
        if inSlice > 0 { peaks.append(UInt8(min(sliceMax, 1) * 255)) }
        return Waveform(peaks: peaks)
    }

    /// From the cache if it's there, else read from the file and cached.
    /// Keyed by the file's hash, so a rename or relink doesn't matter.
    public static func load(_ url: URL, hash: String, cacheDir: URL) throws -> Waveform {
        let cached = cacheDir.appendingPathComponent("\(hash).peaks")
        if let data = try? Data(contentsOf: cached), !data.isEmpty { return Waveform(peaks: [UInt8](data)) }
        let w = try read(url)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? Data(w.peaks).write(to: cached, options: .atomic)
        return w
    }
}
