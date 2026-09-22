import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

/// The Settings switch for stripping metadata from exported files (plan,
/// Phase 4). On by default: Jason wants privacy protected unless he says
/// otherwise.
enum ExportSettings {
    static let stripKey = "exportStripsMetadata"
    static var stripMetadata: Bool {
        UserDefaults.standard.object(forKey: stripKey) as? Bool ?? true
    }
}

/// An export's progress, then its result, for `ExportBanner`.
struct ExportStatus {
    var showName: String
    var total = 0
    var done = 0
    var finished = false
    var folder: URL?
    var notStripped: [(path: String, reason: String)] = []
    var replaced = false
}

/// File ▸ Export Show… (plan, Phase 4): a Save panel for the new folder's
/// name and place, with a "Hide from Spotlight" checkbox (on to start with
/// when the library is private). The name is Photos' ("Export Photos…",
/// ⇧⌘E); Apple's guidelines only define "Export As…", for document apps.
@MainActor
func runExportPanel(_ model: AppModel, showID: Int64) {
    guard let lib = model.library, let show = model.show(showID) else { return }
    let strip = ExportSettings.stripMetadata

    let panel = NSSavePanel()
    panel.nameFieldStringValue = SetlistExport.folderName(for: show.name)
    panel.prompt = "Export"
    panel.message = "The show's files are copied into a new folder, numbered in show order, with show.json and show.tsv to import it again."
    panel.canCreateDirectories = true
    let hide = NSButton(checkboxWithTitle: "Hide from Spotlight", target: nil, action: nil)
    hide.state = model.libraryIsPrivate ? .on : .off
    hide.toolTip = "Adds “.noindex” to the folder's name, so Spotlight doesn't index the copies."
    let note = NSTextField(labelWithString: strip
        ? "Copies have their location, camera and date removed. (Settings ▸ Export)"
        : "Copies keep their metadata: location, camera and date. (Settings ▸ Export)")
    note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    note.textColor = .secondaryLabelColor
    let stack = NSStackView(views: [hide, note])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    panel.accessoryView = stack
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let options = SetlistExport.Options(stripMetadata: strip, hideFromSpotlight: hide.state == .on,
                                        folderName: url.lastPathComponent)
    let plan: SetlistExport.Plan
    do {
        plan = try SetlistExport.plan(show, from: lib, options: options)
    } catch {
        exportAlert("“\(show.name)” can't be exported.",
                    "\(error). Use File ▸ Relink Missing Files… first.")
        return
    }
    model.exportShow(plan, into: url.deletingLastPathComponent(), options: options)
}

@MainActor
func exportAlert(_ title: String, _ detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
}

extension AppModel {
    /// Writes the export off the main thread, reporting to `exportStatus`.
    func exportShow(_ plan: SetlistExport.Plan, into parent: URL, options: SetlistExport.Options) {
        exportStatus = ExportStatus(showName: plan.manifest.name, total: plan.copies.count)
        Task {
            do {
                let result = try await SetlistExport.write(plan, into: parent, options: options,
                                                           progress: { done, total in
                    Task { @MainActor in
                        guard self.exportStatus?.finished == false else { return }
                        self.exportStatus?.done = done
                        self.exportStatus?.total = total
                    }
                })
                exportStatus?.done = result.fileCount
                exportStatus?.finished = true
                exportStatus?.folder = result.folder
                exportStatus?.notStripped = result.notStripped
                exportStatus?.replaced = result.replaced
            } catch {
                exportStatus = nil
                exportAlert("“\(plan.manifest.name)” wasn't exported.", "\(error).")
            }
        }
    }
}

/// Export progress, then a summary that stays until dismissed.
struct ExportBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.exportStatus {
            HStack(spacing: 12) {
                if s.finished {
                    Image(systemName: s.notStripped.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(s.notStripped.isEmpty ? .green : .orange)
                    Text(summary(s))
                    if !s.notStripped.isEmpty {
                        Menu("Details") {
                            ForEach(Array(s.notStripped.enumerated()), id: \.offset) { _, f in
                                Text("\(f.path): \(f.reason)")
                            }
                        }
                        .fixedSize()
                    }
                    if let folder = s.folder {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    Button("Done") { model.exportStatus = nil }
                } else {
                    ProgressView(value: Double(s.done), total: Double(max(s.total, 1)))
                        .frame(width: 160)
                    Text("Exporting “\(s.showName)”: \(s.done) of \(s.total)…")
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.bottom, 14)
        }
    }

    private func summary(_ s: ExportStatus) -> String {
        var text = "Exported “\(s.showName)” — \(s.total) file\(s.total == 1 ? "" : "s")"
        if s.replaced { text += ", replacing the earlier export" }
        if !s.notStripped.isEmpty {
            text += " · \(s.notStripped.count) kept \(s.notStripped.count == 1 ? "its" : "their") metadata"
        }
        return text
    }
}
