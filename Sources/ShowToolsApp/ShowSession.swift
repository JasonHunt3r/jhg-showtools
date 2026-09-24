import Foundation
import CoreGraphics
import ShowToolsPlayback

/// A show's editing state, out of the views and into one object
/// (`spec/windows.md`, "What stands in the way"; `spec/panekit.md`, step
/// 4's own prerequisite): the slide selection, the playback engine, and
/// Edit Show's lane selections and storyline scroll — all of it `@State`
/// in `ShowView` and `EditShowView` until now, reachable by nothing
/// outside those views. Owned by `AppModel`, one per open show, so a
/// window other than the main one could reach it later; nothing on
/// screen changes by this move alone.
@MainActor
@Observable
final class ShowSession {
    let showID: Int64
    var selection: Set<Int64> = []
    /// Edit Show only: created when that mode is entered, torn down when
    /// it's left or another show opens (`EditShowView`'s own lifecycle,
    /// unchanged by this move).
    var engine: PlaybackEngine?
    /// The transition selected in the storyline's lane, by the slide it
    /// leads into.
    var selectedTransition: Int64?
    /// The image selected in the lane's images row.
    var selectedOverlay: UUID?
    var selectedSong: UUID?
    var selectedMarkers: Set<UUID> = []
    var storylineOffset: CGFloat = 0

    init(showID: Int64) { self.showID = showID }
}
