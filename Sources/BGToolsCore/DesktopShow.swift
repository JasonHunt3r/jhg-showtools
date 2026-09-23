import Foundation
import ShowToolsCore

/// Builds the show a screen plays from its setting and the library as read.
/// The desktop always loops; the random modes use the desktop defaults.
public enum DesktopShow {
    /// The id every built show carries: the engine asks for it by this.
    public static let id: Int64 = -1
    /// A random pass holds at most this many pictures; the next pass picks
    /// again, so a big library still gets round.
    public static let randomPassLimit = 300

    public struct Library: Sendable {
        public var shows: [Show]
        public var collections: [MediaCollection]
        public var items: [Int64: MediaItem]

        public init(shows: [Show], collections: [MediaCollection], items: [Int64: MediaItem]) {
            self.shows = shows
            self.collections = collections
            self.items = items
        }
    }

    /// A built show, and the library show it was made from (nil for the
    /// random-pictures modes).
    public struct Built: Hashable, Sendable {
        public var show: Show
        public var sourceShowID: Int64?
    }

    /// Nil when there's nothing to play: the show or collection is gone or
    /// empty, or Stills only leaves nothing.
    public static func build<G: RandomNumberGenerator>(_ setting: ScreenSetting, from lib: Library,
                                                       randomDefaults: ShowDefaults, rng: inout G) -> Built? {
        switch setting.mode {
        case .show(let sid):
            return lib.shows.first { $0.id == sid }.flatMap { fromShow($0, setting, lib, shuffle: false, rng: &rng) }
        case .shuffled(let sid):
            return lib.shows.first { $0.id == sid }.flatMap { fromShow($0, setting, lib, shuffle: true, rng: &rng) }
        case .collection(let cid):
            guard let c = lib.collections.first(where: { $0.id == cid }) else { return nil }
            return random(c.itemIDs, name: c.name, setting, lib, randomDefaults, rng: &rng)
        case .allFiles:
            return random(Array(lib.items.keys), name: "All files", setting, lib, randomDefaults, rng: &rng)
        case .randomShow:
            for s in lib.shows.shuffled(using: &rng) {
                if let built = fromShow(s, setting, lib, shuffle: false, rng: &rng) { return built }
            }
            return nil
        }
    }

    /// After the library changes mid-pass: the same pass, updated. A show's
    /// slides take their latest settings (a shuffled one keeps its order,
    /// new slides at the end); random pictures keep theirs, minus any gone.
    public static func refresh(_ current: Built, _ setting: ScreenSetting, from lib: Library) -> Built? {
        guard let sid = current.sourceShowID else {
            var s = current.show
            s.slides = s.slides.filter { playable($0.itemID, setting, lib) }
            return s.slides.isEmpty ? nil : Built(show: s, sourceShowID: nil)
        }
        var rng = SystemRandomNumberGenerator()
        guard let source = lib.shows.first(where: { $0.id == sid }),
              var fresh = fromShow(source, setting, lib, shuffle: false, rng: &rng) else { return nil }
        if case .shuffled = setting.mode {
            let order = Dictionary(current.show.slides.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            fresh.show.slides.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        }
        return fresh
    }

    static func playable(_ itemID: Int64, _ setting: ScreenSetting, _ lib: Library) -> Bool {
        guard let item = lib.items[itemID], item.kind.isPicture else { return false }
        return !setting.stillsOnly || item.kind == .image
    }

    private static func fromShow<G: RandomNumberGenerator>(_ source: Show, _ setting: ScreenSetting, _ lib: Library,
                                                           shuffle: Bool, rng: inout G) -> Built? {
        var s = source
        s.id = id
        s.slides = s.slides.filter { playable($0.itemID, setting, lib) }
        guard !s.slides.isEmpty else { return nil }
        if shuffle { s.slides.shuffle(using: &rng) }
        s.overlays = s.overlays.filter { playable($0.itemID, setting, lib) }
        if !setting.sound { s.music = [] }
        s.defaults.loop = true
        s.editor = ShowEditorState()
        return Built(show: s, sourceShowID: source.id)
    }

    private static func random<G: RandomNumberGenerator>(_ itemIDs: [Int64], name: String, _ setting: ScreenSetting,
                                                         _ lib: Library, _ defaults: ShowDefaults,
                                                         rng: inout G) -> Built? {
        var pool = Array(Set(itemIDs.filter { playable($0, setting, lib) }))
        guard !pool.isEmpty else { return nil }
        pool.sort()             // Set order isn't stable; the shuffle is the only randomness
        pool.shuffle(using: &rng)
        // The slide's id is the item's, so each picture keeps its own auto
        // Pan and Zoom move every time it comes round.
        let slides = pool.prefix(randomPassLimit).map { Slide(id: $0, itemID: $0) }
        var d = defaults
        d.loop = true
        return Built(show: Show(id: id, name: name, defaults: d, slides: Array(slides)), sourceShowID: nil)
    }
}
