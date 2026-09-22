import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ShowToolsCore

// Developer tool: drive the core without the app.
//
//   stcli ingest <library> <file-or-folder>...
//   stcli show   <library> <name>              new show from every item
//   stcli render <library> <showID> <width>x<height> <out-dir> <t>...
//
// `render` goes through the same Compositor the player uses, so it is also
// the first sketch of video export: frames at times, written to disk.

let args = CommandLine.arguments
func die(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }
guard args.count >= 3 else { die("usage: stcli ingest|show|render <library> …") }
let lib = try Library(root: URL(fileURLWithPath: args[2]))

switch args[1] {
case "ingest":
    for file in Ingest.collect(args.dropFirst(3).map { URL(fileURLWithPath: $0) }) {
        let hash = try Ingest.sha256(of: file)
        if let id = try lib.itemID(forHash: hash) { print("dup  #\(id) \(file.lastPathComponent)"); continue }
        do {
            let c = try await Ingest.copyIn(file, expectedHash: hash, mediaDir: lib.mediaURL)
            let item = try lib.insertItem(relativePath: c.relativePath, hash: hash, probe: c.probe, sourcePath: file.path)
            print("add  #\(item.id) \(item.relativePath) \(item.kind) \(item.pixelWidth)x\(item.pixelHeight) \(item.duration.map { String(format: "%.2fs", $0) } ?? "")")
        } catch { print("FAIL \(file.lastPathComponent): \(error)") }
    }

case "show":
    // Into the library's first collection, as the app puts a new show.
    let show = try lib.createShow(name: args[3], collectionID: try lib.allCollections().first?.id,
                                  itemIDs: try lib.allItems().map(\.id))
    print("show #\(show.id) \(show.name): \(show.slides.count) slides")

case "render":
    guard args.count >= 7, let showID = Int64(args[3]) else { die("render <lib> <showID> <WxH> <out> <t>…") }
    let dims = args[4].split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims[0], height: dims[1])
    let out = URL(fileURLWithPath: args[5])
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    guard let show = try lib.allShows().first(where: { $0.id == showID }) else { die("no show \(showID)") }
    let items = Dictionary(uniqueKeysWithValues: try lib.allItems().map { ($0.id, $0) })
    let timeline = ShowTimeline(show: show, items: items)
    let ctx = CIContext()
    var cache: [Int64: CIImage] = [:]
    for tArg in args.dropFirst(6) {
        guard let t = Double(tArg) else { continue }
        let state = timeline.frame(at: t)
        func load(_ item: MediaItem) -> CIImage? {
            if let hit = cache[item.id] { return hit }
            guard item.kind != .video,
                  let src = CGImageSourceCreateWithURL(lib.url(for: item) as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 3000] as CFDictionary) else { return nil }
            let ci = CIImage(cgImage: cg)
            cache[item.id] = ci
            return ci
        }
        let img = Compositor.compose(state, size: size, overlay: timeline.overlay(at: t),
                                     overlaySource: { load($0.overlay.item) }) { load($0.slide.item) }
        let file = out.appendingPathComponent(String(format: "t%07.3f.png", t))
        try ctx.writePNGRepresentation(of: img, to: file, format: .RGBA8,
                                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let desc: String = switch state {
        case .empty: "empty"
        case .background(_, let after): "background after #\(after + 1)"
        case .still(let l): "still #\(l.slide.index + 1) kb=\(String(format: "%.2f", l.kenBurnsFrame.zoom))"
        case .transition(let a, let b, let tr, let p): "\(tr.style.rawValue) #\(a.slide.index + 1)→#\(b.slide.index + 1) \(String(format: "%.2f", p))"
        }
        print(file.lastPathComponent, desc)
    }

default:
    die("unknown command \(args[1])")
}
