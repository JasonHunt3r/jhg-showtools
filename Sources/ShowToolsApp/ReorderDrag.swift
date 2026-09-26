import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Drag-to-reorder's view-side pieces (`spec/plan.md`, "Reordering"), kept
// apart from `LibraryGridView` and free of ShowTools' own types so they can
// move into a package of their own, like PaneKit, once the behaviour is
// settled. The pure geometry and ordering is `ShowToolsCore.Reorder`.

/// A grid's one drop handler for drag-to-reorder, over the whole grid
/// rather than one per tile: the tiles move while dragging, so a tile can't
/// be asked whether the cursor is over it (that was the back-and-forth
/// loop, 2026-09-25). The grid works out the slot from the cursor's
/// position instead. Only the grid's own drags (`isOurs`): anything else
/// falls through to whatever other drop the grid has.
struct ReorderDrop: DropDelegate {
    let type: UTType
    let isOurs: () -> Bool
    /// The cursor moved to a point; false when the grid can't reorder.
    let update: (CGPoint) -> Bool
    let exit: () -> Void
    /// Dropped at a point, already accepted by `update`.
    let perform: (CGPoint) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [type]) && isOurs()
    }

    func dropEntered(info: DropInfo) { _ = update(info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: update(info.location) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) { exit() }

    func performDrop(info: DropInfo) -> Bool {
        guard update(info.location) else { exit(); return false }
        perform(info.location)
        return true
    }
}

/// Each tile's frame, in the grid's own coordinate space (the space
/// `StackDragAnchor` and the grid's drop share), keyed by the tile's id.
struct TileFramesKey: PreferenceKey {
    static let defaultValue: [Int64: CGRect] = [:]
    static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Starts a drag whose picture is a tidy pile of the dragged items (Jason,
/// 2026-09-25: "no rotation, just bring together into a tidy, slightly
/// overlapped stack"). One dragging item with one composed picture
/// (`pileImage`), not one per file: AppKit tilts every picture of a
/// multi-item drag, whatever the formation (measured in a harness with
/// `.none` held on every move). The fly-in to the pile is drawn by the grid.
/// Sits behind the grid as an invisible view, so its coordinates are the
/// grid's (flipped, like SwiftUI's); never takes a click itself.
final class StackDragSource: NSView, NSDraggingSource {
    /// The drag ended: dropped somewhere (an operation) or cancelled (`[]`).
    var onEnd: ((NSDragOperation) -> Void)?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `frame` is where the picture starts, in this view (the grid's
    /// space); `event` the mouse event the drag started from
    /// (`NSApp.currentEvent` in a drag gesture).
    func begin(image: NSImage, frame: CGRect, writer: NSPasteboardWriting, event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(frame, contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        self.session = session
        let grab = convert(event.locationInWindow, from: nil)
        pile = image
        grabInPile = CGPoint(x: grab.x - frame.minX, y: grab.y - frame.minY)
        pileAbove = max(0, grab.y - frame.minY)
        pileBelow = max(0, frame.maxY - grab.y)
        handScale = min(1, Self.handful.width / max(frame.width, 1), Self.handful.height / max(frame.height, 1))
        shownScale = 1
        startEdgeScroll()
    }

    // MARK: Edge scrolling, and the pile shrinking toward the edge

    /// Called after each edge-scroll step with the pointer's new place in
    /// this view (the content moved under a still pointer), so the grid
    /// can move its gap to match.
    var onAutoscroll: ((CGPoint) -> Void)?

    /// The pile's picture, and where in it the pointer holds it.
    private var pile: NSImage?
    private var grabInPile: CGPoint = .zero
    /// How far the full-size pile hangs above and below the pointer.
    private var pileAbove: CGFloat = 0, pileBelow: CGFloat = 0
    /// The pile's scale at the edge (`handful`), and the scale it's drawn at now.
    private var handScale: CGFloat = 1, shownScale: CGFloat = 1
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    /// The size the pile shrinks to fit at the edge: what AppKit shrinks a
    /// drag picture to over the header bar or a closed pane (measured
    /// 2026-09-25: a 363pt grid pile became ~121pt wide, a 320×34 list card
    /// ~199×20 — both "fit in about 200×130, never enlarge").
    static let handful = CGSize(width: 200, height: 130)
    /// Points per second at the start of the zone and at the edge.
    static let edgeMinSpeed: CGFloat = 30, edgeMaxSpeed: CGFloat = 2800
    /// Scrolling stops this far past the edge (a drop target beyond it,
    /// like the timeline, stays reachable).
    static let edgeOvershoot: CGFloat = 30

    /// Near the scroll view's top or bottom edge, two things follow one
    /// ramp, 0 where the zone starts and 1 at the edge (Jason, 2026-09-25):
    /// the scroll speed (cubed — a crawl at first, fast only near the edge)
    /// and the pile's size (full size down to `handful`, so it arrives the
    /// size AppKit makes it over the header or a closed pane). The zone is
    /// as deep as the full pile hangs past the pointer, at least 48pt and at
    /// most 30% of the visible height — AppKit's own zone is a thin strip at
    /// the pointer, "fussy" with a large pile hanging below it. A timer
    /// drives it, so a still pointer keeps scrolling.
    private func startEdgeScroll() {
        timer?.invalidate()
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.edgeScrollTick() }
        }
        // `.common` includes the event-tracking mode a drag runs in.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopEdgeScroll() {
        timer?.invalidate()
        timer = nil
    }

    private func edgeScrollTick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 0.05))
        lastTick = now
        guard let window, let scroll = enclosingScrollView, let doc = scroll.documentView else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let vis = visibleRect
        // Over the sidebar or anything beside the grid: leave the pile be.
        guard vis.height > 0, p.x >= vis.minX, p.x <= vis.maxX else { return }
        func zone(_ hang: CGFloat) -> CGFloat { min(max(hang + 16, 48), vis.height * 0.3) }
        let top = zone(pileAbove), bottom = zone(pileBelow)

