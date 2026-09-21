import AppKit
import AVFoundation
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func draw(_ w: Int, _ h: Int, hue: CGFloat, label: String) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let c1 = NSColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor
    let c2 = NSColor(hue: hue + 0.15, saturation: 0.8, brightness: 0.35, alpha: 1).cgColor
    let grad = CGGradient(colorsSpace: nil, colors: [c1, c2] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])
    // Grid so Ken Burns motion is visible.
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.setLineWidth(3)
    for x in stride(from: 0, to: w, by: w / 12) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)) }
    for y in stride(from: 0, to: h, by: h / 8) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)) }
    ctx.strokePath()
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = ns
    let font = NSFont.boldSystemFont(ofSize: CGFloat(min(w, h)) / 3)
    let s = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white])
    let sz = s.size()
    s.draw(at: CGPoint(x: (CGFloat(w) - sz.width) / 2, y: (CGFloat(h) - sz.height) / 2))
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String, _ type: UTType) {
    let d = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    CGImageDestinationFinalize(d)
}

let sizes = [(4000, 3000), (3000, 4000), (6000, 4000), (2400, 2400), (4032, 3024), (1920, 1080)]
for i in 0..<8 {
    let (w, h) = sizes[i % sizes.count]
    save(draw(w, h, hue: CGFloat(i) / 8, label: "\(i + 1)"), String(format: "photo_%02d.jpg", i + 1), .jpeg)
}
save(draw(4000, 3000, hue: 0.3, label: "HEIC"), "heic_test.heic", .heic)

// Animated GIF: 6 frames, 0.2s each.
let gif = CGImageDestinationCreateWithURL(out.appendingPathComponent("spinner.gif") as CFURL, UTType.gif.identifier as CFString, 6, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for f in 0..<6 {
    CGImageDestinationAddImage(gif, draw(600, 400, hue: CGFloat(f) / 6, label: "G\(f + 1)"),
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
}
CGImageDestinationFinalize(gif)

// 4-second H.264 video with a moving counter.
let vurl = out.appendingPathComponent("clip.mov")
try? FileManager.default.removeItem(at: vurl)
let writer = try! AVAssetWriter(outputURL: vurl, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for f in 0..<120 {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    let img = draw(1280, 720, hue: CGFloat(f) / 120, label: String(format: "%.1f", Double(f) / 30))
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32ARGB, nil, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: 1280, height: 720, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1280, height: 720))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: 30))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("done", writer.status.rawValue)
