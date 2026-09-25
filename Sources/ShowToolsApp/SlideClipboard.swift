import AppKit
import ShowToolsCore

/// Copy/Paste of slides, and Copy Settings/Paste Settings of just one
/// slide's settings onto others (`spec/conventions.md` §3, item 3). Uses the
/// system pasteboard, not `ItemDrag`'s own type (that carries library item
/// ids for drags; this carries whole slides, settings and all).
///
/// **Simplified from the settled design, on purpose:** Jason's answer calls
/// for Copy Settings/Paste Settings to appear only while ⌥ is held, swapped
/// in live over Copy/Paste — AppKit's *alternate* menu items, which
/// SwiftUI's `.contextMenu` has no way to declare. Built here as four
/// always-visible items instead, so the functions exist and work; the
/// ⌥-swap interaction is a separate, later pass (its own small AppKit menu,
/// not a `.contextMenu`) if it's worth the trouble once this is used.
@MainActor
enum SlideClipboard {
    private static let slidesType = NSPasteboard.PasteboardType("com.jhg.showtools.slides")
    private static let settingsType = NSPasteboard.PasteboardType("com.jhg.showtools.slidesettings")

    private struct Copied: Codable {
        let itemID: Int64
        let settings: SlideSettings
    }

    static func copy(_ ids: Set<Int64>, from show: Show) {
        let ordered = show.slides.filter { ids.contains($0.id) }
        guard !ordered.isEmpty,
              let data = try? JSONEncoder().encode(ordered.map { Copied(itemID: $0.itemID, settings: $0.settings) })
        else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: slidesType)
    }

    static var canPaste: Bool { NSPasteboard.general.data(forType: slidesType) != nil }

    /// New slides, after `afterID` (or at the end if nil) — a fresh id and
    /// no Pan and Zoom seed each, as `SlideActions.duplicate` already does.
    static func paste(after afterID: Int64?, mutate: ShowMutator) {
        guard let data = NSPasteboard.general.data(forType: slidesType),
              let payload = try? JSONDecoder().decode([Copied].self, from: data), !payload.isEmpty
        else { return }
        mutate(payload.count == 1 ? "Paste Slide" : "Paste Slides") { s in
            let new = payload.map { c -> Slide in
                var settings = c.settings
                settings.panAndZoomSeed = nil
                return Slide(id: 0, itemID: c.itemID, settings: settings)
            }
            if let afterID, let i = s.slides.firstIndex(where: { $0.id == afterID }) {
                s.slides.insert(contentsOf: new, at: i + 1)
            } else {
                s.slides += new
            }
        }
    }

    static func copySettings(_ id: Int64, from show: Show) {
        guard let slide = show.slides.first(where: { $0.id == id }),
              let data = try? JSONEncoder().encode(slide.settings) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: settingsType)
    }

    static var canPasteSettings: Bool { NSPasteboard.general.data(forType: settingsType) != nil }

    /// Onto every slide in `ids`, one undo step — the same "applies to
    /// every selected slide" convention the quick-settings menus use.
    static func pasteSettings(onto ids: Set<Int64>, mutate: ShowMutator) {
        guard !ids.isEmpty, let data = NSPasteboard.general.data(forType: settingsType),
              let settings = try? JSONDecoder().decode(SlideSettings.self, from: data)
        else { return }
        mutate("Paste Settings") { s in
            for i in s.slides.indices where ids.contains(s.slides[i].id) {
                var new = settings
                new.panAndZoomSeed = nil
                s.slides[i].settings = new
            }
        }
    }
}
