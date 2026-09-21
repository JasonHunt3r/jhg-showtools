import Foundation

// Motion effects that stack on a slide (Phase 2a). Each one is sampled at a
// progress 0…1 through the slide's visible span, like Ken Burns.

/// The centre-zero acceleration slider shared by every motion effect.
///
/// `amount` runs −1…1: 0 is constant speed, above 0 starts slow and speeds
/// up, below 0 starts fast and slows down. Either way the move still starts
/// at 0 and finishes at 1, so it only changes the timing, never where a move
/// ends — a match-cut end frame stays put.
public enum Acceleration {
    public static func shape(_ p: Double, amount: Double) -> Double {
        let p = min(max(p, 0), 1)
        let a = min(max(amount, -1), 1)
        // At ±1 the curve is a quartic: it starts (or ends) at zero speed.
        let k = 1 + 3 * abs(a)
        return a >= 0 ? pow(p, k) : 1 - pow(1 - p, k)
    }
}

/// An sRGB colour, components 0…1.
public struct SRGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    public static let black = SRGBColor(red: 0, green: 0, blue: 0)
}

/// A point in the image's own terms, as `KenBurnsFrame` uses: 0…1 across
/// and down the image from its top left. It can lie outside 0…1 (off the
/// image), which a rotation pivot is allowed to do.
public struct ImagePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let centre = ImagePoint(x: 0.5, y: 0.5)
}

/// Where a slide's image sits when nothing is moving it (Final Cut's
/// Transform). Applied on top of the slide's fit; the motion effects add to
/// it. The identity leaves the image exactly where fit puts it, so every
/// slide has a placement without any effect switched on.
public struct Transform: Codable, Hashable, Sendable {
    /// Shift from where fit puts it, as a fraction of the frame's width and
    /// height (0.1 = a tenth of the frame to the right / down).
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    /// 1 = as fitted. Below 1 the background shows round it.
    public var scale: Double = 1
    /// Degrees, clockwise.
    public var rotation: Double = 0
    /// What scale and rotation turn around, pinned to the image.
    public var anchor: ImagePoint = .centre

    public init() {}

    public static let identity = Transform()

    /// Field by field, for the same reason as `ShowDefaults`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        let d = Transform()
        offsetX = get(.offsetX, d.offsetX)
        offsetY = get(.offsetY, d.offsetY)
        scale = get(.scale, d.scale)
        rotation = get(.rotation, d.rotation)
        anchor = get(.anchor, d.anchor)
    }
}

/// A spin, with Ken Burns or on its own.
public struct Rotation: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Degrees per second. Trimming the slide changes where it ends.
        case speed
        /// Start and end angles. Trimming changes the speed, not the end,
        /// so this is the mode for match cuts.
        case angles
    }

    /// The effect's checkbox. Off keeps the settings.
    public var enabled: Bool = true
    public var mode: Mode = .angles
    /// Degrees, clockwise. The starting angle in both modes.
    public var startAngle: Double = 0
    /// Degrees, clockwise. Angles mode only.
    public var endAngle: Double = 0
    /// Degrees per second, clockwise if positive. Speed mode only. This is
    /// the average speed: acceleration reshapes the timing around it.
    public var speed: Double = 0
    /// −1…1; see `Acceleration`.
    public var acceleration: Double = 0
    /// Where the rotation turns around, pinned to the image.
    public var pivotStart: ImagePoint = .centre
    public var pivotEnd: ImagePoint = .centre
    /// The pivot grids' Lock checkbox: the end pivot follows the start.
    public var pivotLocked: Bool = true
    /// Hold still through the transitions in and out. Off by default.
    public var freezeOnTransition: Bool = false

    public init() {}

    /// Field by field, for the same reason as `ShowDefaults`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        let d = Rotation()
        enabled = get(.enabled, d.enabled)
        mode = get(.mode, d.mode)
        startAngle = get(.startAngle, d.startAngle)
        endAngle = get(.endAngle, d.endAngle)
        speed = get(.speed, d.speed)
        acceleration = get(.acceleration, d.acceleration)
        pivotStart = get(.pivotStart, d.pivotStart)
        pivotEnd = get(.pivotEnd, d.pivotEnd)
        pivotLocked = get(.pivotLocked, d.pivotLocked)
        freezeOnTransition = get(.freezeOnTransition, d.freezeOnTransition)
    }

    /// The whole turn, in degrees, over `span` seconds of movement.
    public func sweep(span: Double) -> Double {
        switch mode {
        case .speed: speed * max(span, 0)
        case .angles: endAngle - startAngle
        }
    }

    /// The angle at `progress` 0…1 through `span` seconds of movement.
    public func angle(at progress: Double, span: Double) -> Double {
        let p = Acceleration.shape(progress, amount: acceleration)
        switch mode {
        case .speed: return startAngle + sweep(span: span) * p
        case .angles: return mix(startAngle, endAngle, p)
        }
    }

    public func pivot(at progress: Double) -> ImagePoint {
        if pivotLocked { return pivotStart }
        let p = Acceleration.shape(progress, amount: acceleration)
        return ImagePoint(x: mix(pivotStart.x, pivotEnd.x, p), y: mix(pivotStart.y, pivotEnd.y, p))
    }
}

/// Lands exactly on `b` at 1, so an end frame set for a match cut is the end
/// frame that plays. (`a + (b - a) * p` can miss it by a rounding step.)
func mix(_ a: Double, _ b: Double, _ p: Double) -> Double {
    a * (1 - p) + b * p
}

