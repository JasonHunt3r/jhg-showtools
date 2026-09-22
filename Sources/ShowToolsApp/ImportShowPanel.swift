import SwiftUI
import ShowToolsCore

/// File ▸ Import Show… (plan, Phase 4): a folder exported by Export Show…,
/// or any folder of pictures, becomes a new show named after the folder. It
/// goes into the collection the sidebar is in, or, with "Make a collection
/// for it", into a new collection of the same name.
@MainActor
func runImportShowPanel(_ model: AppModel) {
    guard model.library != nil else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Import Show"
    panel.message = "Choose a folder made by Export Show…, or any folder of pictures."

    let current = model.currentCollectionID.flatMap { model.collection($0) }
    let box = NSButton(checkboxWithTitle: "Make a collection for it", target: nil, action: nil)
    box.toolTip = "Puts the show and its files into a new collection named after the folder."
    if current == nil { box.state = .on; box.isEnabled = false }
    let note = NSTextField(labelWithString: current.map { "Otherwise the show goes into “\($0.name)”." }
                           ?? "There's no collection yet, so one is made.")
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .secondaryLabelColor
    let stack = NSStackView(views: [box, note])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    panel.accessoryView = stack
    panel.isAccessoryViewDisclosed = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let makeCollection = box.state == .on
    Task { await model.importShow(from: url, makeCollection: makeCollection) }
}
