import Foundation
import CoreGraphics

/// Where everything goes: pure arithmetic from a tree, a state and a
/// rectangle, so it can be tested without a window. Coordinates are
/// **flipped** (y grows downward), as `PaneContainerView` is.
public struct PaneLayoutResult: Sendable, Equatable {
    /// Each docked, visible pane's frame. A popped-out pane isn't here.
    public var panes: [String: CGRect] = [:]
    /// Each split's divider: the thin line between its children.
    public var dividers: [String: CGRect] = [:]
    /// Each closed split's edge handle.
    public var handles: [String: CGRect] = [:]
    /// Each split's whole rectangle, for drags to measure against.
    public var splits: [String: CGRect] = [:]
}

public enum PaneLayout {
    /// The line drawn between two children.
    public static let dividerThickness: CGFloat = 1
    /// A closed pane's handle on the window edge (the frame strip's bar is
    /// the model: slim, but big enough to grab).
    public static let handleThickness: CGFloat = 12

    public static func layout(_ node: PaneNode, in rect: CGRect, state: PaneKitState) -> PaneLayoutResult {
        var result = PaneLayoutResult()
        place(node, in: rect, state: state, into: &result)
        return result
    }

    private static func place(_ node: PaneNode, in rect: CGRect, state: PaneKitState,
                              into result: inout PaneLayoutResult) {
        switch node {
        case .leaf(let pane):
            if !state.isPoppedOut(pane.id) { result.panes[pane.id] = rect }
        case .branch(let split):
            // A side whose panes have all popped out closes up: its
            // neighbour takes the space, and there's no divider or handle.
            let sizedEmpty = isEmpty(split.sizedNode, state: state)
            let mainEmpty = isEmpty(split.mainNode, state: state)
            if sizedEmpty && mainEmpty { return }
            if sizedEmpty { place(split.mainNode, in: rect, state: state, into: &result); return }
            if mainEmpty { place(split.sizedNode, in: rect, state: state, into: &result); return }

            result.splits[split.id] = rect
            let total = extent(of: rect, along: split.axis)
            let extentSized: CGFloat
            let gap: CGFloat
            if state.isCollapsed(split.id) && split.collapsible {
                extentSized = 0
                gap = min(handleThickness, total)
            } else {
                extentSized = sizedExtent(for: split, available: total, state: state)
                gap = dividerThickness
            }
            let (sizedRect, gapRect, mainRect) = carve(rect, axis: split.axis, sizedFirst: split.sized == .first,
                                                       sized: extentSized, gap: gap)
            if extentSized > 0 {
                place(split.sizedNode, in: sizedRect, state: state, into: &result)
                result.dividers[split.id] = gapRect
            } else {
                result.handles[split.id] = gapRect
            }
            place(split.mainNode, in: mainRect, state: state, into: &result)
        }
    }

    /// The sized child's size: the stored or default size, kept inside its
    /// range, and never so big that the main side drops below its minimum.
    /// A squeeze from a small window shrinks it here without touching the
    /// stored size, so the window growing again gives it back.
    public static func sizedExtent(for split: Split, available: CGFloat, state: PaneKitState) -> CGFloat {
        let wanted = state.splits[split.id]?.size ?? split.defaultSize
        let inRange = min(max(wanted, split.range.lowerBound), split.range.upperBound)
        let room = available - dividerThickness - minExtent(split.mainNode, along: split.axis, state: state)
        return max(0, min(inRange, room))
    }

    /// The least a node needs along an axis.
    public static func minExtent(_ node: PaneNode, along axis: PaneAxis, state: PaneKitState) -> CGFloat {
        switch node {
        case .leaf(let pane):
            return state.isPoppedOut(pane.id) ? 0 : pane.minSize
        case .branch(let split):
            let sizedEmpty = isEmpty(split.sizedNode, state: state)
            let mainEmpty = isEmpty(split.mainNode, state: state)
            if sizedEmpty && mainEmpty { return 0 }
            if sizedEmpty { return minExtent(split.mainNode, along: axis, state: state) }
            if mainEmpty { return minExtent(split.sizedNode, along: axis, state: state) }
            let collapsed = state.isCollapsed(split.id) && split.collapsible
            if split.axis == axis {
                let sized = collapsed ? handleThickness : split.range.lowerBound + dividerThickness
                return sized + minExtent(split.mainNode, along: axis, state: state)
            }
            let sizedMin = collapsed ? 0 : minExtent(split.sizedNode, along: axis, state: state)
            return max(sizedMin, minExtent(split.mainNode, along: axis, state: state))
        }
    }

    /// True when every pane under a node has popped out.
    public static func isEmpty(_ node: PaneNode, state: PaneKitState) -> Bool {
        node.paneIDs.allSatisfy { state.isPoppedOut($0) }
    }

    static func extent(of rect: CGRect, along axis: PaneAxis) -> CGFloat {
        axis == .horizontal ? rect.width : rect.height
    }

    /// Cuts a rectangle into the sized part, the gap (divider or handle)
    /// and the main part, along an axis.
    static func carve(_ rect: CGRect, axis: PaneAxis, sizedFirst: Bool,
                      sized: CGFloat, gap: CGFloat) -> (CGRect, CGRect, CGRect) {
        let total = extent(of: rect, along: axis)
        let main = max(0, total - sized - gap)
        func span(_ from: CGFloat, _ length: CGFloat) -> CGRect {
            axis == .horizontal
                ? CGRect(x: rect.minX + from, y: rect.minY, width: length, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + from, width: rect.width, height: length)
        }
        if sizedFirst {
            return (span(0, sized), span(sized, gap), span(sized + gap, main))
        }
        return (span(main + gap, sized), span(main, gap), span(0, main))
    }
}
