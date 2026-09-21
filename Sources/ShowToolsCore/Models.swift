import Foundation

// MARK: - Library

public enum MediaKind: String, Codable, Sendable {
    case image
    /// GIF, APNG, animated HEIC/WebP — anything ImageIO reads as several frames.
    case animatedImage
    case video
}

/// One file the app has ingested. Carries no slide settings: those belong to
/// each use of the file in a show (see `Slide`).
public struct MediaItem: Identifiable, Hashable, Sendable {
    public var id: Int64
    /// Path inside the library's `Media/` folder. Relative, so renaming the
    /// library folder (the Spotlight toggle) breaks nothing.
    public var relativePath: String
    /// SHA-256 of the file's bytes, hex.
    public var hash: String
    public var kind: MediaKind
    /// Display size, orientation already applied.
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Seconds. Video: clip length. Animated image: one loop.
    public var duration: Double?
    public var ingestedAt: Date
    /// Where the file was copied from. Informational only; may no longer exist.
    public var sourcePath: String

    /// Stars, 0 (unrated) to 5. Belongs to the file, like tags will: the
    /// same in every show that uses it.
    public var rating: Int

    public init(id: Int64, relativePath: String, hash: String, kind: MediaKind,
                pixelWidth: Int, pixelHeight: Int, duration: Double?,
                ingestedAt: Date, sourcePath: String, rating: Int = 0) {
        self.rating = rating
        self.id = id
        self.relativePath = relativePath
        self.hash = hash
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.ingestedAt = ingestedAt
        self.sourcePath = sourcePath
    }

    public var fileName: String { (relativePath as NSString).lastPathComponent }
}

// MARK: - Slide settings

public enum TransitionStyle: String, Codable, CaseIterable, Sendable {
    case cut
    case dissolve
    case fadeThroughBlack
    case push
    case cover
    case swipe
    case bars
    case copyMachine
    case pageCurl
    case ripple
    case mod
    case flash
    case disintegrate

    public var title: String {
        switch self {
        case .cut: "Cut"
        case .dissolve: "Dissolve"
        case .fadeThroughBlack: "Fade Through Black"
        case .push: "Push"
        case .cover: "Cover"
        case .swipe: "Swipe"
        case .bars: "Bars"
        case .copyMachine: "Copy Machine"
        case .pageCurl: "Page Turn"
        case .ripple: "Ripple"
        case .mod: "Mod"
        case .flash: "Flash"
        case .disintegrate: "Disintegrate"
        }
    }

    /// Styles where `Direction` changes anything.
    public var usesDirection: Bool {
        switch self {
        case .push, .cover, .swipe, .bars, .copyMachine, .pageCurl: true
        default: false
        }
    }
}

/// The way the incoming slide travels.
public enum Direction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down

    public var title: String { rawValue.capitalized }
}

public struct Transition: Codable, Hashable, Sendable {
    public var style: TransitionStyle
    /// Seconds: how long the two pictures overlap.
    public var duration: Double
    public var direction: Direction
    /// Seconds before the join at which the overlap begins: 0 starts it at
    /// the join and runs it into the incoming slide (how every transition
    /// worked before the lane); `duration` ends it at the join; anything
    /// between straddles it (Phase 2c).
    public var lead: Double

    public init(style: TransitionStyle, duration: Double, direction: Direction = .left, lead: Double = 0) {
        self.style = style
        self.duration = duration
        self.direction = direction
        self.lead = lead
    }

    /// Field by field: shows saved before `lead` existed have no such key,
    /// and a synthesized decoder would drop the whole transition.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = try c.decode(TransitionStyle.self, forKey: .style)
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 1
        direction = (try? c.decodeIfPresent(Direction.self, forKey: .direction)) ?? .left
        lead = (try? c.decodeIfPresent(Double.self, forKey: .lead)) ?? 0
    }

    /// A new show's default (Jason, 2026-09-21): a 2 s dissolve centred on
    /// the join. Every join a slide hasn't been given its own transition for
    /// uses the show's default, so it's assigned automatically, and since a
    /// transition is measured from its join it stays with it when a seam is
    /// trimmed or rolled.
    public static let newShowDefault = Transition(style: .dissolve, duration: 2, lead: 1)
}

