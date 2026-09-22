import SwiftUI
import Vision
import ImageIO
import ShowToolsCore
import ShowToolsPlayback

/// Each picture's fingerprint for Find Similar (plan, Phase 3b): Vision's
/// image feature print, worked out once per file and kept, on disk beside
/// the library (by content hash) and in memory while the app runs.
///
/// Pictures are shrunk to 299 px first, the size that kept a resized or
/// recompressed copy closest to its original (0.09–0.18) while different
/// photos stayed apart (0.39 and up), measured 2026-09-22 on the aerial
/// screensaver stills: 512 px put copies at 0.35–0.38, and whole images
/// given to Vision scattered them up to 0.63.
@MainActor @Observable
final class Fingerprints {
    static let shared = Fingerprints()

    /// `<library>/Cache/Prints`, set when a library opens.
    @ObservationIgnored var cacheDir: URL? {
        didSet { if cacheDir != oldValue { byHash = [:]; job?.cancel(); job = nil; progress = nil } }
    }
    @ObservationIgnored private var byHash: [String: [Float]] = [:]
    @ObservationIgnored private var job: Task<Void, Never>?
    /// Bumped as prints arrive, so views asking for them look again.
    private(set) var revision = 0
    /// While some are being worked out: how many of how many.
    private(set) var progress: (done: Int, total: Int)?

    /// The revision the cache files are named for: a different Vision model
    /// gives different numbers, so its prints never mix with these.
    nonisolated static let visionRevision = VNGenerateImageFeaturePrintRequestRevision2
    nonisolated static let side = 299

    static func fingerprintable(_ kind: MediaKind) -> Bool { kind == .image || kind == .animatedImage }

    func print(_ item: MediaItem) -> [Float]? { byHash[item.hash] }

    /// Works out whatever these pictures still lack, in the background,
    /// reading the disk cache first. A new call replaces one in progress.
    func prepare(_ items: [(item: MediaItem, url: URL)]) {
        guard let dir = cacheDir else { return }
        let todo = items.filter { Self.fingerprintable($0.item.kind) && byHash[$0.item.hash] == nil }
        guard !todo.isEmpty else { return }
        job?.cancel()
        progress = (0, todo.count)
        job = Task { [weak self] in
            var done = 0
            // A few at a time: Vision and image decoding use every core anyway.
            await withTaskGroup(of: (String, [Float]?).self) { group in
                var queue = todo[...]
                func next() {
                    guard let (item, url) = queue.popFirst() else { return }
                    let hash = item.hash
                    group.addTask(priority: .utility) { (hash, Self.load(url, hash: hash, dir: dir)) }
                }
                for _ in 0..<4 { next() }
                for await (hash, p) in group {
                    guard let self, !Task.isCancelled else { group.cancelAll(); return }
                    if let p { self.byHash[hash] = p }
                    done += 1
                    self.progress = (done, todo.count)
                    if done % 16 == 0 || done == todo.count { self.revision += 1 }
                    next()
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.progress = nil
            self.revision += 1
        }
    }

    /// From the disk cache, or worked out and saved there.
    nonisolated private static func load(_ url: URL, hash: String, dir: URL) -> [Float]? {
        let file = dir.appendingPathComponent("\(hash).r\(visionRevision).f32")
        if let data = try? Data(contentsOf: file), data.count % 4 == 0, !data.isEmpty {
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        guard let print = compute(url) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? print.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file, options: .atomic)
        return print
    }

    nonisolated private static func compute(_ url: URL) -> [Float]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = visionRevision
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
              let o = request.results?.first as? VNFeaturePrintObservation, o.elementType == .float
        else { return nil }
        return o.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
