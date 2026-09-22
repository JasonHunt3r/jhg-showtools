import Foundation
import BGToolsCore
import ShowToolsCore

/// One library, read-only (spec/bgtools.md, "BGTools' read path"). Polls
/// SQLite's change counter and rereads everything in one snapshot when
/// ShowTools saves; `generation` goes up each time, for the players.
@MainActor
final class LibraryReader {
    let root: URL
    private let library: Library
    private(set) var contents = DesktopShow.Library(shows: [], collections: [], items: [:])
    private(set) var generation = 0
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

    func url(for item: MediaItem) -> URL { library.url(for: item) }

    private func reload() {
        let now = library.changeCount
        guard now != lastChange else { return }
        do {
            contents = try library.snapshot {
                let items = try library.allItems()
                return DesktopShow.Library(shows: try library.allShows(), collections: try library.allCollections(),
                                           items: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
            }
            lastChange = now
            generation += 1
            Log.write("read \(root.lastPathComponent): \(contents.shows.count) shows, \(contents.items.count) items")
        } catch {
            Log.write("read \(root.lastPathComponent) failed: \(error)")
        }
    }
}
