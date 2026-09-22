import AppKit
import SwiftUI
import BGToolsCore
import ShowToolsCore
import ShowToolsPlayback

/// Which page BGTools' window shows: shared with the panel, so "Open in
/// BGTools…" lands on the right screen.
@MainActor
@Observable
final class WindowState {
    var selection: Selection?
}

/// The compact panel (spec/bgtools.md, B4b): drops from the top right like
/// a Control Center module. It doesn't make BGTools the active app, and
/// closes on a click anywhere else or Escape.
final class ControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

@MainActor
final class PanelController {
    private var panel: ControlPanel?
    private var outsideClicks: Any?
    private let desktop: DesktopController
    private let windowState: WindowState
    private let openWindow: () -> Void

    init(desktop: DesktopController, windowState: WindowState, openWindow: @escaping () -> Void) {
        self.desktop = desktop
        self.windowState = windowState
        self.openWindow = openWindow
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        if panel == nil {
            let p = ControlPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .popUpMenu
            p.isReleasedWhenClosed = false
            p.hasShadow = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let root = PanelView(close: { [weak self] in self?.close() },
                                 openWindow: { [weak self] sel in
                                     self?.windowState.selection = sel
                                     self?.close()
                                     self?.openWindow()
                                 })
                .environment(desktop)
            // The controller sizes the panel to its content, and again when
            // the content grows (All same on, a Space added).
            let host = NSHostingController(rootView: root)
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pinToCorner() }
            }
            panel = p
        }
        guard let panel else { return }
        desktop.keepReaders = true
        // The screen the pointer is on, like Control Center.
        let mouse = NSEvent.mouseLocation
        screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        if let size = panel.contentViewController?.view.fittingSize, size.width > 0 { panel.setContentSize(size) }
        pinToCorner()
        panel.makeKeyAndOrderFront(nil)
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        Log.write("panel opened on \(screen?.localizedName ?? "?") at \(panel.frame)")
    }

    private var screen: NSScreen?

    /// Top right of its screen, under the menu bar, whatever its height.
    private func pinToCorner() {
        guard let panel, let visible = screen?.visibleFrame else { return }
        let f = panel.frame
        let origin = NSPoint(x: visible.maxX - f.width - 10, y: visible.maxY - f.height - 6)
        if f.origin != origin { panel.setFrameOrigin(origin) }
    }

    func close() {
        if let m = outsideClicks { NSEvent.removeMonitor(m) }
        outsideClicks = nil
        panel?.orderOut(nil)
        desktop.keepReaders = NSApp.windows.contains { $0.isVisible && !($0 is ControlPanel) && $0.level == .normal }
    }
}

// MARK: The panel's content

private struct PanelView: View {
    @Environment(DesktopController.self) private var desktop
    let close: () -> Void
    let openWindow: (Selection?) -> Void

