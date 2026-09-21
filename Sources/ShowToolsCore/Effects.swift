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
public struct RGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    public static let black = RGBColor(red: 0, green: 0, blue: 0)
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
