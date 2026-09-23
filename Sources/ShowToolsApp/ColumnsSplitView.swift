import AppKit

/// Two or three columns — main, an optional list, inspector — laid out by
/// hand, because a constraint-based split view can't do all of these at
/// once:
///
/// - dragging a divider resizes only the two columns beside it;
/// - resizing the window resizes only the main column;
/// - collapsing the inspector (drag its divider to the edge) keeps the
///   list's width, so the list moves over and the main column grows;
/// - showing the inspector again restores its last width, list untouched.
///
/// With holding priorities, whichever column ranks lowest absorbs every
/// change, including divider drags that don't touch it (measured 2026-09-21).
///
/// Edit Show has a preview, a list and an inspector; Edit Slides has no
/// middle list column. Rather than fake one, the two-pane initializer skips
/// it: `hasList` is false, `listWidth`/`listRange` go unused, and every
/// method that indexed subviews positionally for `list` now goes through
/// the `list` accessor, which is `nil` when there isn't one.
@MainActor
final class ColumnsSplitView: NSSplitView {
    var mainMin: CGFloat = 420
    var listRange: ClosedRange<CGFloat> = 180...420
    /// Its least is what the inspector's content needs (the Rotation pivot
    /// pads side by side measured 316): narrower, it was cut off.
    var inspectorRange: ClosedRange<CGFloat> = 320...440

    /// Remembered between launches.
    private(set) var listWidth: CGFloat
    private(set) var inspectorWidth: CGFloat
    private let defaultsKey: String
    /// False for the two-pane shape (Edit Slides): no middle list column.
    private let hasList: Bool
    /// The divider between the (list or main) column and the inspector:
    /// index 1 in three panes, index 0 — the only divider — in two.
    private var inspectorDividerIndex: Int { hasList ? 1 : 0 }

    /// Called when the user collapses or reveals the inspector by dragging.
    var onInspectorShownChange: ((Bool) -> Void)?

    private var inspectorShown = true
    private var arranging = false
    /// True only while a divider is being moved. Widths are remembered, and
    /// a collapse noticed, only then: the split view also reports its own
    /// window-resize layout (twice per resize, measured), and a squeeze from
    /// a narrow window must not become the remembered width.
    private var draggingDivider = false

    /// NSSplitView tracks a divider drag inside mouseDown, returning when
    /// the mouse comes up — so the whole drag happens within this call.
    override func mouseDown(with event: NSEvent) {
        // Closed, the inspector is a collapsed subview at the very right
        // edge, and AppKit offers no divider beside a collapsed column —
        // measured 2026-09-23, which is why pulling it back open did
        // nothing however wide its grab strip was made. So that one drag
        // is tracked here instead.
        if !inspectorShown, convert(event.locationInWindow, from: nil).x >= bounds.width - grabWidth {
            revealByDragging()
            return
        }
        draggingDivider = true
        defer { draggingDivider = false }
        super.mouseDown(with: event)
    }

    /// Pull the closed inspector out from the right edge.
    private func revealByDragging() {
        guard let window else { return }
        var opened = false
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
              event.type != .leftMouseUp {
            let wanted = bounds.width - convert(event.locationInWindow, from: nil).x
            // A small twitch shouldn't open it: a hand that means to drag
            // travels further than one that meant to click.
            guard opened || wanted >= 12 else { continue }
            if !opened {
                opened = true
                inspectorShown = true
                onInspectorShownChange?(true)
            }
            inspectorWidth = min(max(wanted, inspectorRange.lowerBound), inspectorRange.upperBound)
            arrange()
        }
        guard opened else { return }
        UserDefaults.standard.set(Double(inspectorWidth), forKey: defaultsKey + ".inspector")
    }

    override func setPosition(_ position: CGFloat, ofDividerAt index: Int) {
        draggingDivider = true
        defer { draggingDivider = false }
        super.setPosition(position, ofDividerAt: index)
    }