        // The ramp: how far into the zone, 0...1, and which way to scroll.
        // Past either edge it stays 1, so the pile stays handful-sized as
        // it goes on over the header or a pane.
        var ramp: CGFloat = 0, direction: CGFloat = 0
        if p.y < vis.minY + top {
            ramp = min((vis.minY + top - p.y) / top, 1)
            direction = p.y > vis.minY - Self.edgeOvershoot ? -1 : 0
        } else if p.y > vis.maxY - bottom {
            ramp = min((p.y - (vis.maxY - bottom)) / bottom, 1)
            direction = p.y < vis.maxY + Self.edgeOvershoot ? 1 : 0
        }

        resizePile(to: 1 - ramp * (1 - handScale), pointer: p)

        guard direction != 0, ramp > 0 else { return }
        let v = direction * (Self.edgeMinSpeed + (Self.edgeMaxSpeed - Self.edgeMinSpeed) * ramp * ramp * ramp)
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let limit = max(doc.frame.height - clip.bounds.height, 0)
        let dy = doc.isFlipped ? v * dt : -v * dt
        origin.y = min(max(origin.y + dy, 0), limit)
        guard origin.y != clip.bounds.origin.y else { return }
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        onAutoscroll?(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// Redraws the drag's picture at `scale`, kept in the same place under
    /// the pointer. Skipped for changes too small to see.
    private func resizePile(to scale: CGFloat, pointer: CGPoint) {
        guard let pile, abs(scale - shownScale) > 0.004 else { return }
        shownScale = scale
        let size = CGSize(width: pile.size.width * scale, height: pile.size.height * scale)
        let frame = CGRect(x: pointer.x - grabInPile.x * scale, y: pointer.y - grabInPile.y * scale,
                           width: size.width, height: size.height)
        session?.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self],
                                        searchOptions: [:]) { item, _, _ in
            item.setDraggingFrame(frame, contents: pile)
        }
    }

    /// At most this many pictures show in the pile, however many are
    /// dragged; the badge says how many there really are (Jason,
    /// 2026-09-25: "if more than X, then just use a stack of 5").
    static let pileDepth = 5
    /// How far each picture sits from the one above it: 6pt for a small
    /// pile, less as it grows, so a full pile spreads no further than
    /// `pileSpread` ("the bigger the stack, the smaller the offset").
    static let pileSpread: CGFloat = 18
    static func pileStep(layers: Int) -> CGFloat {
        layers > 1 ? min(6, pileSpread / CGFloat(layers - 1)) : 0
    }
    /// Room above the top picture for the count badge, when there is one:
    /// the top picture sits this far down inside `pileImage`.
    static func badgeRoom(count: Int) -> CGFloat { count > 1 ? 11 : 0 }

    /// The pile: `layers[0]` on top at the top-left, each next one
    /// `pileStep` further down and right, all `size`; a count badge on the
    /// top one's corner when there's more than one item. Only the first
    /// `pileDepth` layers are drawn.
    static func pileImage(_ layers: [NSImage], size: CGSize, count: Int) -> NSImage {
        let shown = Array(layers.prefix(pileDepth))
        let step = pileStep(layers: shown.count)
        let spread = CGFloat(max(shown.count - 1, 0)) * step
        let badge = badgeRoom(count: count)
        let total = CGSize(width: size.width + spread + badge, height: size.height + spread + badge)
        return NSImage(size: total, flipped: true) { _ in
            for (i, layer) in shown.enumerated().reversed() {
                let r = CGRect(x: CGFloat(i) * step, y: badge + CGFloat(i) * step,
                               width: size.width, height: size.height)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 3
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.set()
                layer.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            if count > 1 {
                let text = "\(count)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12),
                                                            .foregroundColor: NSColor.white]
                let t = text.size(withAttributes: attrs)
                let d = max(22, t.width + 12)
                let circle = CGRect(x: size.width - d / 2, y: 0, width: d, height: 22)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: circle, xRadius: 11, yRadius: 11).fill()
                text.draw(at: CGPoint(x: circle.midX - t.width / 2, y: circle.midY - t.height / 2), withAttributes: attrs)
            }
            return true
        }
    }

    private weak var session: NSDraggingSession?

    /// Blanks the drag's pictures, for a drop that draws its own landing:
    /// otherwise AppKit's end-of-drag animation plays over it, and each
    /// file shows twice for a moment (measured 2026-09-25, list mode).
    func hideImages() {
        pile = nil  // and `resizePile` doesn't bring it back
        session?.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self],
                                        searchOptions: [:]) { item, _, _ in
            item.imageComponentsProvider = { [] }
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // The app's other drops (a collection, a show) propose copy; the
        // grid's own reorder proposes move.
        context == .withinApplication ? [.move, .copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        stopEdgeScroll()
        onEnd?(operation)
    }
}

/// `StackDragSource` as a SwiftUI background.
struct StackDragAnchor: NSViewRepresentable {
    let source: StackDragSource
    func makeNSView(context: Context) -> StackDragSource { source }
    func updateNSView(_ view: StackDragSource, context: Context) {}
}
