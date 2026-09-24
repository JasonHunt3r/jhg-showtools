// PaneKit's test app (spec/panekit.md, "The order", step 1).
//
//   cd PaneKit && swift run PaneHarness
//
// A window laid out by PaneKit with coloured dummy panes, in three shapes
// (the Layout menu): Finder's two panes, Mail's three columns, and
// ShowTools' own layout, the demanding example. Nothing here knows about
// ShowTools beyond that one tree; PaneKit is meant for any Mac app.
//
// What to check (Claude Code on the Mac runs it; Jason feels it):
// - Dragging each divider resizes only the two panes beside it; a window
//   resize goes to the main pane.
// - Dragging a divider toward its edge closes that pane; a visible handle
//   stays on the edge. Drag the handle out, or double-click it, to reopen.
//   Double-clicking a divider closes its pane.
// - View ▸ "<pane> in Its Own Window" pops a pane out (panels float;
//   ShowTools' Timeline is an ordinary window). The main window closes up.
//   Closing the pane's window puts it back in its slot, at its old size.
// - Quit and relaunch: sizes, closed panes, popped-out panes and their
//   window positions all come back.
// - Undo: "Make an undoable change" in a popped-out panel, then ⌘Z in the
//   main window, and the other way round. One history.
// - Typing into a pane's text field works in the window and in a panel.
// - View ▸ Restore Default Layout, and Test ▸ the two presets: each is one
//   step, with nothing half-moved drawn.
// - Test ▸ Stress: sixty rapid layout changes. No layout-loop exception
//   (it would print below and crash).
import AppKit
import PaneKit

