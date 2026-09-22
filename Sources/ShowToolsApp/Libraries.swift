import SwiftUI
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