    private var displays: [(name: String, spaces: [ScreenInfo])] {
        var order: [String] = []
        var byDisplay: [String: [ScreenInfo]] = [:]
        for s in desktop.screens {
            if byDisplay[s.key.display] == nil { order.append(s.key.display) }
            byDisplay[s.key.display, default: []].append(s)
        }
        return order.map { (byDisplay[$0]![0].displayName, byDisplay[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BGTools").font(.headline)
                Spacer()
                Toggle("Desktop Show", isOn: Binding(get: { desktop.settings.on },
                                                     set: { on in desktop.update { $0.on = on } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help("Turns the desktop show on or off on every screen")
            }
            Toggle("All same", isOn: Binding(get: { desktop.settings.allSame }, set: { on in
                desktop.update {
                    $0.allSame = on
                    if on, $0.allSameSetting == nil { $0.allSameSetting = $0.newScreens }
                }
            }))
            .help("One choice on every monitor and Space, in sync")

            if desktop.settings.allSame {
                PanelRow(title: "All same", subtitle: summary(desktop.settings.allSameSetting),
                         highlighted: true, player: desktop.players["all"],
                         setting: desktop.settings.allSameSetting,
                         change: { new in desktop.update { $0.allSameSetting = new } },
                         open: { openWindow(.allSame) })
            } else {
                ForEach(displays, id: \.name) { d in
                    Text(d.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(d.spaces) { s in
                        PanelRow(title: s.spaceIndex > 0 ? "Space \(s.spaceIndex)" : "Every Space",
                                 subtitle: desktop.summary(for: s.id), highlighted: s.isCurrent,
                                 player: desktop.player(for: s.id),
                                 setting: desktop.settings.setting(for: s.id),
                                 change: { new in desktop.update { $0.screens[s.id] = new } },
                                 open: { openWindow(.screen(s.id)) })
                    }
                }
            }

            Divider()
            HStack {
                Text("New screens").foregroundStyle(.secondary)
                Spacer()
                SettingMenu(setting: desktop.settings.newScreens, label: summary(desktop.settings.newScreens)) { new in
                    desktop.update { $0.newScreens = new }
                }
            }
            Button {
                openWindow(.randomPictures)
            } label: {
                HStack {
                    Text("Random pictures").foregroundStyle(.secondary)
                    Spacer()
                    Text(randomSummary).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            Button("Open BGTools…") { openWindow(nil) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 360)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
    }

    private func summary(_ s: ScreenSetting?) -> String {
        guard let s else { return "Nothing" }
        return DesktopController.describe(s.mode, in: desktop.reader(for: s.library)?.contents)
    }

    private var randomSummary: String {
        let d = desktop.settings.randomDefaults
        let length = d.length == d.length.rounded() ? "\(Int(d.length)) s" : String(format: "%.1f s", d.length)
        return [length, d.transition.style.title, d.kenBurns == .off ? nil : "Ken Burns"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// One screen: live thumbnail, what it plays, and its three controls.
private struct PanelRow: View {
    @Environment(DesktopController.self) private var desktop
    let title: String
    let subtitle: String
    let highlighted: Bool
    let player: Player?
    let setting: ScreenSetting?
    let change: (ScreenSetting?) -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Rectangle().fill(.black)
                if let engine = player?.engine { ShowCanvasView(engine: engine) }
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(highlighted ? Color.accentColor : .clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(highlighted ? .semibold : .regular)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            SettingMenu(setting: setting, label: nil, change: change)
            Button { player?.engine.step(1) } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(.borderless)
                .disabled(player == nil)
                .help("Next picture")
                .accessibilityLabel("Next picture")
            Menu {
                if let setting {
                    Toggle("Stills only", isOn: Binding(get: { setting.stillsOnly },
                                                        set: { v in var s = setting; s.stillsOnly = v; change(s) }))
                    Toggle("Sound", isOn: Binding(get: { setting.sound },
                                                  set: { v in var s = setting; s.sound = v; change(s) }))
                    Divider()
                }
                Button("Open in BGTools…", action: open)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Stills only, Sound, and more in BGTools' window")
            .accessibilityLabel("Options")
        }
        .frame(height: 44)
    }
}

/// Every choice of what to play, as one menu: shows in order or
/// shuffled, collections, a random show, all files. Keeps the library.
private struct SettingMenu: View {
    @Environment(DesktopController.self) private var desktop
    let setting: ScreenSetting?
    /// Nil shows only the ▾.
    let label: String?
    let change: (ScreenSetting?) -> Void

    var body: some View {
        let base = setting ?? desktop.startingSetting()
        let contents = base.flatMap { desktop.reader(for: $0.library)?.contents }
        Menu {
            if let base, let contents {
                let set: (PlayMode) -> Void = { mode in var s = base; s.mode = mode; change(s) }
                Menu("A show") {
                    ForEach(contents.shows) { show in Button(show.name) { set(.show(show.id)) } }
                }
                Menu("A show, shuffled") {
                    ForEach(contents.shows) { show in Button(show.name) { set(.shuffled(show.id)) } }
                }
                Menu("Random from a collection") {
                    ForEach(contents.collections) { c in Button(c.name) { set(.collection(c.id)) } }
                }
                Button("A random show") { set(.randomShow) }
                Button("Random from all files") { set(.allFiles) }
            }
            if setting != nil, label != nil {
                Divider()
                Button("Nothing") { change(nil) }
            }
        } label: {
            if let label { Text(label) } else { Image(systemName: "chevron.down") }
        }
        .menuStyle(.borderlessButton)
        // The icon-only one is its own chevron; the labelled one keeps the
        // menu's.
        .menuIndicator(label == nil ? .hidden : .visible)
        .fixedSize()
        .help("What this plays")
        .accessibilityLabel(label ?? "What this plays")
    }
}

/// The frosted background Control Center's modules use.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