/// Changes to a Transform made by dragging on the picture (the handles).
///
/// Points are in picture coordinates with y running down, as a view draws,
/// in the same units as `size`. Only differences between points matter, so
/// any common origin works. `anchor` is where the Transform's anchor sits
/// before the Transform is applied (fit and Ken Burns only).
///
/// In these coordinates the Transform is  q ↦ A + s·R(θ)·(q − A) + offset,
/// where R is the usual rotation matrix, which turns clockwise when y runs
/// down, matching the Transform's clockwise degrees.
public enum TransformEdit {
    public static func offset(_ t: Transform, size: CGSize) -> CGPoint {
        CGPoint(x: t.offsetX * size.width, y: t.offsetY * size.height)
    }

    public static func withOffset(_ t: Transform, _ o: CGPoint, size: CGSize) -> Transform {
        var t = t
        t.offsetX = Double(o.x / size.width)
        t.offsetY = Double(o.y / size.height)
        return t
    }

    /// Scaled by `k` about the on-screen point `p`, which stays put: the
    /// opposite corner for a corner drag, the centre with Option.
    ///   k·(T(q) − p) + p  =  A + k·s·R·(q − A) + [k·offset + (1 − k)·(p − A)]
    public static func scaled(_ t: Transform, by k: Double, about p: CGPoint,
                              anchor A: CGPoint, size: CGSize) -> Transform {
        var out = t
        out.scale = t.scale * k
        let o = offset(t, size: size), kk = CGFloat(k)
        return withOffset(out, CGPoint(x: kk * o.x + (1 - kk) * (p.x - A.x),
                                       y: kk * o.y + (1 - kk) * (p.y - A.y)), size: size)
    }

    /// The anchor moved to the on-screen point `x` without moving the image:
    /// the offset takes up the difference. Returns the new Transform and the
    /// new anchor's position before the Transform, for the caller to turn
    /// back into an image point.
    public static func movingAnchor(_ t: Transform, to x: CGPoint, anchor A: CGPoint,
                                    size: CGSize) -> (Transform, CGPoint) {
        let o = offset(t, size: size)
        let th = CGFloat(t.rotation) * .pi / 180, s = CGFloat(max(t.scale, 0.0001))
        let c = cos(th), sn = sin(th)
        // New anchor B before the Transform, from s·R·(B − A) = x − offset − A.
        let v = CGPoint(x: x.x - o.x - A.x, y: x.y - o.y - A.y)
        let B = CGPoint(x: A.x + (c * v.x + sn * v.y) / s, y: A.y + (-sn * v.x + c * v.y) / s)
        // Same picture about B: offset' = offset + (A − B) − s·R·(A − B).
        let d = CGPoint(x: A.x - B.x, y: A.y - B.y)
        let sRd = CGPoint(x: s * (c * d.x - sn * d.y), y: s * (sn * d.x + c * d.y))
        return (withOffset(t, CGPoint(x: o.x + d.x - sRd.x, y: o.y + d.y - sRd.y), size: size), B)
    }
}

// MARK: - The lane's images row (Phase 2c)

/// How an image in the lane mixes with the picture under it.
public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, softLight, lighten, darken, difference, add

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .softLight: "Soft Light"
        case .lighten: "Lighten"
        case .darken: "Darken"
        case .difference: "Difference"
        case .add: "Add"
        }
    }
}

/// An image in the lane's images row, laid over the finished picture:
/// picture-in-picture, an overlap, a PNG or HEIC with transparency.
///
/// It sits at a time on the show's clock. Whether it should instead move
/// with the slide under it when slides are trimmed or reordered is parked
/// until Jason has his own files to test with (plan, Phase 2c).
public struct OverlayClip: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var itemID: Int64
    /// Seconds from the start of the show.
    public var start: Double
    public var length: Double
    public var fit: Fit = .fit
    public var transform: Transform = .identity
    /// 0…1.
    public var opacity: Double = 1
    public var blend: BlendMode = .normal
    /// Seconds to fade in from nothing and out to nothing.
    public var fadeIn: Double = 0.5
    public var fadeOut: Double = 0.5

    public init(itemID: Int64, start: Double, length: Double) {
        self.itemID = itemID
        self.start = start
        self.length = length
    }

    /// Field by field, for the same reason as `ShowDefaults`. The file and
    /// the timing have no sensible fallback, so without them it fails, and
    /// the list it's in skips it (see `decodeList`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        itemID = try c.decode(Int64.self, forKey: .itemID)
        start = try c.decode(Double.self, forKey: .start)
        length = try c.decode(Double.self, forKey: .length)
        id = get(.id, UUID())
        fit = get(.fit, .fit)
        transform = get(.transform, .identity)
        opacity = get(.opacity, 1)
        blend = get(.blend, .normal)
        fadeIn = get(.fadeIn, 0.5)
        fadeOut = get(.fadeOut, 0.5)
    }

    /// A saved list, keeping every clip that can be read: one unreadable
    /// clip mustn't cost the rest (the next save would make that permanent).
    public static func decodeList(_ json: String) -> [OverlayClip] {
        guard let array = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { return [] }
        return array.compactMap { element in
            guard let data = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? JSONDecoder().decode(OverlayClip.self, from: data)
        }
    }
}
