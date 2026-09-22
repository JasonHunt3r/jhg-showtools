import Foundation
import AVFoundation
import ShowToolsCore
import ShowToolsPlayback
// Weakly linked: the framework is new in macOS 27, and the app still has to
// launch on older systems, where beat detection just says it isn't there.
@_weakLinked import MusicUnderstanding

/// Songs' rhythms (beats, bar starts, tempo, sections), found once per file
/// with Apple's Music Understanding framework (plan, Phase 3 step 6) and
/// kept: on disk beside the library (by content hash), and in memory while
/// the app runs. Analysis starts the first time a song is drawn.
@MainActor
@Observable
final class Rhythms {
    static let shared = Rhythms()

    enum State: Equatable {
        case analysing
        case ready(SongRhythm)
        case failed(String)
    }

    /// `<library>/Cache/Rhythm`, set when a library opens.
    @ObservationIgnored var cacheDir: URL?
    private(set) var byHash: [String: State] = [:]

    /// Beat detection needs macOS 27.
    static var isAvailable: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    func state(_ item: MediaItem) -> State? { byHash[item.hash] }

    func rhythm(_ item: MediaItem) -> SongRhythm? {
        if case .ready(let r) = byHash[item.hash] { return r }
        return nil
    }

    /// From memory or the cache, or analysed now (in the background). Does
    /// nothing before macOS 27, or while that song is already being read.
    func load(_ item: MediaItem, url: URL) async {
        guard item.kind == .audio, byHash[item.hash] == nil, let dir = cacheDir else { return }
        let hash = item.hash
        let file = dir.appendingPathComponent("\(hash).json")
        if let data = try? Data(contentsOf: file), let r = try? JSONDecoder().decode(SongRhythm.self, from: data) {
            byHash[hash] = .ready(r)
            return
        }
        guard #available(macOS 27.0, *) else { return }
        byHash[hash] = .analysing
        do {
            let r = try await Self.analyse(url)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? JSONEncoder().encode(r).write(to: file, options: .atomic)
            byHash[hash] = .ready(r)
        } catch {
            byHash[hash] = .failed(error.localizedDescription)
        }
    }

    /// Forget a failed analysis so it can be tried again.
    func retry(_ item: MediaItem, url: URL) async {
        if case .failed = byHash[item.hash] { byHash[item.hash] = nil }
        await load(item, url: url)
    }

    @available(macOS 27.0, *)
    private nonisolated static func analyse(_ url: URL) async throws -> SongRhythm {
        // Precise timing, as the framework's WWDC session asks.
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let session = try await MusicUnderstandingSession(asset: asset)
        let result = try await session.analyze(for: [.rhythm, .structure])
        let rhythm = result.rhythm
        return SongRhythm(
            beats: rhythm?.beats.map(\.seconds) ?? [],
            bars: rhythm?.bars.map(\.seconds) ?? [],
            beatsPerMinute: rhythm?.beatsPerMinute.map(Double.init),
            sections: result.structure?.sections.map { .init(start: $0.start.seconds, end: $0.end.seconds) } ?? [])
    }
}