    init(main: NSView, list: NSView, inspector: NSView, defaultsKey: String) {
        self.defaultsKey = defaultsKey
        hasList = true
        let d = UserDefaults.standard
        listWidth = CGFloat(d.object(forKey: defaultsKey + ".list") as? Double ?? 230)
        inspectorWidth = CGFloat(d.object(forKey: defaultsKey + ".inspector") as? Double ?? 290)
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 400))
        isVertical = true
        dividerStyle = .thin
        rules = ColumnsDelegate(self)
        delegate = rules
        for v in [main, list, inspector] {
            v.translatesAutoresizingMaskIntoConstraints = true
            addSubview(v)
        }
    }

    /// The two-pane shape (Edit Slides): no middle list column.
    init(main: NSView, inspector: NSView, defaultsKey: String) {
        self.defaultsKey = defaultsKey
        hasList = false
        listWidth = 0
        let d = UserDefaults.standard
        inspectorWidth = CGFloat(d.object(forKey: defaultsKey + ".inspector") as? Double ?? 290)
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 400))
        isVertical = true
        dividerStyle = .thin
        rules = ColumnsDelegate(self)
        delegate = rules
        for v in [main, inspector] {
            v.translatesAutoresizingMaskIntoConstraints = true
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Held here: `delegate` is weak.
    private var rules: ColumnsDelegate?

    private var main: NSView { subviews[0] }
    private var list: NSView? { hasList ? subviews[1] : nil }
    private var inspector: NSView { subviews[hasList ? 2 : 1] }

    var isInspectorShown: Bool { inspectorShown }

    /// Show or hide the inspector from outside (toolbar, double-click).
    func setInspectorShown(_ shown: Bool) {
        guard shown != inspectorShown else { return }
        inspectorShown = shown
        arrange()
    }

    /// Put the columns back to given widths (View ▸ Restore Default
    /// Layout). Saved here as well as arranged, because nothing else is
    /// dragging a divider to save them.
    func setWidths(list: CGFloat, inspector: CGFloat) {
        if hasList { listWidth = min(max(list, listRange.lowerBound), listRange.upperBound) }
        inspectorWidth = min(max(inspector, inspectorRange.lowerBound), inspectorRange.upperBound)
        arrange()
        let d = UserDefaults.standard
        if hasList { d.set(Double(listWidth), forKey: defaultsKey + ".list") }
        d.set(Double(inspectorWidth), forKey: defaultsKey + ".inspector")
    }

    // MARK: Layout

    /// Places every column from the remembered widths. The main column
    /// takes whatever is left.
    func arrange() {
        arranging = true
        defer { arranging = false }
        let W = bounds.width, H = bounds.height, t = dividerThickness
        // Remembered widths are held to their limits here, not only when a
        // narrow window squeezes: a width saved under older limits (the
        // inspector's 260) would otherwise come back as it was.
        var listW = hasList ? min(max(listWidth, listRange.lowerBound), listRange.upperBound) : 0
        var insW = inspectorShown ? min(max(inspectorWidth, inspectorRange.lowerBound), inspectorRange.upperBound) : 0
        // A narrow window squeezes the side columns before the main one
        // goes below its minimum.
        // One gap per visible divider (none at the window edge when the
        // inspector is hidden, and none for a list column that isn't there).
        let dividerCount = (hasList ? 1 : 0) + (inspectorShown ? 1 : 0)
        let gaps = CGFloat(dividerCount)
        var mainW = W - listW - insW - gaps * t
        if mainW < mainMin {
            var short = mainMin - mainW
            let insGive = inspectorShown ? min(short, insW - inspectorRange.lowerBound) : 0
            insW -= max(insGive, 0); short -= max(insGive, 0)
            if hasList {
                let listGive = min(short, listW - listRange.lowerBound)
                listW -= max(listGive, 0)
            }
            mainW = max(W - listW - insW - gaps * t, 0)
        }
        main.frame = NSRect(x: 0, y: 0, width: mainW, height: H)
        // Closed, the inspector is simply zero-width. It used to be sent
        // isHidden as well; that was removed after measuring that AppKit
        // marks a zero-width subview collapsed (and hidden) by itself, so
        // the line changed nothing either way. What it does not do is
        // offer a divider beside a collapsed column, which is why
        // mouseDown tracks that one drag itself.
        if hasList, let list {
            list.frame = NSRect(x: mainW + t, y: 0, width: listW, height: H)
            inspector.frame = NSRect(x: mainW + t + listW + t, y: 0, width: insW, height: H)
        } else {
            inspector.frame = NSRect(x: mainW + t, y: 0, width: insW, height: H)
        }
    }

    // MARK: Divider lines

    /// NSSplitView draws each divider in a layer of its own and only moves
    /// those layers when it lays the columns out itself, so with this manual
    /// layout they were left behind: a stale line across the preview where
    /// the list used to be (found by dumping the layer tree, 2026-09-21).
    /// Instead they're drawn clear, and the split view's own background
    /// shows through the 1pt gaps between columns, which are always right.
    override var dividerColor: NSColor { .clear }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        updateGapColour()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGapColour()
    }

    private func updateGapColour() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) { arrange() }

    // MARK: Divider limits (called by ColumnsDelegate)

    /// How wide a divider is to the mouse. The line drawn is 1pt, which is
    /// fiddly with a trackpad and worse with touch — Jason kept missing
    /// them, and one miss that registered as a double-click is what broke
    /// the layout on 2026-09-23.
    var grabWidth: CGFloat = 11

    /// The strip that counts as the divider, over and above the 1pt line.
    func splitView(_ sv: NSSplitView, additionalEffectiveRectOfDividerAt i: Int) -> NSRect {
        // Closed, the inspector's divider sits on the window's right edge,
        // where half a centred strip would be off the window: put all of
        // it inside, so there is something to pull the inspector out by.
        if i == inspectorDividerIndex, !inspectorShown {
            return NSRect(x: bounds.width - grabWidth, y: 0, width: grabWidth, height: bounds.height)
        }
        let centre = i == 0 ? main.frame.maxX : (list?.frame.maxX ?? main.frame.maxX)
        return NSRect(x: centre - (grabWidth - dividerThickness) / 2, y: 0,
                      width: grabWidth, height: bounds.height)
    }

    func splitView(_ sv: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        if i == 0 { return mainMin }
        // Closed, the inspector's space was given to the main column, so
        // dragging it back open takes that space back and the list keeps
        // its width. Measuring from the list's current position instead
        // put the minimum (1309) past the maximum (1055), and a divider
        // whose range is empty cannot be dragged at all — which is why it
        // looked stuck (2026-09-23).
        if !inspectorShown { return mainMin + dividerThickness + listWidth }
        return (list?.frame.minX ?? 0) + listRange.lowerBound
    }

    func splitView(_ sv: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        if i == 0, let list {
            return min(list.frame.maxX - listRange.lowerBound, list.frame.maxX)
        }
        // Past this the inspector would be too narrow; further still and
        // it collapses (the split view's own rule for collapsible views).
        return bounds.width - dividerThickness - inspectorRange.lowerBound
    }

    func splitView(_ sv: NSSplitView, canCollapseSubview v: NSView) -> Bool { v === inspector }

    func splitView(_ sv: NSSplitView, shouldCollapseSubview v: NSView,
                   forDoubleClickOnDividerAt i: Int) -> Bool { false }

    func splitView(_ sv: NSSplitView, shouldAdjustSizeOfSubview v: NSView) -> Bool { v === main }

    /// After a divider drag: remember the widths it produced, and notice a
    /// collapse or reveal. A collapse by dragging hands the inspector's space
    /// to the list, so the list is put back to its width and the main column
    /// takes the space instead.
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard draggingDivider, !arranging else { return }
        let collapsed = isSubviewCollapsed(inspector) || inspector.frame.width < 1
        if collapsed {
            if inspectorShown {
                inspectorShown = false
                onInspectorShownChange?(false)
            }
            arrange()
        } else if !inspectorShown {
            // Dragged back open. The collapse handed the inspector's space
            // to the main column, so the reveal takes it back from there:
            // arrange() puts the list at its remembered width again.
            inspectorShown = true
            onInspectorShownChange?(true)
            inspectorWidth = min(max(inspector.frame.width, inspectorRange.lowerBound),
                                 inspectorRange.upperBound)
            arrange()
        } else {
            if hasList, let list {
                listWidth = min(max(list.frame.width, listRange.lowerBound), listRange.upperBound)
            }
            inspectorWidth = min(max(inspector.frame.width, inspectorRange.lowerBound), inspectorRange.upperBound)
        }
        let d = UserDefaults.standard
        if hasList { d.set(Double(listWidth), forKey: defaultsKey + ".list") }
        d.set(Double(inspectorWidth), forKey: defaultsKey + ".inspector")
    }
}

