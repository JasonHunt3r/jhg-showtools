import SwiftUI
import ShowToolsCore

@main
struct ShowToolsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("ShowTools", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 1100, minHeight: 700)
                .task { DevHooks.run(model) }
        }
        .defaultSize(width: 1320, height: 820)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.activeShowID) private var activeShowID

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Show") { model.newShow() }
                .keyboardShortcut("n")
                .disabled(model.collections.isEmpty)
            Button("New Collection") { model.newCollection() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Import…") { runImportPanel(model) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Add to Library…") { runImportPanel(model, intoCollection: false) }
                .keyboardShortcut("i", modifiers: [.command, .shift, .option])
            Divider()
            // Libraries switch one at a time, as Photos does (plan, 2b).
            Button("Open Library…") { runOpenLibraryPanel(model) }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Menu("Open Recent Library") {
                ForEach(model.recentLibraries, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        Task { await model.openLibrary(at: url) }
                    }
                }
                if !model.recentLibraries.isEmpty { Divider() }
                Button("Clear Menu") { model.clearRecentLibraries() }
                    .disabled(model.recentLibraries.isEmpty)
            }
            Button("New Library…") { runNewLibraryPanel(model) }
            Button("Open Master Library") { Task { await model.openLibrary(at: model.masterURL) } }
                .disabled(model.isOnMaster)
        }

        CommandMenu("Show") {
            Button("Play") { play(fullScreen: false) }
                .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                .disabled(activeShow == nil)
            Button("Play Full Screen") { play(fullScreen: true) }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(activeShow == nil)
        }
    }

    private var activeShow: Show? {
        activeShowID.flatMap { model.show($0) }.flatMap { $0.slides.isEmpty ? nil : $0 }
    }

    @MainActor private func play(fullScreen: Bool) {
        if let show = activeShow { Player.open(show: show, model: model, fullScreen: fullScreen) }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SlideRemovalNotice.suppressKey) private var suppressRemovalNotice = false
    @AppStorage(CollectionAddNotice.autoAddKey) private var autoAddToCollection = false

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Name", value: model.libraryName)
                LabeledContent("Location") {
                    HStack {
                        Text(model.library?.root.path(percentEncoded: false) ?? "—")
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Show in Finder") {
                            if let root = model.library?.root {
                                NSWorkspace.shared.activateFileViewerSelecting([root])
                            }
                        }
                    }
                }
                Toggle("Let Spotlight index the library", isOn: Binding(
                    get: { !model.libraryHiddenFromSpotlight },
                    set: { model.setSpotlightIndexing($0) }))
                Text(model.libraryHiddenFromSpotlight
                     ? "Hidden: the library folder ends in “.noindex”, so Spotlight skips its file names, image details and the text in pictures."
                     : "Searchable: Spotlight can find library files by name, image details and the text in pictures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Private library", isOn: Binding(
                    get: { model.libraryIsPrivate },
                    set: { on in Task { await model.setPrivate(on) } }))
                    .disabled(model.library == nil)
                Text("Opening a private library asks for Touch ID or your Mac's password, and it's never listed in Open Recent. Turning this off asks too. It locks ShowTools' door only: the photos are still ordinary files to anyone using this Mac account. To lock the files themselves, keep the library in an encrypted disk image (Disk Utility can make one).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Collections") {
                Toggle("Add files to the collection automatically", isOn: $autoAddToCollection)
                Text("When a file that isn't in a show's collection goes into the show, add it to the collection without asking. Off: ShowTools asks first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Alerts") {
                Toggle("Explain what removing a slide does", isOn: Binding(
                    get: { !suppressRemovalNotice },
                    set: { suppressRemovalNotice = !$0 }))
                Text("The notice that a slide removed from a show isn't moved to the Trash.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Developer-only: lets a script open a show and start the player without
/// clicking, so the app can be checked from the command line. Inert unless
/// the environment variable is set.
///
///   SHOWTOOLS_DEV_PLAY="<showID>:<slideIndex>[:full]"
///   SHOWTOOLS_DEV_SHOW="<showID>[:<slideIndex>]"   select a show (and a slide)
@MainActor
enum DevHooks {
    static func run(_ model: AppModel) {
        if let spec = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_SHOW"] {
            let parts = spec.split(separator: ":")
            if let id = parts.first.flatMap({ Int64($0) }), let show = model.show(id) {
                model.sidebar = .show(id)
                if parts.count > 1, let i = Int(parts[1]), show.slides.indices.contains(i) {
                    model.devSelection = show.slides[i].id
                }
            }
        }
        guard let spec = ProcessInfo.processInfo.environment["SHOWTOOLS_DEV_PLAY"] else { return }
        let parts = spec.split(separator: ":")
        guard let id = parts.first.flatMap({ Int64($0) }), let show = model.show(id) else { return }
        model.sidebar = .show(id)
        let index = parts.count > 1 ? Int(parts[1]) : nil
        Player.open(show: show, model: model, fullScreen: parts.contains("full"), startAt: index)
    }
}
