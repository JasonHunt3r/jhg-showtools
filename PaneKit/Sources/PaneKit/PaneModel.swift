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
    public var first: PaneNode
    public var second: PaneNode

    public init(_ id: String, _ axis: PaneAxis, sized: PaneSide, size: CGFloat,
                range: ClosedRange<CGFloat>, collapsible: Bool = true, title: String? = nil,
                first: PaneNode, second: PaneNode) {
        self.id = id
        self.axis = axis
        self.sized = sized
        self.defaultSize = size
        self.range = range
        self.collapsible = collapsible
        self.title = title
        self.first = first
        self.second = second
    }

    /// The window edge the sized child closes against.
    public var edge: PaneEdge {
        switch (axis, sized) {
        case (.horizontal, .first): .leading
        case (.horizontal, .second): .trailing
        case (.vertical, .first): .top
        case (.vertical, .second): .bottom
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
                             _ first: PaneNode, _ second: PaneNode) -> PaneNode {
        .branch(Split(id, axis, sized: sized, size: size, range: range, collapsible: collapsible,
                      title: title, first: first, second: second))
    }

    /// Every pane's id, in order.
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

    public init(size: CGFloat? = nil, collapsed: Bool = false) {
        self.size = size
        self.collapsed = collapsed
    }

    /// Field by field (CLAUDE.md): one unreadable field doesn't lose the other.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = (try? c.decodeIfPresent(CGFloat.self, forKey: .size)) ?? nil
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? false
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
    public func isPoppedOut(_ paneID: String) -> Bool { panes[paneID]?.poppedOut ?? false }
}
