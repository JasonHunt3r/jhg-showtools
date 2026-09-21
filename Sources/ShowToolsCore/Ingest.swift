import Foundation
import CryptoKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// What a file is, read from the file itself.
public struct MediaProbe: Sendable {
    public var kind: MediaKind
    public var width: Int
    public var height: Int
    public var duration: Double?

    /// Nil when the file isn't media the app can show.
    public static func read(_ url: URL) async -> MediaProbe? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return await readVideo(url)
        }
        if type.conforms(to: .image) { return readImage(url) }
        return nil
    }

    static func readImage(_ url: URL) -> MediaProbe? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              var w = props[kCGImagePropertyPixelWidth] as? Int,
              var h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // Orientations 5–8 are rotated a quarter turn.
        if let o = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(o) { swap(&w, &h) }

        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return MediaProbe(kind: .image, width: w, height: h) }
        let total = (0..<count).reduce(0.0) { $0 + AnimatedFrames.delay(src, $1) }
        return MediaProbe(kind: .animatedImage, width: w, height: h, duration: total)
    }

    static func readVideo(_ url: URL) async -> MediaProbe? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform),
              let duration = try? await asset.load(.duration)
        else { return nil }
        let r = CGRect(origin: .zero, size: size).applying(transform)
        return MediaProbe(kind: .video, width: Int(abs(r.width).rounded()),
                          height: Int(abs(r.height).rounded()), duration: duration.seconds)
    }
}

public enum AnimatedFrames {
    /// A frame's delay, as browsers read it: under 0.02s means 0.1s.
    public static func delay(_ src: CGImageSource, _ i: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] else { return 0.1 }
        let dicts: [CFString] = [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary,
                                 kCGImagePropertyHEICSDictionary, kCGImagePropertyWebPDictionary]
        for key in dicts {
            guard let d = props[key] as? [CFString: Any] else { continue }
            let v = (d[kCGImagePropertyGIFUnclampedDelayTime] ?? d[kCGImagePropertyAPNGUnclampedDelayTime]
                     ?? d[kCGImagePropertyHEICSUnclampedDelayTime] ?? d[kCGImagePropertyWebPUnclampedDelayTime]
                     ?? d[kCGImagePropertyGIFDelayTime] ?? d[kCGImagePropertyAPNGDelayTime]
                     ?? d[kCGImagePropertyHEICSDelayTime] ?? d[kCGImagePropertyWebPDelayTime]) as? Double
            if let v { return v < 0.02 ? 0.1 : v }
        }
        return 0.1
    }
}

/// The file side of ingest: everything except the database row.
public enum Ingest {

    /// Every media file under the given files and folders, in a stable order.
    /// Hidden files and packages (a Photos library, say) are skipped.
    public static func collect(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if isMedia(url) { out.append(url) }
                continue
            }
            guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            var found: [URL] = []
            for case let f as URL in e where isMedia(f) { found.append(f) }
            out += found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return out
    }

    public static func isMedia(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .image) || t.conforms(to: .movie) || t.conforms(to: .video)
    }

    public static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public struct Copied: Sendable {
        public let relativePath: String
        public let probe: MediaProbe
    }

    public enum Failure: Error, CustomStringConvertible {
        case notMedia, verifyFailed, copy(String)
        public var description: String {
            switch self {
            case .notMedia: "not a readable image or video"
            case .verifyFailed: "the copy didn't match the original"
            case .copy(let m): m
            }
        }
    }

    /// Copies `source` into `mediaDir`, keeping its name (numbered if taken),
    /// and proves the copy is byte-identical before returning. On any failure
    /// the partial copy is removed.
    public static func copyIn(_ source: URL, expectedHash: String, mediaDir: URL,
                              folder: String = "") async throws -> Copied {
        guard let probe = await MediaProbe.read(source) else { throw Failure.notMedia }
        let fm = FileManager.default
        let dir = folder.isEmpty ? mediaDir : mediaDir.appendingPathComponent(folder)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dest = uniqueURL(in: dir, for: source.lastPathComponent)
        do {
            try fm.copyItem(at: source, to: dest)
        } catch {
            throw Failure.copy(error.localizedDescription)
        }
        guard (try? sha256(of: dest)) == expectedHash else {
            try? fm.removeItem(at: dest)
            throw Failure.verifyFailed
        }
        let rel = String(dest.path.dropFirst(mediaDir.path.count + 1))
        return Copied(relativePath: rel, probe: probe)
    }

    static func uniqueURL(in dir: URL, for name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            candidate = dir.appendingPathComponent(next)
            n += 1
        }
        return candidate
    }
}