public enum Easing: String, Codable, CaseIterable, Sendable {
    case linear, easeInOut

    public func apply(_ p: Double) -> Double {
        switch self {
        case .linear: return p
        case .easeInOut: return p * p * (3 - 2 * p)
        }
    }
}

/// One end of a Ken Burns move, in the image's own terms.
public struct KenBurnsFrame: Codable, Hashable, Sendable {
    /// Centre of view, 0…1 across the image, measured from the left.
    public var x: Double
    /// Centre of view, 0…1 down the image, measured from the top.
    public var y: Double
    /// 1 = the slide's normal framing (per its fit); 2 = twice as close.
    public var zoom: Double

    public init(x: Double, y: Double, zoom: Double) {
        self.x = x; self.y = y; self.zoom = zoom
    }

    public static let centred = KenBurnsFrame(x: 0.5, y: 0.5, zoom: 1)

    /// Field by field, for the same reason as `ShowDefaults`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get(_ k: CodingKeys, _ fallback: Double) -> Double {
            ((try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil) ?? fallback
        }
        x = get(.x, 0.5); y = get(.y, 0.5); zoom = get(.zoom, 1)
    }
}

public struct KenBurns: Codable, Hashable, Sendable {
    public var start: KenBurnsFrame
    public var end: KenBurnsFrame
    public var easing: Easing
    /// −1…1, applied alongside the easing; see `Acceleration`. 0 leaves the
    /// move exactly as it was before the slider existed.
    public var acceleration: Double
    /// Hold still through the transitions in and out, moving only while
    /// the slide is on screen alone. Off by default.
    public var freezeOnTransition: Bool

    public init(start: KenBurnsFrame, end: KenBurnsFrame, easing: Easing = .easeInOut,
                acceleration: Double = 0, freezeOnTransition: Bool = false) {
        self.start = start; self.end = end; self.easing = easing
        self.acceleration = acceleration
        self.freezeOnTransition = freezeOnTransition
    }

    /// Field by field: shows saved before `acceleration` existed have no such
    /// key, and a synthesized decoder would throw away their frames.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(KenBurnsFrame.self, forKey: .start)
        end = try c.decode(KenBurnsFrame.self, forKey: .end)
        easing = (try? c.decodeIfPresent(Easing.self, forKey: .easing)) ?? .easeInOut
        acceleration = (try? c.decodeIfPresent(Double.self, forKey: .acceleration)) ?? 0
        freezeOnTransition = (try? c.decodeIfPresent(Bool.self, forKey: .freezeOnTransition)) ?? false
    }

    public func frame(at progress: Double) -> KenBurnsFrame {
        let p = easing.apply(Acceleration.shape(progress, amount: acceleration))
        func mix(_ a: Double, _ b: Double) -> Double { ShowToolsCore.mix(a, b, p) }
        return KenBurnsFrame(x: mix(start.x, end.x), y: mix(start.y, end.y),
                             zoom: mix(start.zoom, end.zoom))
    }
}

public enum KenBurnsSetting: Codable, Hashable, Sendable {
    case off
    /// A gentle move generated from the slide's id: varied across a show,
    /// but the same every time that slide plays.
    case auto
    case custom(KenBurns)
}

public enum Fit: String, Codable, CaseIterable, Sendable {
    case fill, fit, stretch

    public var title: String { rawValue.capitalized }
}

public enum SlideLength: Codable, Hashable, Sendable {
    case seconds(Double)
    /// The media's own length: a video's clip, one loop of an animation.
    case clip
}

/// Every field is optional: nil means "use the show's default".
public struct SlideSettings: Codable, Hashable, Sendable {
    public var length: SlideLength?
    public var transition: Transition?
    public var kenBurns: KenBurnsSetting?
    public var fit: Fit?
    /// Seconds into a video (or animation) where this slide starts playing
    /// it — set by trimming the front of its block. Nil means the beginning.
    public var clipStart: Double?
    /// The still placement on top of fit. Nil is the identity; there's no
    /// show-wide default for it.
    public var transform: Transform?
    /// What shows wherever the image doesn't cover the frame.
    public var background: SRGBColor?
    /// Nil means no rotation. There's no show-wide default for it.
    public var rotation: Rotation?

