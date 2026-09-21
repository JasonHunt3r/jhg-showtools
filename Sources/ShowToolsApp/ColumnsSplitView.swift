import AppKit

/// Three columns — main, list, inspector — laid out by hand, because a
/// constraint-based split view can't do all of these at once:
///
/// - dragging a divider resizes only the two columns beside it;
/// - resizing the window resizes only the main column;
/// - collapsing the inspector (drag its divider to the edge) keeps the
///   list's width, so the list moves over and the main column grows;
/// - showing the inspector again restores its last width, list untouched.
///
/// With holding priorities, whichever column ranks lowest absorbs every
/// change, including divider drags that don't touch it (measured 2026-09-21).
@MainActor
final class ColumnsSplitView: NSSplitView, @preconcurrency NSSplitViewDelegate {
    var mainMin: CGFloat = 420
    var listRange: ClosedRange<CGFloat> = 180...420
    var inspectorRange: ClosedRange<CGFloat> = 260...440

    /// Remembered between launches.
    private(set) var listWidth: CGFloat
    private(set) var inspectorWidth: CGFloat
    private let defaultsKey: String

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
        draggingDivider = true
        defer { draggingDivider = false }
        super.mouseDown(with: event)
    }

    override func setPosition(_ position: CGFloat, ofDividerAt index: Int) {
        draggingDivider = true
        defer { draggingDivider = false }
        super.setPosition(position, ofDividerAt: index)
    }

    init(main: NSView, list: NSView, inspector: NSView, defaultsKey: String) {
        self.defaultsKey = defaultsKey
        let d = UserDefaults.standard
        listWidth = CGFloat(d.object(forKey: defaultsKey + ".list") as? Double ?? 230)
        inspectorWidth = CGFloat(d.object(forKey: defaultsKey + ".inspector") as? Double ?? 290)
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 400))
        isVertical = true
        dividerStyle = .thin
        delegate = self
        for v in [main, list, inspector] {
            v.translatesAutoresizingMaskIntoConstraints = true
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var main: NSView { subviews[0] }
    private var list: NSView { subviews[1] }
    private var inspector: NSView { subviews[2] }

    var isInspectorShown: Bool { inspectorShown }

    /// Show or hide the inspector from outside (toolbar, double-click).
    func setInspectorShown(_ shown: Bool) {
        guard shown != inspectorShown else { return }
        inspectorShown = shown
        arrange()
    }

    // MARK: Layout

    /// Places every column from the remembered widths. The main column
    /// takes whatever is left.
    func arrange() {
        arranging = true
        defer { arranging = false }
        let W = bounds.width, H = bounds.height, t = dividerThickness
        var listW = listWidth
        var insW = inspectorShown ? inspectorWidth : 0
        // A narrow window squeezes the side columns before the main one
        // goes below its minimum.
        // One gap when the inspector is hidden (no line at the window edge).
        let gaps: CGFloat = inspectorShown ? 2 : 1
        var mainW = W - listW - insW - gaps * t
        if mainW < mainMin {
            var short = mainMin - mainW
            let insGive = inspectorShown ? min(short, insW - inspectorRange.lowerBound) : 0
            insW -= max(insGive, 0); short -= max(insGive, 0)
            let listGive = min(short, listW - listRange.lowerBound)
            listW -= max(listGive, 0)
            mainW = max(W - listW - insW - gaps * t, 0)
        }
        main.frame = NSRect(x: 0, y: 0, width: mainW, height: H)
        list.frame = NSRect(x: mainW + t, y: 0, width: listW, height: H)
        inspector.isHidden = !inspectorShown
        inspector.frame = NSRect(x: mainW + t + listW + t, y: 0, width: insW, height: H)
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

    // MARK: Divider limits

    func splitView(_ sv: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        i == 0 ? mainMin : list.frame.minX + listRange.lowerBound
    }

    func splitView(_ sv: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt i: Int) -> CGFloat {
        if i == 0 {
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
        } else {
            if !inspectorShown {
                inspectorShown = true
                onInspectorShownChange?(true)
            }
            listWidth = min(max(list.frame.width, listRange.lowerBound), listRange.upperBound)
            inspectorWidth = min(max(inspector.frame.width, inspectorRange.lowerBound), inspectorRange.upperBound)
        }
        let d = UserDefaults.standard
        d.set(Double(listWidth), forKey: defaultsKey + ".list")
        d.set(Double(inspectorWidth), forKey: defaultsKey + ".inspector")
    }
}
