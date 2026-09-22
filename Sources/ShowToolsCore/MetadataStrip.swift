import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// Copies a file without the metadata that says who took it, where, when and
/// on what (plan, Phase 4: export strips by default). Pixels and sound are
/// left alone; only the container is rewritten.
///
/// Measured 2026-09-22 before relying on it:
/// - JPEG: ImageIO's lossless copy with the metadata replaced comes out clean
///   and pixel-identical. For HEIC, PNG and TIFF that same copy leaves some
///   behind (PNG kept GPS, camera and date), so those are written afresh
///   from their decoded frames, which came out clean and pixel-identical too.
/// - Video and songs: a passthrough export with `.forSharing()` dropped the
///   location but kept the camera and creation date, so they are remuxed
///   (samples copied untouched, no metadata written). A remuxed song decodes
///   sample-for-sample the same, with the same duration: no drift against
///   beats placed on it.
///
/// Every stripped copy is read back and checked; anything but orientation
/// and structural fields left in it is a failure, never a silent pass.
public enum MetadataStrip {

    public enum Failure: Error, CustomStringConvertible {
        case unsupported(String)
        case failed(String)
        /// It wrote, but the check found these still in it.
        case leftBehind([String])

        public var description: String {
            switch self {
            case .unsupported(let t): "can't rewrite \(t) files"
            case .failed(let m): m
            case .leftBehind(let tags): "metadata left in the copy: \(tags.joined(separator: ", "))"
            }
        }
    }

    public static func strip(_ src: URL, to dst: URL, kind: MediaKind) async throws {
        try? FileManager.default.removeItem(at: dst)
        do {
            switch kind {
            case .image, .animatedImage:
                try stripImage(src, to: dst)
                let left = imageMetadata(dst)
                if !left.isEmpty { throw Failure.leftBehind(left) }
            case .video, .audio:
                try await remux(src, to: dst)
                let left = try await avMetadata(dst).filter { !harmlessAVTags.contains($0) }
                if !left.isEmpty { throw Failure.leftBehind(left) }
            }
        } catch {
            try? FileManager.default.removeItem(at: dst)
            throw error
        }
    }

    // MARK: Images

    static func stripImage(_ src: URL, to dst: URL) throws {
        guard let s = CGImageSourceCreateWithURL(src as CFURL, nil),
              let type = CGImageSourceGetType(s) else { throw Failure.failed("not a readable image") }
        let n = CGImageSourceGetCount(s)
        guard let d = CGImageDestinationCreateWithURL(dst as CFURL, type, n, nil) else {
            throw Failure.unsupported(src.pathExtension.uppercased())
        }
        func orientation(_ i: Int) -> Any? {
            (CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any])?[kCGImagePropertyOrientation]
        }

        if UTType(type as String)?.conforms(to: .jpeg) == true, n == 1 {
            // Lossless: the compressed data is copied, the metadata replaced
            // by nothing but the orientation.
            let md = CGImageMetadataCreateMutable()
            if let o = orientation(0) as? Int {
                CGImageMetadataSetValueMatchingImageProperty(
                    md, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, o as CFNumber)
            }
            let opts: [CFString: Any] = [kCGImageDestinationMetadata: md,
                                         kCGImageDestinationMergeMetadata: false,
                                         kCGImageMetadataShouldExcludeGPS: true]
            var err: Unmanaged<CFError>?
            guard CGImageDestinationCopyImageSource(d, s, opts as CFDictionary, &err) else {
                throw Failure.failed(err.map { "\($0.takeRetainedValue())" } ?? "the copy failed")
            }
            return
        }

