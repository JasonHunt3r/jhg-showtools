import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ShowToolsCore

final class SetlistTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("showtools-setlist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: Media with metadata in it

    /// A 64×32 picture carrying GPS, camera and date, turned by orientation 6.
    func writeImage(_ name: String, _ type: UTType, colour: CGFloat = 1, frames: Int = 1) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil)!
        if frames > 1 {
            CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        for f in 0..<frames {
            let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(red: colour, green: CGFloat(f) / CGFloat(frames), blue: 0.2, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 32))
            var props: [CFString: Any] = [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
                                                kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05",
                                                 kCGImagePropertyExifLensModel: "SecretLens"],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple",
                                                 kCGImagePropertyTIFFModel: "iPhone Secret"],
            ]
            if frames > 1 { props[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: 0.25] }
            CGImageDestinationAddImage(d, ctx.makeImage()!, props as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(d))
        return url
    }

    /// One second of black video, with a location, camera and date on it.
    func writeVideo(_ name: String = "clip.mov") async throws -> URL {
        let url = dir.appendingPathComponent(name)
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        func item(_ id: AVMetadataIdentifier, _ v: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem(); m.identifier = id; m.value = v as NSString; return m
        }
        w.metadata = [item(.quickTimeMetadataLocationISO6709, "+51.5000-000.1200/"),
                      item(.quickTimeMetadataMake, "Apple"), item(.quickTimeMetadataModel, "iPhone Secret"),
                      item(.quickTimeMetadataCreationDate, "2024-01-02T03:04:05Z")]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        w.add(input)
        w.startWriting(); w.startSession(atSourceTime: .zero)
        for i in 0..<10 {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 10))
        }
        input.markAsFinished()
        await w.finishWriting()
        return url
    }

    /// Two seconds of AAC.
    func writeSong(_ name: String = "song.m4a") throws -> URL {
        let url = dir.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for c in 0..<2 { for i in 0..<88_200 { buffer.floatChannelData![c][i] = 0.5 * sin(Float(i) * 0.05) } }
        try file.write(from: buffer)
        return url
    }

    func pixels(_ url: URL, frame: Int = 0) -> Data {
        let s = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(s, frame, nil)!.dataProvider!.data! as Data
    }

    func orientation(_ url: URL) -> Int? {
        let s = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? Int
    }

    // MARK: Stripping

    func testStillImagesComeOutCleanWithTheirPixelsAndOrientation() async throws {
        for (name, type) in [("a.jpg", UTType.jpeg), ("a.heic", .heic), ("a.png", .png), ("a.tiff", .tiff)] {
            let src = try writeImage(name, type)
            XCTAssertFalse(MetadataStrip.imageMetadata(src).isEmpty, "\(name) starts with metadata")
            let out = dir.appendingPathComponent("stripped-" + name)
            try await MetadataStrip.strip(src, to: out, kind: .image)
            XCTAssertEqual(MetadataStrip.imageMetadata(out), [], name)
            XCTAssertEqual(orientation(out), 6, name)
            XCTAssertEqual(pixels(src), pixels(out), name)
        }
    }

    func testAnAnimationKeepsItsFramesAndTiming() async throws {
        let src = try writeImage("a.gif", .gif, frames: 3)
        let out = dir.appendingPathComponent("stripped.gif")
        try await MetadataStrip.strip(src, to: out, kind: .animatedImage)
        XCTAssertEqual(MetadataStrip.imageMetadata(out), [])
        let s = CGImageSourceCreateWithURL(out as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetCount(s), 3)
        XCTAssertEqual(AnimatedFrames.delay(s, 1), 0.25, accuracy: 0.001)
        for f in 0..<3 { XCTAssertEqual(pixels(src, frame: f), pixels(out, frame: f)) }
    }

    func testAVideoLosesItsLocationCameraAndDate() async throws {
        let src = try await writeVideo()
        let before = try await MetadataStrip.avMetadata(src)
        XCTAssertTrue(before.contains { $0.contains("location") })
        let out = dir.appendingPathComponent("stripped.mov")
        try await MetadataStrip.strip(src, to: out, kind: .video)
        let after = try await MetadataStrip.avMetadata(out)
        XCTAssertEqual(after, [])
        let d0 = try await AVURLAsset(url: src).load(.duration).seconds
        let d1 = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(d0, d1, accuracy: 0.001)
    }

    /// A song tagged as a purchase: its title and artist, and the buyer's
    /// Apple ID, name and purchase date.
    func writeTaggedSong() async throws -> URL {
        let plain = try writeSong("plain.m4a")
        func item(_ key: String, _ v: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = AVMetadataItem.identifier(forKey: key as NSString, keySpace: .iTunes)
            m.value = v as NSString
            return m
        }
        let url = dir.appendingPathComponent("song.m4a")
        try await MetadataStrip.remux(plain, to: url, metadata: [
            item("\u{A9}nam", "Fly Me to the Moon"), item("\u{A9}ART", "Someone"),
            item("apID", "someone@example.com"), item("ownr", "Some One"),
            item("purd", "2024-01-02 03:04:05")])
        return url
    }

    func testASongKeepsItsTagsAndLengthButNotWhoBoughtIt() async throws {
        let src = try await writeTaggedSong()
        let before = try await MetadataStrip.avMetadata(src)
        XCTAssertTrue(before.contains("itsk/apID"), "\(before)")
        let out = dir.appendingPathComponent("stripped.m4a")
        try await MetadataStrip.strip(src, to: out, kind: .audio)
        let after = Set(try await MetadataStrip.avMetadata(out))
        XCTAssertTrue(after.contains("itsk/%A9nam"), "\(after)")
        XCTAssertTrue(after.contains("itsk/%A9ART"), "\(after)")
        XCTAssertTrue(after.isDisjoint(with: ["itsk/apID", "itsk/ownr", "itsk/purd"]), "\(after)")
        let d0 = try await AVURLAsset(url: src).load(.duration).seconds
        let d1 = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(d0, d1, accuracy: 0.0001)
    }

    // MARK: Text forms

    func testTSVValuesReadAsWritten() {
        XCTAssertEqual(SetlistTSV.number(8), "8")
        XCTAssertEqual(SetlistTSV.number(2.5), "2.5")
        XCTAssertEqual(SetlistTSV.number(0.123456), "0.123")
        XCTAssertEqual(SetlistTSV.number(-0.0001), "0")
        XCTAssertEqual(SetlistTSV.length(.clip), "clip")
        XCTAssertEqual(SetlistTSV.transition(.newShowDefault), "dissolve 2 lead 1")
        XCTAssertEqual(SetlistTSV.transition(Transition(style: .swipe, duration: 0.5, direction: .up)), "swipe up 0.5")
        var r = Rotation(); r.startAngle = 0; r.endAngle = 90
        XCTAssertEqual(SetlistTSV.rotation(r), "0 to 90")
        r.mode = .speed; r.speed = 30
        XCTAssertEqual(SetlistTSV.rotation(r), "30/s")
        r.startAngle = 10
        XCTAssertEqual(SetlistTSV.rotation(r), "30/s from 10")
        r.enabled = false
        XCTAssertEqual(SetlistTSV.rotation(r), "off")
        XCTAssertEqual(SetlistTSV.colour(SRGBColor(red: 1, green: 0.5, blue: 0)), "#ff8000")
        let kb = KenBurnsSetting.custom(KenBurns(start: .centred, end: KenBurnsFrame(x: 0.3, y: 0.4, zoom: 1.4)))
        XCTAssertEqual(SetlistTSV.kenBurnsStart(kb), "0.5,0.5,1")
        XCTAssertEqual(SetlistTSV.kenBurnsEnd(kb), "0.3,0.4,1.4")
        XCTAssertEqual(SetlistTSV.kenBurnsStart(.auto), "auto")
        XCTAssertEqual(SetlistTSV.kenBurnsEnd(.auto), "")
        XCTAssertEqual(SetlistExport.folderName(for: ".Trip/2024: Day 1"), "Trip-2024- Day 1")
        XCTAssertEqual(SetlistExport.folderName(for: "  "), "Untitled Show")
    }

    // MARK: Export

    func ingest(_ lib: Library, _ url: URL) async throws -> MediaItem {
        let hash = try Ingest.sha256(of: url)
        let c = try await Ingest.copyIn(url, expectedHash: hash, mediaDir: lib.mediaURL)
        return try lib.insertItem(relativePath: c.relativePath, hash: hash, probe: c.probe, sourcePath: url.path)
    }

    /// A show of three slides (the beach photo twice), a song and a lane image.
    func makeShow() async throws -> (Library, Show, [MediaItem]) {
        let lib = try Library(root: dir.appendingPathComponent("Lib.noindex"))
        let beach = try await ingest(lib, try writeImage("beach.jpg", .jpeg))
        let sunset = try await ingest(lib, try writeImage("sunset.png", .png, colour: 0.4))
        let logo = try await ingest(lib, try writeImage("logo.gif", .gif, frames: 2))
        let song = try await ingest(lib, try writeSong())
        try lib.setRating(4, for: [sunset.id])
        try lib.setTags(["Summer"], for: sunset.id)
        var show = try lib.createShow(name: "Beach Trip", itemIDs: [beach.id, sunset.id, beach.id])
        show.slides[0].settings.length = .seconds(8)
        show.slides[0].settings.kenBurns = .custom(KenBurns(start: .centred, end: KenBurnsFrame(x: 0.3, y: 0.4, zoom: 1.4)))
        show.slides[1].settings.transition = Transition(style: .swipe, duration: 0.5)
        var rot = Rotation(); rot.endAngle = 90
        show.slides[2].settings.rotation = rot
        show.music = [AudioClip(itemID: song.id, start: 0, length: 2)]
        show.overlays = [OverlayClip(itemID: logo.id, start: 1, length: 3)]
        show.markers = [Marker(time: 1.5)]
        show = try lib.saveShow(show)
        return (lib, show, [beach, sunset, logo, song])
    }

    func testAnExportWritesNumberedSlidesSubfoldersAndBothManifests() async throws {
        let (lib, show, items) = try await makeShow()
        let out = dir.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let plan = try SetlistExport.plan(show, from: lib, now: now)
        let result = try await SetlistExport.write(plan, into: out)

        XCTAssertEqual(result.folder.lastPathComponent, "Beach Trip")
        XCTAssertEqual(result.notStripped.count, 0, "\(result.notStripped)")
        XCTAssertFalse(result.replaced)
        let names = try FileManager.default.contentsOfDirectory(atPath: result.folder.path).sorted()
        XCTAssertEqual(names, ["001_beach.jpg", "002_sunset.png", "003_beach.jpg", "music", "overlays",
                               "show.json", "show.tsv"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("music/song.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("overlays/logo.gif").path))
        // Nothing left behind: the staging folder was moved into place.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Beach Trip"])

        // Stripped: clean, and so a different hash from the library's.
        let first = result.folder.appendingPathComponent("001_beach.jpg")
        XCTAssertEqual(MetadataStrip.imageMetadata(first), [])
        XCTAssertNotEqual(try Ingest.sha256(of: first), items[0].hash)
        XCTAssertEqual(pixels(first), pixels(lib.url(for: items[0])))

        // show.json reads back as exactly what was planned.
        let data = try Data(contentsOf: result.folder.appendingPathComponent("show.json"))
        let m = try SetlistManifest.decoder().decode(SetlistManifest.self, from: data)
        XCTAssertEqual(m, plan.manifest)
        XCTAssertEqual(m.slides.map(\.hash), [items[0].hash, items[1].hash, items[0].hash])
        XCTAssertEqual(m.slides.map(\.id), show.slides.map(\.id))
        XCTAssertEqual(m.slides.map(\.settings), show.slides.map(\.settings))
        XCTAssertEqual(m.music.map(\.file), ["music/song.m4a"])
        XCTAssertEqual(m.overlays.map(\.file), ["overlays/logo.gif"])
        XCTAssertEqual(m.markers, show.markers)
        XCTAssertEqual(m.files.first { $0.hash == items[1].hash }, SetlistFileInfo(hash: items[1].hash, rating: 4, tags: ["Summer"]))
        XCTAssertTrue(m.metadataStripped)

        let tsv = try String(contentsOf: result.folder.appendingPathComponent("show.tsv"), encoding: .utf8)
        let lines = tsv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "# ShowTools setlist v1")
        XCTAssertTrue(lines.contains("# music\tmusic/song.m4a"))
        XCTAssertTrue(lines.contains(SetlistTSV.columns.joined(separator: "\t")))
        XCTAssertTrue(lines.contains("001_beach.jpg\t8\t\t0.5,0.5,1\t0.3,0.4,1.4\t\t\t"))
        XCTAssertTrue(lines.contains("002_sunset.png\t\tswipe left 0.5\t\t\t\t\t"))
        XCTAssertTrue(lines.contains("003_beach.jpg\t\t\t\t\t\t0 to 90\t"))
    }

    func testUnstrippedCopiesAreByteForByte() async throws {
        let (lib, show, items) = try await makeShow()
        let opts = SetlistExport.Options(stripMetadata: false, hideFromSpotlight: true)
        let plan = try SetlistExport.plan(show, from: lib, options: opts)
        let result = try await SetlistExport.write(plan, into: dir, options: opts)
        XCTAssertEqual(result.folder.lastPathComponent, "Beach Trip.noindex")
        let named = try SetlistExport.plan(show, from: lib, options: .init(hideFromSpotlight: true, folderName: "Trip.noindex"))
        XCTAssertEqual(named.folderName, "Trip.noindex", "typed .noindex isn't doubled")
        XCTAssertEqual(try Ingest.sha256(of: result.folder.appendingPathComponent("001_beach.jpg")), items[0].hash)
        XCTAssertEqual(try Ingest.sha256(of: result.folder.appendingPathComponent("003_beach.jpg")), items[0].hash)
        XCTAssertEqual(try Ingest.sha256(of: result.folder.appendingPathComponent("music/song.m4a")), items[3].hash)
        XCTAssertFalse(plan.manifest.metadataStripped)
    }

    func testExportingAgainReplacesTheEarlierExportButNoOtherFolder() async throws {
        let (lib, show, _) = try await makeShow()
        let first = try await SetlistExport.write(try SetlistExport.plan(show, from: lib), into: dir)
        let firstJSON = try Data(contentsOf: first.folder.appendingPathComponent("show.json"))
        let bin = dir.appendingPathComponent("Bin")
        let again = try await SetlistExport.write(try SetlistExport.plan(show, from: lib), into: dir,
                                                  discard: { try FileManager.default.moveItem(at: $0, to: bin) })
        XCTAssertTrue(again.replaced)
        XCTAssertEqual(try Data(contentsOf: bin.appendingPathComponent("show.json")), firstJSON,
                       "the earlier export went to discard")

        // Another show of the same name is not this show's export.
        var other = try lib.createShow(name: "Beach Trip", itemIDs: [show.slides[0].itemID])
        other = try lib.saveShow(other)
        do {
            _ = try await SetlistExport.write(try SetlistExport.plan(other, from: lib), into: dir)
            XCTFail("wrote over another show's export")
        } catch let e as SetlistExport.Failure {
            XCTAssertEqual(e, .folderNotEmpty("Beach Trip"))
        }
        // An empty folder of that name is fine to use.
        try FileManager.default.removeItem(at: again.folder)
        try FileManager.default.createDirectory(at: again.folder, withIntermediateDirectories: true)
        _ = try await SetlistExport.write(try SetlistExport.plan(other, from: lib), into: dir)
    }

    func testAMissingFileStopsTheExportBeforeAnythingIsWritten() async throws {
        let (lib, show, items) = try await makeShow()
        try FileManager.default.removeItem(at: lib.url(for: items[1]))
        XCTAssertThrowsError(try SetlistExport.plan(show, from: lib)) { e in
            XCTAssertEqual(e as? SetlistExport.Failure, .missingFiles(["sunset.png"]))
        }
    }

    func testNumbersArePaddedToTheSlideCount() async throws {
        let (lib, show, items) = try await makeShow()
        var big = show
        big.slides = (0..<1200).map { Slide(id: Int64($0 + 1), itemID: items[0].id) }
        let plan = try SetlistExport.plan(big, from: lib)
        XCTAssertEqual(plan.manifest.slides.first?.file, "0001_beach.jpg")
        XCTAssertEqual(plan.manifest.slides.last?.file, "1200_beach.jpg")
        XCTAssertEqual(try SetlistExport.plan(show, from: lib).manifest.slides.first?.file, "001_beach.jpg")
    }

    func testAManifestSkipsWhatItCantReadAndKeepsTheRest() throws {
        let json = """
            {"version": 1, "name": "X", "slides": [{"file": "001_a.jpg", "hash": "h"}, {"nofile": 1},
             {"file": "002_b.jpg", "settings": {"fit": "nonsense", "length": {"clip": {}}}}],
             "defaults": {"length": 7}}
            """
        let m = try SetlistManifest.decoder().decode(SetlistManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.slides.map(\.file), ["001_a.jpg", "002_b.jpg"])
        XCTAssertEqual(m.slides[1].settings.length, .clip)
        XCTAssertNil(m.slides[1].settings.fit)
        XCTAssertEqual(m.defaults.length, 7)
        XCTAssertEqual(m.rows.count, TimelineRow.Kind.allCases.count)
    }
}
