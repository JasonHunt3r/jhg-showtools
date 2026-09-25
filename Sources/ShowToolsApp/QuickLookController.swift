import AppKit
import Quartz

/// Quick Look for the Library grid (B5, B6): ⌘Y and double-clicking a tile.
/// A direct `QLPreviewPanel.shared()` data source, not the full responder-
/// chain `acceptsPreviewPanelControl` dance — this app never puts Quick
/// Look behind Space (that's play/pause everywhere, settled), so there's
/// no other owner of the panel to hand control back and forth with.
@MainActor
final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var items: [NSURL] = []

    /// Opens or closes the panel. Opening with a new selection always
    /// replaces what's shown, even if the panel was already open on a
    /// different one.
    func toggle(urls: [URL], startAt index: Int) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, items.map(\.absoluteURL) == urls.map(\.absoluteURL) {
            panel.orderOut(nil)
            return
        }
        items = urls.map { $0 as NSURL }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = max(0, min(index, items.count - 1))
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }
}
