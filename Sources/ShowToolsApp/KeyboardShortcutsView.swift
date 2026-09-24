import SwiftUI

/// Help ▸ Keyboard Shortcuts (F3, batch 5): a plain list of the single-key
/// commands, which have no menu shortcut to show themselves (they're bare
/// keys — `SingleKeys`, not `.keyboardShortcut`, so typing still works in a
/// text field; audit M4). Everything with a real modifier already shows its
/// own shortcut in its menu, so it isn't repeated here.
struct KeyboardShortcutsView: View {
    struct Section: Identifiable {
        let title: String
        let rows: [(key: String, does: String)]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Playback", rows: [
            ("Space", "Play and pause"),
            ("J", "Shuttle backward"),
            ("K", "Stop shuttling"),
            ("L", "Shuttle forward"),
        ]),
        Section(title: "The timeline", rows: [
            ("M", "Add a marker at the playhead"),
            ("I", "Set the range's in point"),
            ("O", "Set the range's out point"),
            ("N", "Toggle snapping"),
        ]),
        Section(title: "The browser (Edit Show)", rows: [
            ("E", "Append the selection to the show"),
            ("W", "Insert at the playhead"),
            ("Q", "Place in the images row at the playhead"),
        ]),
        Section(title: "Selecting", rows: [
            ("Click", "Select just this"),
            ("⌘-click", "Add to or remove from the selection"),
            ("⇧-click", "Select the range from the last click"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(Self.sections) { section in
                SwiftUI.Section(section.title) {
                    ForEach(section.rows, id: \.key) { row in
                        HStack {
                            Text(row.key).font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .leading)
                            Text(row.does).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .frame(minWidth: 420, minHeight: 480)
    }
}
