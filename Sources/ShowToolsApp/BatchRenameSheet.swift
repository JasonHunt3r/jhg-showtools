import SwiftUI
import ShowToolsCore

/// `.sheet(item:)` needs an `Identifiable`; `[Int64]` isn't one, so this
/// just carries it across.
struct IdentifiedIDs: Identifiable {
    let ids: [Int64]
    var id: [Int64] { ids }
}

/// Finder's *Rename Items* sheet (plan, 2b): Replace Text, Add Text and
/// Format, with a live preview before anything on disk changes.
struct BatchRenameSheet: View {
    /// In grid order, so the preview lists them the way they were selected.
    let itemIDs: [Int64]
    /// Passed in rather than read from this view's own environment: a
    /// `.sheet` is a separate window, whose `\.undoManager` isn't
    /// necessarily the presenting window's (confirmed by hand — a rename's
    /// undo silently went nowhere until this was explicit).
    let undoManager: UndoManager?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum ModeCase: String, CaseIterable { case replace = "Replace Text", add = "Add Text", format = "Format" }
    @State private var modeCase: ModeCase = .format
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var addText = ""
    @State private var addPosition: BatchRename.Mode.Position = .after
    @State private var formatName = "Untitled"
    @State private var formatCounter: BatchRename.Mode.Counter = .index
    @State private var formatStart = 1

    private var items: [MediaItem] { itemIDs.compactMap { model.itemsByID[$0] } }

    private var mode: BatchRename.Mode {
        switch modeCase {
        case .replace: .replaceText(find: findText, with: replaceText)
        case .add: .addText(addText, addPosition)
        case .format: .format(name: formatName, counter: formatCounter, start: max(formatStart, 0))
        }
    }

    private var newNames: [String] { BatchRename.apply(mode, to: items.map(\.fileName)) }

    private var canRename: Bool {
        !newNames.contains { $0.isEmpty } && !(modeCase == .format && formatName.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(itemIDs.count == 1 ? "Rename 1 Item" : "Rename \(itemIDs.count) Items")
                .font(.headline)

            Picker("Mode", selection: $modeCase) {
                ForEach(ModeCase.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                switch modeCase {
                case .replace:
                    TextField("Find", text: $findText)
                    TextField("Replace with", text: $replaceText)
                case .add:
                    TextField("Text", text: $addText)
                    Picker("Where", selection: $addPosition) {
                        Text("Before name").tag(BatchRename.Mode.Position.before)
                        Text("After name").tag(BatchRename.Mode.Position.after)
                    }
                case .format:
                    TextField("Name", text: $formatName)
                    Picker("Numbered by", selection: $formatCounter) {
                        Text("Index (1, 2, 3…)").tag(BatchRename.Mode.Counter.index)
                        Text("Counter (01, 02…)").tag(BatchRename.Mode.Counter.counter)
                        Text("Date").tag(BatchRename.Mode.Counter.date)
                    }
                    Stepper("Starting at \(formatStart)", value: $formatStart, in: 0...9999)
                }
            }
            .formStyle(.grouped)
            .frame(height: modeCase == .format ? 150 : 100)

            Text("Preview").font(.subheadline).foregroundStyle(.secondary)
            List(Array(zip(items, newNames)), id: \.0.id) { item, newName in
                HStack(spacing: 6) {
                    Text(item.fileName).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.caption2)
                    Text(newName).lineLimit(1)
                }
            }
            .frame(minHeight: 100, maxHeight: 220)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    model.renameItems(Dictionary(uniqueKeysWithValues: zip(itemIDs, newNames)), undo: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRename)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
