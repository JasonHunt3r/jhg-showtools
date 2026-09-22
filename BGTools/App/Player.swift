import Foundation
import BGToolsCore
import ShowToolsCore
import ShowToolsPlayback

/// Plays one screen's setting (or All same's, on every screen at once):
/// builds its show, follows library edits, and picks again at the end of
/// each pass for the random modes. It's the engine's `ShowSource`.
@MainActor
final class Player: ShowSource {
    let setting: ScreenSetting
    private let reader: LibraryReader
    let randomDefaults: ShowDefaults
    private var built: DesktopShow.Built?
    private(set) var engine: PlaybackEngine!
    private var seenGeneration: Int
    private var pass = 0
    private var timer: Timer?

    /// Only one screen is heard: the controller sets this on the player
    /// for the main display's current Space.
    var audible = false {
        didSet {
            guard audible != oldValue else { return }
            engine.media.muteVideo = !hears
            if let built { self.built = DesktopShow.refresh(built, effective, from: reader.contents) }
        }
    }
    private var hears: Bool { audible && setting.sound }
    private var effective: ScreenSetting {
        var s = setting
        s.sound = hears
        return s
    }

    init(setting: ScreenSetting, reader: LibraryReader, randomDefaults: ShowDefaults) {
        self.setting = setting
        self.reader = reader
        self.randomDefaults = randomDefaults
        seenGeneration = reader.generation
        built = pick()
        engine = PlaybackEngine(showID: DesktopShow.id, model: self)
        engine.media.muteVideo = true
        engine.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine.shutdown()
    }

    /// Whether a change to the desktop defaults matters to this player:
    /// only the random-pictures modes use them.
    var usesRandomDefaults: Bool {
        switch setting.mode {
        case .collection, .allFiles: return true
        case .show, .shuffled, .randomShow: return false
        }
    }

    private func pick() -> DesktopShow.Built? {
        var rng = SystemRandomNumberGenerator()
        let b = DesktopShow.build(effective, from: reader.contents, randomDefaults: randomDefaults, rng: &rng)
        Log.write(b.map { "playing \"\($0.show.name)\", \($0.show.slides.count) slides (\(setting.mode))" }
                  ?? "nothing to play for \(setting.mode)")
        return b
    }

    private func tick() {
        if reader.generation != seenGeneration {
            seenGeneration = reader.generation
            built = built.flatMap { DesktopShow.refresh($0, effective, from: reader.contents) } ?? pick()
        }
        // At the end of a pass, the random modes pick again from the top.
        guard setting.mode.rerollsEachPass, engine.duration > 0 else { return }
        let p = Int(engine.now / engine.duration)
        if p != pass {
            built = pick()
            engine.restartWithLatest()
            pass = 0
        }
    }

    // MARK: ShowSource

    func show(_ id: Int64) -> Show? { built?.show }
    func timeline(for show: Show) -> ShowTimeline { ShowTimeline(show: show, items: reader.contents.items) }
    func item(_ id: Int64) -> MediaItem? { reader.contents.items[id] }
    func url(for item: MediaItem) -> URL? { reader.url(for: item) }
    func updateEditor(_ showID: Int64, _ change: (inout ShowEditorState) -> Void) {}
}
