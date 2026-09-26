import Foundation
import CoreGraphics

// PaneKit's model: a tree of panes, built from one primitive, Finder's
// shape: two panes and one divider. Anything bigger is those nested.
// See spec/panekit.md.

/// How a split's two children sit.
public enum PaneAxis: String, Sendable, Codable {
    /// Side by side, with a vertical divider between them.
    case horizontal
    /// One above the other, with a horizontal divider between them.
    case vertical
}

/// One of a split's two children.
public enum PaneSide: String, Sendable, Codable {
    case first, second
}

/// A window edge a pane can close against.
public enum PaneEdge: String, Sendable {
    case leading, trailing, top, bottom
}

/// How a pane leaves the window, if it can.
public enum PopOutStyle: String, Sendable {
    /// It can't.
    case none
    /// A panel: floats above the app's other windows (the library, the
    /// inspector).
    case panel
    /// An ordinary window: can go behind others (the Timeline window).
    case window
}

/// What a closed split leaves on its edge, and what drags it.
public enum PaneHandleStyle: String, Sendable {
    /// PaneKit's own edge handle: a 12-point grip on the edge, always
    /// visible (the frame strip's bar was the model).
    case edge
    /// **The app's own view is the handle** (Jason, 2026-09-26: a grid's
    /// header bar, with the viewer drawer above it). Closed, the split
    /// takes no room at all; the app marks the view with `.paneHandle`
    /// (SwiftUI) or puts a `PaneHandleView` behind it (AppKit), and a drag
    /// on it resizes the split, a double-click opens or closes it. Such a
    /// split can't switch sides: the app's view stays where the app put it.
    case external
}

/// A leaf: one pane of content.
public struct Pane: Sendable, Identifiable, Equatable {
    public let id: String
    public var title: String
    /// The least it shows along either axis while open. Its neighbour
    /// gives way until then.
    public var minSize: CGFloat
    public var popOut: PopOutStyle

    public init(_ id: String, title: String? = nil, minSize: CGFloat = 80, popOut: PopOutStyle = .none) {
        self.id = id
        self.title = title ?? id
        self.minSize = minSize
        self.popOut = popOut
    }
}

/// The primitive: two children and one divider. One child is **sized**: it
/// keeps its size, can close against its edge, and is what a divider drag
/// changes. The other is **main**: it takes whatever is left, so a window
/// resize goes to it.
public struct Split: Sendable, Identifiable, Equatable {
    public let id: String
    public var axis: PaneAxis
    public var sized: PaneSide
    /// The sized child's size along the axis, before anyone drags it.
    public var defaultSize: CGFloat
    /// What a drag can set the sized child's size to.
    public var range: ClosedRange<CGFloat>
    /// Whether the sized child can close against its edge, leaving a handle.
    public var collapsible: Bool
    /// What the menus call the sized side ("Inspector"). Nil: its first
    /// pane's title.
    public var title: String?
    /// Another split whose stored size moves by the same amount whenever
    /// this one's divider is dragged, or whenever this one collapses or
    /// reopens (never on a plain window resize) — so a pane sandwiched
    /// between this split's own boundary and that ancestor's doesn't change
    /// size, only position. `.row`'s `nearIsRigid` is what sets this
    /// (`spec/panekit.md`, "Building a row").
    public var linkedAncestor: String?
    /// Whether the sized child can **switch sides**: dragged across the
    /// main side, it trades places with it and mounts on the opposite
    /// edge (leading ⇄ trailing, top ⇄ bottom). Which side it's on now is
    /// state (`SplitState.onOtherSide`), remembered like its size. Jason,
    /// 2026-09-25: "basically we're reordering the columns."
    public var canSwitchSides: Bool
    /// What it leaves when closed, and what drags it (`PaneHandleStyle`).
    public var handle: PaneHandleStyle
    public var first: PaneNode
    public var second: PaneNode

    public init(_ id: String, _ axis: PaneAxis, sized: PaneSide, size: CGFloat,
                range: ClosedRange<CGFloat>, collapsible: Bool = true, title: String? = nil,
                linkedAncestor: String? = nil, canSwitchSides: Bool = true,
                handle: PaneHandleStyle = .edge, first: PaneNode, second: PaneNode) {
        self.id = id
        self.axis = axis
        self.sized = sized
        self.defaultSize = size
        self.range = range
        self.collapsible = collapsible
        self.title = title
        self.linkedAncestor = linkedAncestor
        self.canSwitchSides = canSwitchSides && handle == .edge
        self.handle = handle
        self.first = first
        self.second = second
    }

    /// The edge the sized child is built on, before any switch of sides.
    public var edge: PaneEdge {
        switch (axis, sized) {
        case (.horizontal, .first): .leading
        case (.horizontal, .second): .trailing
        case (.vertical, .first): .top
        case (.vertical, .second): .bottom
        }
    }

