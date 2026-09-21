import SwiftUI
import AppKit

/// Edit Show's three columns — preview, order list, inspector — in a
/// `ColumnsSplitView`, which lays them out by hand. See that type for why.
struct ShowColumns<Preview: View, List: View, Inspector: View>: NSViewRepresentable {
    @Binding var inspectorShown: Bool
    let model: AppModel
    let preview: Preview
    let list: List
    let inspector: Inspector

    @MainActor final class Coordinator {
        var inspectorShown: Binding<Bool>
        var hosts: [ColumnHost] = []
        init(_ b: Binding<Bool>) { inspectorShown = b }
    }

    func makeCoordinator() -> Coordinator { Coordinator($inspectorShown) }

    func makeNSView(context: Context) -> ColumnsSplitView {
        let hosts = [wrap(preview), wrap(list), wrap(inspector)].map { view -> ColumnHost in
            let h = ColumnHost(rootView: view)
            h.sizingOptions = []   // the split view decides sizes, not the content
            // A column's content can be wider than the column (the inspector
            // was 316 in 260, measured 2026-09-21): clipped, it can't hang
            // over its neighbour and take its clicks and scrolling.
            h.clipsToBounds = true
            return h
        }
        context.coordinator.hosts = hosts
        let split = ColumnsSplitView(main: hosts[0], list: hosts[1], inspector: hosts[2],
                                     defaultsKey: "EditShowColumns")
        split.setInspectorShown(inspectorShown)
        // Dragging the inspector shut (or open) keeps the toolbar button and
        // double-click in step.
        let coordinator = context.coordinator
        split.onInspectorShownChange = { shown in
            Task { @MainActor in
                if coordinator.inspectorShown.wrappedValue != shown { coordinator.inspectorShown.wrappedValue = shown }
            }
        }
        return split
    }

    func updateNSView(_ split: ColumnsSplitView, context: Context) {
        context.coordinator.inspectorShown = $inspectorShown
        let hosts = context.coordinator.hosts
        hosts[0].rootView = wrap(preview)
        hosts[1].rootView = wrap(list)
        hosts[2].rootView = wrap(inspector)
        if split.isInspectorShown != inspectorShown {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                split.setInspectorShown(inspectorShown)
            }
        }
    }

    /// Views hosted here don't inherit the SwiftUI environment, so the model
    /// is handed back in.
    private func wrap<V: View>(_ v: V) -> AnyView { AnyView(v.environment(model)) }
}

/// A column's hosting view that takes the mouse only inside its own frame.
/// SwiftUI hit-tests a hosting view's whole content, clipped or not, so a
/// column whose content was wider than it (the inspector, 2026-09-21) caught
/// the clicks and scrolling meant for the column beside it.
final class ColumnHost: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates, as `frame` is.
        guard frame.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
