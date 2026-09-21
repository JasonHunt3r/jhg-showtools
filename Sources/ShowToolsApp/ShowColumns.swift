import SwiftUI
import AppKit

/// Edit Show's three columns — preview, order list, inspector — as an AppKit
/// split view, because SwiftUI's can't collapse a pane.
///
/// - Drag the inspector's divider all the way right and it collapses; the
///   list keeps its width and moves over, so the space goes to the preview.
/// - Showing the inspector again (double-click, ⌥⌘I) slides it back in.
/// - When the window resizes, the preview takes up the change first.
/// - Divider positions are remembered.
struct ShowColumns<Preview: View, List: View, Inspector: View>: NSViewControllerRepresentable {
    @Binding var inspectorShown: Bool
    let model: AppModel
    let preview: Preview
    let list: List
    let inspector: Inspector

    @MainActor final class Coordinator {
        var inspectorShown: Binding<Bool>
        var observation: NSKeyValueObservation?
        init(_ b: Binding<Bool>) { inspectorShown = b }
    }

    func makeCoordinator() -> Coordinator { Coordinator($inspectorShown) }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let c = NSSplitViewController()
        c.splitView.isVertical = true
        c.splitView.dividerStyle = .thin

        let previewItem = NSSplitViewItem(viewController: host(preview))
        previewItem.minimumThickness = 420
        previewItem.holdingPriority = .init(250)     // gives and takes space first

        let listItem = NSSplitViewItem(viewController: host(list))
        listItem.minimumThickness = 180
        listItem.maximumThickness = 420
        listItem.holdingPriority = .init(270)        // keeps its width

        let inspectorItem = NSSplitViewItem(inspectorWithViewController: host(inspector))
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 440
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = .init(260)
        inspectorItem.isCollapsed = !inspectorShown

        [previewItem, listItem, inspectorItem].forEach(c.addSplitViewItem)
        c.splitView.autosaveName = "EditShowColumns"

        // A drag to the edge collapses the item; tell SwiftUI so the toolbar
        // button and double-click stay in step.
        let coordinator = context.coordinator
        coordinator.observation = inspectorItem.observe(\.isCollapsed, options: [.new]) { item, _ in
            let shown = !item.isCollapsed
            Task { @MainActor in
                if coordinator.inspectorShown.wrappedValue != shown { coordinator.inspectorShown.wrappedValue = shown }
            }
        }
        return c
    }

    func updateNSViewController(_ c: NSSplitViewController, context: Context) {
        context.coordinator.inspectorShown = $inspectorShown
        let items = c.splitViewItems
        guard items.count == 3 else { return }
        (items[0].viewController as? NSHostingController<AnyView>)?.rootView = wrap(preview)
        (items[1].viewController as? NSHostingController<AnyView>)?.rootView = wrap(list)
        (items[2].viewController as? NSHostingController<AnyView>)?.rootView = wrap(inspector)
        if items[2].isCollapsed == inspectorShown {
            items[2].animator().isCollapsed = !inspectorShown
        }
    }

    /// Views hosted here don't inherit the SwiftUI environment, so the model
    /// is handed back in.
    private func wrap<V: View>(_ v: V) -> AnyView { AnyView(v.environment(model)) }

    private func host<V: View>(_ v: V) -> NSViewController {
        let h = NSHostingController(rootView: wrap(v))
        h.sizingOptions = []   // the split view decides sizes, not the content
        return h
    }
}
