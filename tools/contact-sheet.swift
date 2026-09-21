import AppKit
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
let cols = 3, w = 480, h = 270, pad = 24
let rows = (files.count + cols - 1) / cols
let img = NSImage(size: NSSize(width: cols * w, height: rows * (h + pad)))
img.lockFocus()
NSColor.darkGray.setFill(); NSRect(origin: .zero, size: img.size).fill()
for (i, f) in files.enumerated() {
    let x = (i % cols) * w, y = (rows - 1 - i / cols) * (h + pad)
    NSImage(contentsOf: f)!.draw(in: NSRect(x: x, y: y + pad, width: w - 4, height: h))
    (f.lastPathComponent as NSString).draw(at: NSPoint(x: x + 4, y: y + 4), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14)])
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