/// The split view's delegate: its own object, passing every call to the
/// split view. The split view mustn't be its own delegate: AppKit answers
/// "does it respond to toggleSidebar:?" by asking the delegate, so a split
/// view that is its own delegate asks itself forever and crashes (measured
/// in a harness, 2026-09-21, and seen once in the app, from a menu check
/// while the keyboard was in Edit Show's columns).
@MainActor
private final class ColumnsDelegate: NSObject, @preconcurrency NSSplitViewDelegate {
    unowned let owner: ColumnsSplitView
    init(_ owner: ColumnsSplitView) { self.owner = owner }

    func splitView(_ sv: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        owner.splitView(sv, constrainMinCoordinate: proposed, ofSubviewAt: i)
    }
    func splitView(_ sv: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        owner.splitView(sv, constrainMaxCoordinate: proposed, ofSubviewAt: i)
    }
    func splitView(_ sv: NSSplitView, canCollapseSubview v: NSView) -> Bool {
        owner.splitView(sv, canCollapseSubview: v)
    }
    func splitView(_ sv: NSSplitView, shouldCollapseSubview v: NSView, forDoubleClickOnDividerAt i: Int) -> Bool {
        owner.splitView(sv, shouldCollapseSubview: v, forDoubleClickOnDividerAt: i)
    }
    func splitView(_ sv: NSSplitView, shouldAdjustSizeOfSubview v: NSView) -> Bool {
        owner.splitView(sv, shouldAdjustSizeOfSubview: v)
    }
    func splitView(_ sv: NSSplitView, additionalEffectiveRectOfDividerAt i: Int) -> NSRect {
        owner.splitView(sv, additionalEffectiveRectOfDividerAt: i)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        owner.splitViewDidResizeSubviews(notification)
    }
}
