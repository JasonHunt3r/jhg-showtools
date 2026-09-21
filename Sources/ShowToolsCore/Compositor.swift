import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a `FrameState` into a picture of a given size.
///
/// Pure: it knows nothing about clocks, windows or files. The source closure
/// hands it each layer's media as a CIImage (orientation applied, extent at
/// the origin). The player calls this every display frame; a video exporter
/// would call it once per output frame.
public enum Compositor {

    public static func compose(_ state: FrameState, size: CGSize,
                               source: (Layer) -> CIImage?) -> CIImage {
        let out = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: out)

        func place(_ layer: Layer) -> CIImage {
            guard let img = source(layer) else { return black }
            let c = layer.slide.background
            let ground = CIImage(color: CIColor(red: c.red, green: c.green, blue: c.blue)).cropped(to: out)
            let spin = layer.slide.rotation == nil ? nil : (angle: layer.rotationAngle, pivot: layer.rotationPivot)
            return placed(img, fit: layer.slide.fit, kb: layer.kenBurnsFrame,
                          transform: layer.slide.transform, spin: spin, in: size)
                .composited(over: ground)
        }

        switch state {
        case .empty:
            return black
        case .still(let layer):
            return place(layer)
        case .transition(let from, let to, let t, let progress):
            let a = place(from), b = place(to)
            return transition(t, from: a, to: b, progress: progress, extent: out)
                .composited(over: black)
                .cropped(to: out)
        }
    }

    // MARK: Framing

    /// The part of the image that fills the output, in image pixels with
    /// the origin at the **top left** (as the Ken Burns editor draws it).
    ///
    /// Works per axis: the base framing (fill, fit or stretch) sets how much
    /// of the image the output covers; Ken Burns zoom narrows that; the
    /// centre is then clamped so a fill never shows past the image's edge,
    /// while a fit centres whatever is smaller than the frame (letterbox).
    /// The region can be larger than the image (fit), never smaller than zero.
    public static func viewRegion(imageSize: CGSize, fit: Fit, kb: KenBurnsFrame,
                                  outputSize size: CGSize) -> CGRect {
        let W = imageSize.width, H = imageSize.height
        guard W > 0, H > 0, size.width > 0, size.height > 0 else { return .zero }

        var regionW: CGFloat, regionH: CGFloat
        switch fit {
        case .fill, .fit:
            let s = fit == .fill ? max(size.width / W, size.height / H)
                                 : min(size.width / W, size.height / H)
            regionW = size.width / s
            regionH = size.height / s
        case .stretch:
            regionW = W
            regionH = H
        }
        let z = CGFloat(max(kb.zoom, 0.05))
        regionW /= z
        regionH /= z

        func axisOrigin(centre: CGFloat, region: CGFloat, span: CGFloat) -> CGFloat {
            if region >= span { return (span - region) / 2 }
            let c = min(max(centre, region / 2), span - region / 2)
            return c - region / 2
        }
        return CGRect(x: axisOrigin(centre: CGFloat(kb.x) * W, region: regionW, span: W),
                      y: axisOrigin(centre: CGFloat(kb.y) * H, region: regionH, span: H),
                      width: regionW, height: regionH)
    }

    /// The part of the image to show, scaled to fill `size` exactly.
    public static func placed(_ image: CIImage, fit: Fit, kb: KenBurnsFrame,
                              in size: CGSize) -> CIImage {
        placed(image, fit: fit, kb: kb, transform: .identity, spin: nil, in: size)
    }

    /// The image placed in a `size` frame: fit and Ken Burns first, then the
    /// Rotation effect's spin, then the slide's Transform. Whatever the image
    /// no longer covers is left clear, for the background to show through.
    public static func placed(_ image: CIImage, fit: Fit, kb: KenBurnsFrame,
                              transform: Transform, spin: (angle: Double, pivot: ImagePoint)?,
                              in size: CGSize) -> CIImage {
        guard let m = placement(imageExtent: image.extent, fit: fit, kb: kb,
                                transform: transform, spin: spin, outputSize: size)
        else { return image }
        return image.transformed(by: m)
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Image pixels (Core Image coordinates) → output pixels. Nil for an
    /// empty image or frame.
    ///
    /// Angles are clockwise on screen, and offsets run right and down, as the
    /// editor shows them; Core Image's y runs up, hence the sign flips.
    /// Scale and rotation can't distort (the Transform is a similarity), so
    /// the spin can be applied before it and still turn around its pivot as
    /// the pivot ends up on screen.
    public static func placement(imageExtent e: CGRect, fit: Fit, kb: KenBurnsFrame,
                                 transform: Transform, spin: (angle: Double, pivot: ImagePoint)?,
                                 outputSize size: CGSize) -> CGAffineTransform? {
        let W = e.width, H = e.height
        let r = viewRegion(imageSize: CGSize(width: W, height: H), fit: fit, kb: kb, outputSize: size)
        guard r.width > 0, r.height > 0 else { return nil }
        // Core Image measures y from the bottom.
        let y0 = H - r.maxY
        var m = CGAffineTransform(translationX: -(e.minX + r.minX), y: -(e.minY + y0))
            .concatenating(CGAffineTransform(scaleX: size.width / r.width,
                                             y: size.height / r.height))

        /// An image point, as the base framing puts it in the output. Both
        /// centres come from here, before either turn is applied: measured
        /// after the spin, the anchor would travel round with it and the
        /// Transform would make the whole picture wobble.
        let base = m
        func onScreen(_ p: ImagePoint) -> CGPoint {
            CGPoint(x: e.minX + CGFloat(p.x) * W, y: e.minY + CGFloat(1 - p.y) * H).applying(base)
        }
        func about(_ c: CGPoint, _ t: CGAffineTransform) -> CGAffineTransform {
            CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(t)
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        }
        func clockwise(_ degrees: Double) -> CGAffineTransform {
            CGAffineTransform(rotationAngle: -CGFloat(degrees) * .pi / 180)
        }

        if let spin, spin.angle != 0 {
            m = m.concatenating(about(onScreen(spin.pivot), clockwise(spin.angle)))
        }
        if transform != .identity {
            let s = CGFloat(max(transform.scale, 0.01))
            m = m.concatenating(about(onScreen(transform.anchor),
                                      CGAffineTransform(scaleX: s, y: s)
                                          .concatenating(clockwise(transform.rotation))))
                 .concatenating(CGAffineTransform(translationX: CGFloat(transform.offsetX) * size.width,
                                                  y: -CGFloat(transform.offsetY) * size.height))
        }
        return m
    }

    // MARK: Transitions

    static func transition(_ t: Transition, from a: CIImage, to b: CIImage,
                           progress p: Double, extent: CGRect) -> CIImage {
        let p = Float(min(max(p, 0), 1))
        // Ripple and mod bend the picture and sample outside it: give them
        // edge pixels to find there, not transparent black. The others
        // misbehave with an endless image (page turn, bars), so they get the
        // plain frame.
        let a = [.ripple, .mod].contains(t.style) ? a.clampedToExtent() : a.cropped(to: extent)
        let b = [.ripple, .mod].contains(t.style) ? b.clampedToExtent() : b.cropped(to: extent)
        let centre = CGPoint(x: extent.midX, y: extent.midY)

        switch t.style {
        case .cut:
            return b

        case .dissolve:
            let f = CIFilter.dissolveTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            return f.outputImage ?? b

        case .fadeThroughBlack:
            let black = CIImage(color: .black).cropped(to: extent)
            let f = CIFilter.dissolveTransition()
            if p < 0.5 {
                f.inputImage = a; f.targetImage = black; f.time = p * 2
            } else {
                f.inputImage = black; f.targetImage = b; f.time = (p - 0.5) * 2
            }
            return f.outputImage ?? b

        case .push, .cover:
            let e = CGFloat(Easing.easeInOut.apply(Double(p)))
            let d = unit(t.direction)
            let w = extent.width, h = extent.height
            // Incoming starts one frame away, opposite the travel direction.
            let inbound = b.transformed(by: .init(translationX: -d.dx * w * (1 - e),
                                                                      y: -d.dy * h * (1 - e)))
            if t.style == .cover { return inbound.composited(over: a) }
            let outbound = a.transformed(by: .init(translationX: d.dx * w * e, y: d.dy * h * e))
            return inbound.composited(over: outbound)

        case .swipe:
            let f = CIFilter.swipeTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.extent = extent; f.angle = angle(t.direction)
            f.width = Float(extent.width * 0.3); f.opacity = 0
            return f.outputImage ?? b

        case .bars:
            let f = CIFilter.barsSwipeTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.angle = angle(t.direction); f.width = Float(extent.width / 12)
            f.barOffset = 10
            return f.outputImage ?? b

        case .copyMachine:
            let f = CIFilter.copyMachineTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.extent = extent; f.angle = angle(t.direction)
            f.width = Float(extent.width * 0.15); f.opacity = 1.3
            f.color = CIColor(red: 0.6, green: 1, blue: 0.8)
            return f.outputImage ?? b

        case .pageCurl:
            let f = CIFilter.pageCurlTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            // On this macOS the curl renders flat: a page turn whose back
            // shows as a band. Darkening the back is what makes it read.
            let back = CIFilter.exposureAdjust()
            back.inputImage = a; back.ev = -1.2
            f.backsideImage = back.outputImage ?? a; f.extent = extent
            f.angle = angle(t.direction)
            f.radius = Float(min(extent.width, extent.height) * 0.18)
            return f.outputImage ?? b

        case .ripple:
            let f = CIFilter.rippleTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.center = centre; f.extent = extent
            f.shadingImage = shading(extent)
            f.width = Float(extent.width * 0.1); f.scale = 50
            return f.outputImage ?? b

        case .mod:
            let f = CIFilter.modTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.center = centre; f.angle = 2
            f.radius = Float(extent.width * 0.15); f.compression = 300
            return f.outputImage ?? b

        case .flash:
            let f = CIFilter.flashTransition()
            // The filter's first ~40% is a pinpoint; start where the flash
            // is visible so it builds over the whole transition.
            f.inputImage = a; f.targetImage = b; f.time = 0.4 + 0.6 * p
            f.center = centre; f.extent = extent
            f.color = CIColor(red: 1, green: 0.95, blue: 0.85)
            f.maxStriationRadius = 2.58; f.striationStrength = 0.5
            f.striationContrast = 1.375; f.fadeThreshold = 0.85
            return f.outputImage ?? b


        case .disintegrate:
            let f = CIFilter.disintegrateWithMaskTransition()
            f.inputImage = a; f.targetImage = b; f.time = p
            f.maskImage = noiseMask(extent)
            f.shadowRadius = 8; f.shadowDensity = 0.65
            f.shadowOffset = CGPoint(x: 0, y: -10)
            return f.outputImage ?? b
        }
    }

    /// Direction the incoming slide travels, as a unit step.
    static func unit(_ d: Direction) -> (dx: CGFloat, dy: CGFloat) {
        switch d {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, 1)
        case .down: (0, -1)
        }
    }

    static func angle(_ d: Direction) -> Float {
        switch d {
        case .left: .pi
        case .right: 0
        case .up: .pi / 2
        case .down: -.pi / 2
        }
    }

    static func shading(_ extent: CGRect) -> CIImage {
        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: extent.midX, y: extent.midY)
        g.radius0 = 0
        g.radius1 = Float(max(extent.width, extent.height) / 2)
        g.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0.12)
        g.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        return (g.outputImage ?? CIImage.empty()).cropped(to: extent)
    }

    /// Soft blotchy noise: the grain the disintegrate transition dissolves along.
    static func noiseMask(_ extent: CGRect) -> CIImage {
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
        let mono = CIFilter.colorControls()
        mono.inputImage = noise.transformed(by: .init(scaleX: 6, y: 6))
        mono.saturation = 0
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = mono.outputImage
        blur.radius = 4
        return (blur.outputImage ?? noise).cropped(to: extent)
    }
}
