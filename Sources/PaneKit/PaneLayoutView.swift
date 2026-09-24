import SwiftUI

/// PaneKit for SwiftUI: a `PaneContainerView` with a SwiftUI view in each
/// pane.
///
///     PaneLayoutView(controller: panes, content: [
///         "library": AnyView(LibraryList()),
///         "detail": AnyView(Detail()),
///     ])
///
/// Each pane's hosting view has `sizingOptions = []`: PaneKit decides the
/// sizes, and SwiftUI doesn't negotiate them (the negotiation that looped in
/// `.inspector()`). The views don't inherit the SwiftUI environment across
/// the AppKit boundary, so pass in what they need (`.environment(model)`).
public struct PaneLayoutView: NSViewRepresentable {
    public let controller: PaneController
    public let content: [String: AnyView]

    public init(controller: PaneController, content: [String: AnyView]) {
        self.controller = controller
        self.content = content
    }

    public func makeNSView(context: Context) -> PaneContainerView {
        let views = content.mapValues { view -> NSView in
            let h = NSHostingView(rootView: view)
            h.sizingOptions = []
            return h
        }
        return PaneContainerView(controller: controller, content: views)
    }

    public func updateNSView(_ container: PaneContainerView, context: Context) {
        for (id, view) in content {
            if let hosting = container.content(of: id) as? NSHostingView<AnyView> {
                hosting.rootView = view
            }
        }
    }
}