    /// Whether the sized child sits first (leading/top) now, in `state`.
    public func sizedFirst(in state: PaneKitState) -> Bool {
        (sized == .first) != (canSwitchSides && state.isOnOtherSide(id))
    }

    /// The edge the sized child sits on and closes against now, in `state`.
    public func edge(in state: PaneKitState) -> PaneEdge {
        switch (axis, sizedFirst(in: state)) {
        case (.horizontal, true): .leading
        case (.horizontal, false): .trailing
        case (.vertical, true): .top
        case (.vertical, false): .bottom
        }
    }

    public var sizedNode: PaneNode { sized == .first ? first : second }
    public var mainNode: PaneNode { sized == .first ? second : first }

    /// The name the menus use for the sized side.
    public var sizedTitle: String { title ?? sizedNode.paneIDs.first.flatMap { sizedNode.pane($0)?.title } ?? id }
}

/// A node of the tree: a pane, or a split holding two nodes.
public indirect enum PaneNode: Sendable, Equatable {
    case leaf(Pane)
    case branch(Split)

    /// A pane (see `Pane.init`).
    public static func pane(_ id: String, title: String? = nil, minSize: CGFloat = 80,
                            popOut: PopOutStyle = .none) -> PaneNode {
        .leaf(Pane(id, title: title, minSize: minSize, popOut: popOut))
    }

    /// A split (see `Split.init`).
    public static func split(_ id: String, _ axis: PaneAxis, sized: PaneSide, size: CGFloat,
                             range: ClosedRange<CGFloat>, collapsible: Bool = true, title: String? = nil,
                             linkedAncestor: String? = nil, canSwitchSides: Bool = true,
                             handle: PaneHandleStyle = .edge,
                             _ first: PaneNode, _ second: PaneNode) -> PaneNode {
        .branch(Split(id, axis, sized: sized, size: size, range: range, collapsible: collapsible,
                      title: title, linkedAncestor: linkedAncestor, canSwitchSides: canSwitchSides,
                      handle: handle, first: first, second: second))
    }

    /// A row of three: `main`, which absorbs a window resize, and two more
    /// panes trailing off it in visual order — `near` (next to `main`) and
    /// `far` (at the outer edge). Two nested splits, not PaneKit's binary
    /// primitive done three ways at once: three independently-sized
    /// siblings can't share one split, so this composes two, chosen so
    /// that **a divider only ever moves its own two neighbors** and **a
    /// window resize goes to `main`** — the two invariants every pane
    /// promises — hold for all three, not just two (`spec/panekit.md`,
    /// "Building a row"; found building Edit Show's preview/list/inspector,
    /// which is what this generalizes).
    ///
    /// The trade-off that forces a choice: by default, `near` gives way
    /// before `far` as the window narrows (`near`'s own floor is
    /// `near.minSize`, no upper bound — it's the inner split's "main"
    /// side); the reverse (`far` giving way first) is reachable only by
    /// breaking divider isolation, moving `far` when the main|near divider
    /// drags. `far` is the only one of the three that keeps a real upper
    /// bound by default. Closing `far` (it can, `near` and `main` can't)
    /// hands its space to `near`, not to `main`, by default — `near` is
    /// what's adjacent to it. **Under `nearIsRigid`, closing or reopening
    /// `far` hands the space to `main` instead** (`PaneController.setOpen`),
    /// matching what a direct drag already did — found wrong the other way
    /// on Edit Show's own list column (item 1,
    /// `ShowTools Feedback — Worklist for Next CC Session.md`, 2026-09-25):
    /// closing the inspector grew the list, when list was meant to stay
    /// fixed-width and only the divider it owns should ever resize it.
    ///
    /// - Parameters:
    ///   - mainFirst: `main` reads first (left/top) when true, matching
    ///     Edit Show's preview; false puts it last, as a reading pane at
    ///     the end of the row would be.
    ///   - nearDefault/nearMax: `near` has no split of its own to carry a
    ///     stored range, so these only seed the combined near+far region's
    ///     starting size and how wide a drag can make it; `near` itself is
    ///     floored at `near.minSize`, and — unless `nearIsRigid` — never
    ///     capped.
    ///   - nearIsRigid: **`near` only ever changes size from the main|near
    ///     divider.** Dragging the near|far divider instead resizes `main`
    ///     and `far`, with `near` sliding to stay adjacent to `far` —
    ///     found on a real case (Edit Show's list column, which Jason
    ///     wanted fixed-width and unmoved by the inspector's own divider,
    ///     2026-09-24). Implemented as one split's divider drag also
    ///     moving an ancestor split's stored size by the same amount
    ///     (`Split.linkedAncestor`), not a special case in the layout
    ///     arithmetic itself — `PaneLayout` doesn't know this option
    ///     exists, only `trackResize` (`PaneContainerView.swift`) does.
    public static func row(_ id: String, _ axis: PaneAxis, mainFirst: Bool, main: Pane,
                           near: Pane, nearDefault: CGFloat, nearMax: CGFloat,
                           far: Pane, farSize: CGFloat, farRange: ClosedRange<CGFloat>,
                           farCollapsible: Bool = true, nearIsRigid: Bool = false) -> PaneNode {
        let d = PaneLayout.dividerThickness
        let comboDefault = nearDefault + d + farSize
        // Under `nearIsRigid`, `far` collapsing shrinks the stored combo
        // size down to just `near` plus the handle (`PaneController
        // .setOpen`), so the combo's own floor must reach that low, not
        // stop at `near` plus a full-width `far` — otherwise the stored
        // value gets clamped back up and `near` grows anyway, the bug
        // `setOpen`'s change fixes.
        let comboLower = nearIsRigid && farCollapsible
            ? near.minSize + PaneLayout.handleThickness
            : near.minSize + d + farRange.lowerBound
        let comboRange = comboLower...(nearMax + d + farRange.upperBound)
        let linkedAncestor = nearIsRigid ? id : nil
        let inner: PaneNode = mainFirst
            ? .split("\(id).near", axis, sized: .second, size: farSize, range: farRange,
                     collapsible: farCollapsible, linkedAncestor: linkedAncestor, canSwitchSides: false, .leaf(near), .leaf(far))
            : .split("\(id).near", axis, sized: .first, size: farSize, range: farRange,
                     collapsible: farCollapsible, linkedAncestor: linkedAncestor, canSwitchSides: false, .leaf(far), .leaf(near))
        return mainFirst
            ? .split(id, axis, sized: .second, size: comboDefault, range: comboRange, collapsible: false, canSwitchSides: false,
                     .leaf(main), inner)
            : .split(id, axis, sized: .first, size: comboDefault, range: comboRange, collapsible: false, canSwitchSides: false,
                     inner, .leaf(main))
    }

    /// Every pane's id, in order (as built, before any switch of sides).
    public var paneIDs: [String] {
        switch self {
        case .leaf(let p): [p.id]
        case .branch(let s): s.first.paneIDs + s.second.paneIDs
        }
    }

    /// Every split, outermost first.
    public var splits: [Split] {
        switch self {
        case .leaf: []
        case .branch(let s): [s] + s.first.splits + s.second.splits
        }
    }

    public var panes: [Pane] {
        switch self {
        case .leaf(let p): [p]
        case .branch(let s): s.first.panes + s.second.panes
        }
    }

    public func pane(_ id: String) -> Pane? { panes.first { $0.id == id } }
    public func split(_ id: String) -> Split? { splits.first { $0.id == id } }
}