@main
struct PaneHarness {
    @MainActor static func main() {
        NSSetUncaughtExceptionHandler { e in
            print("UNCAUGHT: \(e.name.rawValue): \(e.reason ?? "")")
        }
        let app = NSApplication.shared
        let delegate = HarnessDelegate()
        Keep.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
enum Keep {
    static var delegate: HarnessDelegate?
}

/// The three shapes: one primitive, nested three ways.
enum Shape: String, CaseIterable {
    case finder, mail, showTools

    var title: String {
        switch self {
        case .finder: "Finder: two panes"
        case .mail: "Mail: three columns"
        case .showTools: "ShowTools: timeline under everything"
        }
    }

    var tree: PaneNode {
        switch self {
        case .finder:
            .split("window", .horizontal, sized: .first, size: 200, range: 150...320,
                   .pane("sidebar", title: "Sidebar", popOut: .panel),
                   .pane("files", title: "Files", minSize: 240))
        case .mail:
            // NOTE (2026-09-24, found building `.row`): this nests message
            // as the innermost main, mailboxes as the outermost sized —
            // which gives both mailboxes and the message list a real,
            // independent cap, but at a cost not spotted when this shape
            // was first written: dragging the mailboxes|list divider (outer
            // split's own) changes mailboxes and the *message* pane, not
            // list, since list is protected as reading's own sized side.
            // Divider isolation says it should move only mailboxes and
            // list. `.row` (below, and PaneKitTests) makes the opposite
            // trade instead — see its doc comment. Left as it was for the
            // harness's own three-column demo; not a real app.
            .split("window", .horizontal, sized: .first, size: 190, range: 150...300, title: "Mailboxes",
                   .pane("mailboxes", title: "Mailboxes", popOut: .panel),
                   .split("reading", .horizontal, sized: .first, size: 340, range: 240...520, title: "Message List",
                          .pane("list", title: "Message List", popOut: .panel),
                          .pane("message", title: "Message", minSize: 300)))
        case .showTools:
            .split("window", .vertical, sized: .second, size: 240, range: 120...600, title: "Timeline",
                   .split("top", .horizontal, sized: .first, size: 219, range: 180...360, title: "Library",
                          .pane("library", title: "Library", popOut: .panel),
                          .row("columns", .horizontal, mainFirst: true,
                               main: Pane("viewer", title: "Viewer", minSize: 300),
                               near: Pane("browser", title: "Browser", popOut: .panel), nearDefault: 245, nearMax: 419,
                               far: Pane("inspector", title: "Inspector", popOut: .panel),
                               farSize: 320, farRange: 260...480)),
                   .pane("timeline", title: "Timeline", popOut: .window))
        }
    }
}

@MainActor
final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: PaneController!
    private let viewMenu = NSMenu(title: "View")
    private var stressSteps = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.setFrameAutosaveName("PaneHarnessMain")
        if window.frame.origin == .zero { window.center() }
        buildMenus()
        let saved = UserDefaults.standard.string(forKey: "PaneHarness.shape").flatMap(Shape.init) ?? .showTools
        show(saved)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Lays the window out in a shape, with its own saved state.
    private func show(_ shape: Shape) {
        // Put the old shape's popped-out windows away first; its state keeps
        // them out, so they come back when that shape is picked again.
        controller?.poppedOutWindows.forEach { $0.orderOut(nil) }
        UserDefaults.standard.set(shape.rawValue, forKey: "PaneHarness.shape")
        window.title = "PaneKit harness — \(shape.title)"
        let c = PaneController(id: "Harness.\(shape.rawValue)", root: shape.tree)
        c.undoSource = window
        var content: [String: NSView] = [:]
        for (n, pane) in shape.tree.panes.enumerated() {
            content[pane.id] = DemoPane(title: pane.title, hue: CGFloat(n) / CGFloat(shape.tree.panes.count))
        }
        controller = c
        window.contentView = PaneContainerView(controller: c, content: content)
        rebuildViewMenu()
    }

    // MARK: Menus

    private func buildMenus() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PaneKit Harness", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let layoutItem = NSMenuItem()
        let layout = NSMenu(title: "Layout")
        for shape in Shape.allCases {
            let item = layout.addItem(withTitle: shape.title, action: #selector(pickShape(_:)), keyEquivalent: "")
            item.representedObject = shape.rawValue
            item.target = self
        }
        layoutItem.submenu = layout
        main.addItem(layoutItem)

        let testItem = NSMenuItem()
        let test = NSMenu(title: "Test")
        test.addItem(withTitle: "Preset: Main Pane Only", action: #selector(presetMainOnly), keyEquivalent: "").target = self
        test.addItem(withTitle: "Preset: Everything Open", action: #selector(presetEverything), keyEquivalent: "").target = self
        test.addItem(.separator())
        test.addItem(withTitle: "Stress: Sixty Rapid Changes", action: #selector(stress), keyEquivalent: "").target = self
        testItem.submenu = test
        main.addItem(testItem)

        NSApp.mainMenu = main
    }

    private func rebuildViewMenu() {
        viewMenu.removeAllItems()
        for item in controller.menuItems() { viewMenu.addItem(item) }
    }

    @objc private func pickShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shape = Shape(rawValue: raw) else { return }
        show(shape)
    }

    /// Every closable pane closed, and nothing out in a window: the main
    /// panes get the whole window. One transaction.
    @objc private func presetMainOnly() {
        var s = PaneKitState()
        for split in controller.root.splits where split.collapsible {
            s.splits[split.id] = SplitState(collapsed: true)
        }
        controller.apply(s)
    }

    @objc private func presetEverything() { controller.apply(PaneKitState()) }

    /// Sixty layout changes, 30 ms apart: closing and opening panes,
    /// popping them out and back, and presets.
    @objc private func stress() {
        stressSteps = 60
        stressStep()
    }

    private func stressStep() {
        guard stressSteps > 0, let c = controller else { return }
        stressSteps -= 1
        let splits = c.root.splits.filter(\.collapsible)
        let poppable = c.root.panes.filter { $0.popOut != .none }
        switch Int.random(in: 0..<4) {
        case 0: if let s = splits.randomElement() { c.toggle(s.id) }
        case 1: if let p = poppable.randomElement() { c.togglePopOut(p.id) }
        case 2: presetMainOnly()
        default: c.restoreDefaults()
        }
        if stressSteps == 0 { c.restoreDefaults() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.stressStep() }
    }
}

/// A dummy pane: its name, a text field to type in, and a button that makes
/// an undoable change (a counter), to check ⌘Z across windows.
@MainActor
final class DemoPane: NSView {
    private let count = NSTextField(labelWithString: "Changes: 0")
    private var value = 0

    init(title: String, hue: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hue: hue, saturation: 0.25, brightness: 0.95, alpha: 1).cgColor
        let name = NSTextField(labelWithString: title)
        name.font = .boldSystemFont(ofSize: 15)
        let field = NSTextField(string: "")
        field.placeholderString = "Type here"
        let button = NSButton(title: "Make an undoable change", target: self, action: #selector(change))
        let stack = NSStackView(views: [name, field, button, count])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            field.widthAnchor.constraint(equalToConstant: 160),
        ])
    }

    required init?(coder: NSCoder) { fatalError("DemoPane is made in code") }

    override var isFlipped: Bool { true }

    @objc private func change() { set(value + 1) }

    /// Registered on this view's window's undo manager, which in a popped-out
    /// pane is the main window's, so both windows share one history.
    private func set(_ v: Int) {
        let old = value
        value = v
        count.stringValue = "Changes: \(v)"
        window?.undoManager?.registerUndo(withTarget: self) { pane in
            MainActor.assumeIsolated { pane.set(old) }
        }
        window?.undoManager?.setActionName("Change")
    }
}