    public init(length: SlideLength? = nil, transition: Transition? = nil,
                kenBurns: KenBurnsSetting? = nil, fit: Fit? = nil, clipStart: Double? = nil,
                transform: Transform? = nil, background: SRGBColor? = nil,
                rotation: Rotation? = nil) {
        self.length = length
        self.transition = transition
        self.kenBurns = kenBurns
        self.fit = fit
        self.clipStart = clipStart
        self.transform = transform
        self.background = background
        self.rotation = rotation
    }

    /// Field by field, for the same reason as `ShowDefaults`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        length = (try? c.decodeIfPresent(SlideLength.self, forKey: .length)) ?? nil
        transition = (try? c.decodeIfPresent(Transition.self, forKey: .transition)) ?? nil
        kenBurns = (try? c.decodeIfPresent(KenBurnsSetting.self, forKey: .kenBurns)) ?? nil
        fit = (try? c.decodeIfPresent(Fit.self, forKey: .fit)) ?? nil
        clipStart = (try? c.decodeIfPresent(Double.self, forKey: .clipStart)) ?? nil
        transform = (try? c.decodeIfPresent(Transform.self, forKey: .transform)) ?? nil
        background = (try? c.decodeIfPresent(SRGBColor.self, forKey: .background)) ?? nil
        rotation = (try? c.decodeIfPresent(Rotation.self, forKey: .rotation)) ?? nil
    }
}

// MARK: - Shows

/// One use of a library item in a show. The same item can appear many times,
/// in one show or several, and each use keeps its own settings.
public struct Slide: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var itemID: Int64
    public var settings: SlideSettings

    public init(id: Int64, itemID: Int64, settings: SlideSettings = SlideSettings()) {
        self.id = id
        self.itemID = itemID
        self.settings = settings
    }
}

public struct ShowDefaults: Codable, Hashable, Sendable {
    public var length: Double = 5
    /// Shows saved earlier stored their own default, so they keep it.
    public var transition: Transition = .newShowDefault
    /// Only `.off` and `.auto` make sense as a show-wide default.
    public var kenBurns: KenBurnsSetting = .off
    /// New shows fit the whole image in (changed from fill 2026-09-21).
    /// Shows saved earlier stored their own value, so they keep it.
    public var fit: Fit = .fit
    public var background: SRGBColor = .black
    /// Video slides play their whole clip unless given a length.
    public var videoUsesClipLength: Bool = true
    public var loop: Bool = true

    public init() {}

    /// Field by field, so a value this version can't read falls back on its
    /// own instead of resetting every default (which the next save would
    /// then make permanent).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        let d = ShowDefaults()
        length = get(.length, d.length)
        transition = get(.transition, d.transition)
        kenBurns = get(.kenBurns, d.kenBurns)
        fit = get(.fit, d.fit)
        background = get(.background, d.background)
        videoUsesClipLength = get(.videoUsesClipLength, d.videoUsesClipLength)
        loop = get(.loop, d.loop)
    }
}

public struct Show: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var defaults: ShowDefaults
    public var slides: [Slide]
    /// The lane's images row.
    public var overlays: [OverlayClip]
    /// The collection it belongs to and draws its photos from.
    public var collectionID: Int64?

    public init(id: Int64, name: String, defaults: ShowDefaults = ShowDefaults(),
                slides: [Slide] = [], overlays: [OverlayClip] = [], collectionID: Int64? = nil) {
        self.id = id
        self.name = name
        self.defaults = defaults
        self.slides = slides
        self.overlays = overlays
        self.collectionID = collectionID
    }
}

/// A defined set of the library's files, which shows are built from (plan,
/// 2b). A file can be in several collections. `MediaCollection`, not
/// `Collection`, which is Swift's own protocol.
public struct MediaCollection: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    /// In the order they were added.
    public var itemIDs: [Int64]

    public init(id: Int64, name: String, itemIDs: [Int64] = []) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
    }
}