        // Everything else: each frame written afresh with only what it needs
        // to look and move the same — its orientation and, for animations,
        // its delay and the loop count.
        let fileProps = CGImageSourceCopyProperties(s, nil) as? [CFString: Any] ?? [:]
        var keepFile: [CFString: Any] = [:]
        for dict in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyHEICSDictionary] {
            let loopKey = dict == kCGImagePropertyGIFDictionary ? kCGImagePropertyGIFLoopCount
                : dict == kCGImagePropertyPNGDictionary ? kCGImagePropertyAPNGLoopCount : kCGImagePropertyHEICSLoopCount
            if let v = (fileProps[dict] as? [CFString: Any])?[loopKey] { keepFile[dict] = [loopKey: v] }
        }
        if !keepFile.isEmpty { CGImageDestinationSetProperties(d, keepFile as CFDictionary) }

        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(s, i, nil) else { throw Failure.failed("frame \(i) unreadable") }
            let p = CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any] ?? [:]
            var keep: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
            if let o = p[kCGImagePropertyOrientation] { keep[kCGImagePropertyOrientation] = o }
            let delays: [(CFString, [CFString])] = [
                (kCGImagePropertyGIFDictionary, [kCGImagePropertyGIFDelayTime, kCGImagePropertyGIFUnclampedDelayTime]),
                (kCGImagePropertyPNGDictionary, [kCGImagePropertyAPNGDelayTime, kCGImagePropertyAPNGUnclampedDelayTime]),
                (kCGImagePropertyHEICSDictionary, [kCGImagePropertyHEICSDelayTime, kCGImagePropertyHEICSUnclampedDelayTime]),
            ]
            for (dict, keys) in delays {
                guard let src = p[dict] as? [CFString: Any] else { continue }
                let kept = src.filter { keys.contains($0.key) }
                if !kept.isEmpty { keep[dict] = kept }
            }
            CGImageDestinationAddImage(d, img, keep as CFDictionary)
        }
        guard CGImageDestinationFinalize(d) else { throw Failure.failed("the image couldn't be written") }
    }

    /// Structural fields ImageIO writes itself, which say nothing about
    /// the picture's owner, place, time or camera.
    static let harmlessImageTags: Set<String> = [
        "tiff:Orientation", "tiff:TileWidth", "tiff:TileLength", "tiff:PhotometricInterpretation",
        "tiff:Compression", "tiff:ResolutionUnit", "tiff:XResolution", "tiff:YResolution",
        "tiff:PlanarConfiguration", "tiff:BitsPerSample", "tiff:SamplesPerPixel",
        "exif:PixelXDimension", "exif:PixelYDimension", "exif:ColorSpace", "iio:hasXMP",
    ]

    /// Every metadata tag in the file that isn't harmless, by path.
    public static func imageMetadata(_ url: URL) -> [String] {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ["unreadable"] }
        var out: [String] = []
        for i in 0..<CGImageSourceGetCount(s) {
            if let p = CGImageSourceCopyPropertiesAtIndex(s, i, nil) as? [CFString: Any],
               p[kCGImagePropertyGPSDictionary] != nil { out.append("GPS") }
            guard let md = CGImageSourceCopyMetadataAtIndex(s, i, nil) else { continue }
            CGImageMetadataEnumerateTagsUsingBlock(md, nil,
                [kCGImageMetadataEnumerateRecursively: true] as CFDictionary) { path, _ in
                let p = path as String
                if !harmlessImageTags.contains(p), !out.contains(p) { out.append(p) }
                return true
            }
        }
        return out
    }

    // MARK: Video and songs

    /// Copies the video and sound samples untouched into a new file of the
    /// same type, writing no metadata. Other tracks (timecode, timed
    /// metadata, which on a phone can carry location) are left out.
    static func remux(_ src: URL, to dst: URL) async throws {
        guard let uti = UTType(filenameExtension: src.pathExtension) else {
            throw Failure.unsupported(src.pathExtension.uppercased())
        }
        let type = AVFileType(rawValue: uti.identifier)
        let asset = AVURLAsset(url: src)
        let reader = try AVAssetReader(asset: asset)
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: dst, fileType: type) } catch {
            throw Failure.unsupported(src.pathExtension.uppercased())
        }
        writer.metadata = []
        var pairs: [(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)] = []
        for t in try await asset.load(.tracks) where t.mediaType == .video || t.mediaType == .audio {
            let o = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
            o.alwaysCopiesSampleData = false
            let hint = try await t.load(.formatDescriptions).first
            let i = AVAssetWriterInput(mediaType: t.mediaType, outputSettings: nil, sourceFormatHint: hint)
            i.transform = try await t.load(.preferredTransform)
            i.expectsMediaDataInRealTime = false
            guard reader.canAdd(o), writer.canAdd(i) else {
                throw Failure.unsupported(src.pathExtension.uppercased())
            }
            reader.add(o); writer.add(i)
            pairs.append((o, i))
        }
        guard !pairs.isEmpty else { throw Failure.failed("no video or sound in it") }
        guard reader.startReading(), writer.startWriting() else {
            throw Failure.failed((writer.error ?? reader.error)?.localizedDescription ?? "couldn't start")
        }
        writer.startSession(atSourceTime: .zero)

        // Feed the tracks turn about, as each is ready, so the writer can
        // interleave them.
        var done = Array(repeating: false, count: pairs.count)
        while done.contains(false) {
            var fed = false
            for (k, p) in pairs.enumerated() where !done[k] && p.input.isReadyForMoreMediaData {
                if let b = p.output.copyNextSampleBuffer() {
                    guard p.input.append(b) else {
                        reader.cancelReading()
                        throw Failure.failed(writer.error?.localizedDescription ?? "a sample wouldn't write")
                    }
                    fed = true
                } else {
                    p.input.markAsFinished()
                    done[k] = true
                }
            }
            if !fed { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        if reader.status == .failed {
            throw Failure.failed(reader.error?.localizedDescription ?? "reading failed")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw Failure.failed(writer.error?.localizedDescription ?? "writing failed")
        }
    }

    /// What the writer adds itself: an AAC song's gapless-playback figures
    /// (encoder delay and padding), which keep it sample-exact.
    static let harmlessAVTags: Set<String> = ["itlk/com.apple.iTunes.iTunSMPB"]

    /// Every metadata item in the file, container and tracks, by identifier.
    public static func avMetadata(_ url: URL) async throws -> [String] {
        let a = AVURLAsset(url: url)
        var out: [String] = []
        for f in try await a.load(.availableMetadataFormats) {
            for m in try await a.loadMetadata(for: f) { out.append(m.identifier?.rawValue ?? f.rawValue) }
        }
        for t in try await a.load(.tracks) {
            for m in try await t.load(.metadata) { out.append(m.identifier?.rawValue ?? "track") }
        }
        return out
    }
}
