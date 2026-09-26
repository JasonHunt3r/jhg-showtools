import AppKit
import SwiftUI

/// An app's own view as a split's handle (`PaneHandleStyle.external`): put
/// one **behind** the view — a header bar, say — so the bar's own controls
/// keep their clicks and only its empty space reaches this. A drag resizes
/// the split, following the pointer from wherever it was grabbed; past half
/// the sized side's minimum it closes. A double-click opens or closes it.
///
/// It must be in the same window as the split's `PaneContainerView` (a
/// handle inside a pane that has popped out does nothing).
@MainActor
public final class PaneHandleView: NSView {
    public weak var controller: PaneController?
    public var splitID: String

    public init(controller: PaneController, splitID: String) {
        self.controller = controller
        self.splitID = splitID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("PaneHandleView is made in code") }

    private var split: Split? { controller?.root.split(splitID) }

    public override func resetCursorRects() {
        guard let split else { return }
        addCursorRect(bounds, cursor: split.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    public override func mouseDown(with event: NSEvent) {
        guard let controller, let split, split.handle == .external,
              let container = controller.container, container.window === window else { return }
        if event.clickCount == 2 {
            if split.collapsible { controller.toggle(splitID) }
            return
        }
        trackResize(split, in: container, from: event, keepGrabOffset: true)
    }
}

/// `PaneHandleView` for SwiftUI (`View.paneHandle`).
struct PaneHandleRepresentable: NSViewRepresentable {
    let controller: PaneController
    let splitID: String

    func makeNSView(context: Context) -> PaneHandleView {
        PaneHandleView(controller: controller, splitID: splitID)
    }

    func updateNSView(_ view: PaneHandleView, context: Context) {
        view.controller = controller
        view.splitID = splitID
    }
}

public extension View {
    /// Makes this view's empty space the handle of an `.external` split:
    /// drag to resize or close it, double-click to open or close it. Its
    /// controls keep their own clicks (the handle sits behind them).
    func paneHandle(_ controller: PaneController, split splitID: String) -> some View {
        background(PaneHandleRepresentable(controller: controller, splitID: splitID))
    }
}