// MARK: - State

/// A split's own state: its sized child's size, and whether it's closed.
public struct SplitState: Sendable, Equatable, Codable {
    /// Nil: the split's default size.
    public var size: CGFloat?
    public var collapsed: Bool
    /// The sized child has switched sides (`Split.canSwitchSides`).
    public var onOtherSide: Bool

    public init(size: CGFloat? = nil, collapsed: Bool = false, onOtherSide: Bool = false) {
        self.size = size
        self.collapsed = collapsed
        self.onOtherSide = onOtherSide
    }

    /// Field by field (CLAUDE.md): one unreadable field doesn't lose the other.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? c.decodeIfPresent(CGFloat.self, forKey: .size)) ?? nil
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? false
        onOtherSide = (try? c.decodeIfPresent(Bool.self, forKey: .onOtherSide)) ?? false
    }
}

/// A pane's own state: whether it's popped out, and where its window was.
public struct PaneWindowState: Sendable, Equatable, Codable {
    public var poppedOut: Bool
    public var windowFrame: CGRect?

    public init(poppedOut: Bool = false, windowFrame: CGRect? = nil) {
        self.poppedOut = poppedOut
        self.windowFrame = windowFrame
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poppedOut = (try? c.decodeIfPresent(Bool.self, forKey: .poppedOut)) ?? false
        windowFrame = (try? c.decodeIfPresent(CGRect.self, forKey: .windowFrame)) ?? nil
    }
}

/// Everything about a layout that can change: split sizes and states, and
/// which panes are out. Anything missing means "the default", so an empty
/// state is the default layout, and a preset is just one of these.
public struct PaneKitState: Sendable, Equatable, Codable {
    public var splits: [String: SplitState]
    public var panes: [String: PaneWindowState]

    public init(splits: [String: SplitState] = [:], panes: [String: PaneWindowState] = [:]) {
        self.splits = splits
        self.panes = panes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        splits = (try? c.decodeIfPresent([String: SplitState].self, forKey: .splits)) ?? [:]
        panes = (try? c.decodeIfPresent([String: PaneWindowState].self, forKey: .panes)) ?? [:]
    }

    public func isCollapsed(_ splitID: String) -> Bool { splits[splitID]?.collapsed ?? false }
    public func isOnOtherSide(_ splitID: String) -> Bool { splits[splitID]?.onOtherSide ?? false }
    public func isPoppedOut(_ paneID: String) -> Bool { panes[paneID]?.poppedOut ?? false }
}
