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
        var hosts: [NSHostingView<AnyView>] = []
        init(_ b: Binding<Bool>) { inspectorShown = b }
    }

    func makeCoordinator() -> Coordinator { Coordinator($inspectorShown) }

    func makeNSView(context: Context) -> ColumnsSplitView {
        let hosts = [wrap(preview), wrap(list), wrap(inspector)].map { view -> NSHostingView<AnyView> in
            let h = NSHostingView(rootView: view)
            h.sizingOptions = []   // the split view decides sizes, not the content
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
