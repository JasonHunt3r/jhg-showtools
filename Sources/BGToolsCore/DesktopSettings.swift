import Foundation
import ShowToolsCore

/// What one monitor's Space plays (spec/bgtools.md, questions 1–11).
public enum PlayMode: Codable, Hashable, Sendable {
    /// A show as it was made.
    case show(Int64)
    /// A show's slides, each with its own settings, in a new order each pass.
    case shuffled(Int64)
    /// Pictures at random from a collection, with the desktop defaults.
    case collection(Int64)
    /// A different show each pass.
    case randomShow
    /// Pictures at random from the whole library, with the desktop defaults.
    case allFiles

    /// Modes that pick again at the end of every pass.
    public var rerollsEachPass: Bool {
        if case .show = self { return false }
        return true
    }
}

public struct ScreenSetting: Codable, Hashable, Sendable {
    /// The library folder. Each screen names its own (Jason, 2026-09-22).
    public var library: String
    public var mode: PlayMode
    /// Skips video and animated slides (per screen, Jason).
    public var stillsOnly: Bool
    /// Lets the show's music and videos be heard. Off by default; only one
    /// screen is heard at a time.
    public var sound: Bool

    public init(library: String, mode: PlayMode, stillsOnly: Bool = false, sound: Bool = false) {
        self.library = library
        self.mode = mode
        self.stillsOnly = stillsOnly
        self.sound = sound
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        library = try c.decode(String.self, forKey: .library)
        mode = try c.decode(PlayMode.self, forKey: .mode)
        stillsOnly = (try? c.decodeIfPresent(Bool.self, forKey: .stillsOnly)) ?? false
        sound = (try? c.decodeIfPresent(Bool.self, forKey: .sound)) ?? false
    }
}

/// Everything BGTools remembers. Screens are keyed by `screenID`: the
/// display's UUID and the Space's uuid, which last (Space numbers don't).
public struct DesktopSettings: Codable, Hashable, Sendable {
    /// Desktop Show on/off (the Control Center switch).
    public var on = true
    public var screens: [String: ScreenSetting] = [:]
    /// "Synchronize": one choice for every monitor and Space, in sync. The
    /// screens' own settings are kept while it's on. The stored key keeps
    /// its old name, `allSame` (called that until 2026-09-24) — renaming it
    /// would drop every saved setting on the next save unless migrated.
    public var allSame = false
    public var allSameSetting: ScreenSetting?
    /// Plays on any monitor or Space not seen before.
    public var newScreens: ScreenSetting?
    /// Length, transition, Pan and Zoom and fit for the random modes, whose
    /// pictures aren't slides of any show.
    public var randomDefaults: ShowDefaults = DesktopSettings.startingRandomDefaults

    public static var startingRandomDefaults: ShowDefaults {
        var d = ShowDefaults()
        d.length = 8
        d.fit = .fill
        return d
    }

    public init() {}

    /// Field by field, so one unreadable value doesn't lose the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        on = get(.on, true)
        screens = get(.screens, [:])
        allSame = get(.allSame, false)
        allSameSetting = get(.allSameSetting, nil)
        newScreens = get(.newScreens, nil)
        randomDefaults = get(.randomDefaults, Self.startingRandomDefaults)
    }

    public static func screenID(display: String, space: String) -> String {
        "\(display)/\(space.isEmpty ? "desktop1" : space)"
    }

    /// What a screen plays now: Synchronize's choice while it's on, else its
    /// own, else the "new screens" default. Nil plays nothing.
    public func setting(for screenID: String) -> ScreenSetting? {
        if allSame { return allSameSetting ?? newScreens }
        return screens[screenID] ?? newScreens
    }
}

/// Reads and writes the settings file. A missing or unreadable file gives
/// empty settings; it's never overwritten until something is changed.
public struct DesktopSettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/BGTools/settings.json`, or
    /// `BGTOOLS_SETTINGS` (tests never touch the real one).
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        if let p = environment["BGTOOLS_SETTINGS"] { return Self(url: URL(fileURLWithPath: p)) }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(url: dir.appendingPathComponent("BGTools/settings.json"))
    }

    public func load() -> DesktopSettings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(DesktopSettings.self, from: data) else { return DesktopSettings() }
        return s
    }

    public func save(_ settings: DesktopSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(settings).write(to: url, options: .atomic)
    }

    /// When the file last changed, to notice edits made elsewhere.
    public var modified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
