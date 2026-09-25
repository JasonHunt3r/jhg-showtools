import SwiftUI
import AppKit
import LocalAuthentication
import ShowToolsCore
import ShowToolsPlayback

/// "Prove it's you": Touch ID, or the Mac's login password
/// (LocalAuthentication's device-owner check). False if cancelled, failed,
/// or the Mac can't ask.
enum DeviceOwner {
    static func confirm(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// File ▸ Open Library…: pick a ShowTools library folder.
@MainActor
func runOpenLibraryPanel(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Library"
    panel.message = "Choose a ShowTools library folder."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard FileManager.default.fileExists(atPath: url.appendingPathComponent("Library.sqlite").path) else {
        let alert = NSAlert()
        alert.messageText = "“\(url.lastPathComponent)” isn't a ShowTools library."
        alert.informativeText = "Choose the folder that holds Library.sqlite, or make a new library with File ▸ New Library…."
        alert.runModal()
        return
    }
    Task { await model.openLibrary(at: url) }
}

/// File ▸ New Library…: a new, empty library, hidden from Spotlight like the
/// master (its folder ends in .noindex; Settings can change that).
@MainActor
func runNewLibraryPanel(_ model: AppModel) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "New ShowTools Library"
    panel.prompt = "Create"
    panel.message = "A new library is a folder of its own. It's hidden from Spotlight to start with."
    guard panel.runModal() == .OK, var url = panel.url else { return }
    if url.pathExtension != "noindex" { url.appendPathExtension("noindex") }
    guard !FileManager.default.fileExists(atPath: url.path) else {
        let alert = NSAlert()
        alert.messageText = "There's already something called “\(url.lastPathComponent)” there."
        alert.runModal()
        return
    }
    Task { await model.openLibrary(at: url) }
}

/// Shown instead of the library when it's private and not yet unlocked
/// (the master, if it's private, at launch).
struct LockedLibraryView: View {
    let name: String
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("“\(name)” is private", systemImage: "lock.fill")
        } description: {
            Text("Unlock it with Touch ID or your Mac's password.")
        } actions: {
            Button("Unlock") { Task { await model.unlock() } }
                .keyboardShortcut(.defaultAction)
            Button("Open Another Library…") { runOpenLibraryPanel(model) }
        }
        // The whole window: nothing of the library shows round it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// The library panel (`spec/windows.md`, "A possible order" #3, and Jason's
/// answer 6): the whole library, in a window of its own. Settled as a
/// **panel** (floats above the app's other windows) rather than an ordinary
/// window — it's meant to float over a new, empty collection so the whole
/// panel becomes a drop target (`spec/windows.md`, "Filling a new
/// collection", the problem it solves). Opens from the Library item's
/// context menu; moves nothing out of the main window, which keeps showing
/// its own Library grid exactly as before. Follows `InfoPanel`'s pattern
/// (an `NSPanel` hosting SwiftUI, its own shared `undoManager`) rather than
/// a new SwiftUI window scene, per `spec/windows.md`'s note on the
/// layout-loop crash.
@MainActor
final class LibraryPanel: NSObject, NSWindowDelegate {
    private static var shared: LibraryPanel?

    static func show(model: AppModel, undoManager: UndoManager?) {
        if let shared { shared.window.makeKeyAndOrderFront(nil); return }
        let panel = LibraryPanel(model: model, undoManager: undoManager)
        shared = panel
        panel.present()
    }

    private let window: LibraryPanelWindow

    private init(model: AppModel, undoManager: UndoManager?) {
        window = LibraryPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Library"
        // Narrow, it's a list; wider, the grid's own tile-size slider
        // already grows the thumbnails (spec/windows.md, answer 6) — no
        // second view needed, just the grid in a window of its own.
        window.minSize = NSSize(width: 240, height: 300)
        window.isFloatingPanel = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.sharedUndoManager = undoManager
        // Passed in via `undoManagerOverride`, not read from the
        // environment — the same fix InfoPanel's own content needed (see
        // its note): a separate window's undoManager isn't the main
        // window's, and `\.undoManager` isn't a writable environment key.
        let content = LibraryGridView(undoManagerOverride: undoManager).environment(model)
        window.contentView = NSHostingView(rootView: content)
        window.setFrameAutosaveName("libraryPanel")
    }

    private func present() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}

/// Overriding `undoManager` matters the same way it does for `InfoPanelWindow`
/// (see its own note): without it, ⌘Z right after an edit made from this
/// panel would ask the wrong manager.
final class LibraryPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    var sharedUndoManager: UndoManager?
    override var undoManager: UndoManager? { sharedUndoManager }
}
