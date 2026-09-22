import Foundation
import ShowToolsCore

/// Where a `PlaybackEngine` gets its show and files. ShowTools' `AppModel`
/// is one (the library it edits); BGTools' read-only reader is another.
/// The engine asks every tick, so a show edited elsewhere is picked up.
@MainActor
public protocol ShowSource: AnyObject {
    /// The show as saved now, or nil if it's gone.
    func show(_ id: Int64) -> Show?
    func timeline(for show: Show) -> ShowTimeline
    func item(_ id: Int64) -> MediaItem?
    /// Where the item's file is, or nil if it can't be found.
    func url(for item: MediaItem) -> URL?
    /// Saves a change to a show's editing state (range, loop). A source
    /// that can't write ignores it.
    func updateEditor(_ showID: Int64, _ change: (inout ShowEditorState) -> Void)
}
