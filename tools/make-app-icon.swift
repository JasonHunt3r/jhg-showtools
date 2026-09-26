// Renders the app icon's SVG into the asset catalog's AppIcon set.
//
//   swift tools/make-app-icon.swift
//
// Source: Resources/AppIcon.svg (Jason's, drawn in Illustrator on a 400
// pt artboard). Output: Resources/Assets.xcassets/AppIcon.appiconset, every
// macOS size at 1x and 2x, plus its Contents.json. Rerun after editing the
// SVG; the PNGs are committed so a build needs no extra step.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svg = root.appendingPathComponent("Resources/AppIcon.svg")
let set = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")

guard let image = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write("Can't read \(svg.path)\n".data(using: .utf8)!)
    exit(1)
}
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
        entries.append("""
            { "idiom" : "mac", "size" : "\(points)x\(points)", "scale" : "\(scale)x", "filename" : "\(name)" }
        """)
    }
}
let contents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n")
    + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let catalog = root.appendingPathComponent("Resources/Assets.xcassets/Contents.json")
try "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".write(to: catalog, atomically: true, encoding: .utf8)
print("Wrote \(entries.count) sizes to \(set.path)")
