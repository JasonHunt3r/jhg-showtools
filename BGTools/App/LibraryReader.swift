import Foundation
import ShowToolsCore
import ShowToolsPlayback

/// One library, read-only (spec/bgtools.md, "BGTools' read path"). Polls
/// SQLite's change counter and rereads everything in one snapshot when
/// ShowTools saves, so the engines pick up edits on their next tick.
@MainActor
final class LibraryReader: ShowSource {
    let root: URL
    private let library: Library
    private(set) var shows: [Show] = []
    private(set) var items: [MediaItem] = []
    private var itemsByID: [Int64: MediaItem] = [:]
    private var lastChange = -1
    private var poll: Timer?

    init(root: URL) throws {
        self.root = root
        library = try Library(readingOnly: root)
        reload()
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func close() {
        poll?.invalidate()
        poll = nil
    }

    private func reload() {
        let now = library.changeCount
        guard now != lastChange else { return }
        do {
            let (s, i) = try library.snapshot { (try library.allShows(), try library.allItems()) }
            shows = s
            items = i
            itemsByID = Dictionary(uniqueKeysWithValues: i.map { ($0.id, $0) })
            lastChange = now
            Log.write("library read: \(s.count) shows, \(i.count) items")
        } catch {
            Log.write("library read failed: \(error)")
        }
    }

    // MARK: ShowSource

    /// The desktop always loops and, for now, plays silent (the sound
    /// switch comes with each screen's settings).
    func show(_ id: Int64) -> Show? {
        guard var s = shows.first(where: { $0.id == id }) else { return nil }
        s.defaults.loop = true
        s.music = []
        return s
    }

    func timeline(for show: Show) -> ShowTimeline { ShowTimeline(show: show, items: itemsByID) }
    func item(_ id: Int64) -> MediaItem? { itemsByID[id] }
    func url(for item: MediaItem) -> URL? { library.url(for: item) }
    func updateEditor(_ showID: Int64, _ change: (inout ShowEditorState) -> Void) {}
}
