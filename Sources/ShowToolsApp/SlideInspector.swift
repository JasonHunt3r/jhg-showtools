import SwiftUI
import ShowToolsCore

/// Per-slide settings for the selected slide(s). Each control can be left
/// on "Show default"; editing several slides writes the value to all of them.
struct SlideInspector: View {
    let show: Show
    let selection: Set<Int64>
    let mutate: ((inout Show) -> Void) -> Void
    @Environment(AppModel.self) private var model

    private var selected: [Slide] { show.slides.filter { selection.contains($0.id) } }

    private func edit(_ change: @escaping (inout SlideSettings) -> Void) {
        mutate { s in
            for i in s.slides.indices where selection.contains(s.slides[i].id) {
                change(&s.slides[i].settings)
            }
        }
    }

    /// True when the selected slides don't agree on a value.
    private func mixed<T: Equatable>(_ key: (SlideSettings) -> T) -> Bool {
        guard let first = selected.first.map({ key($0.settings) }) else { return false }
        return selected.contains { key($0.settings) != first }
    }

    var body: some View {
        if let first = selected.first {
            Form {
                Section {
                    if selected.count == 1, let item = model.itemsByID[first.itemID] {
                        ThumbnailView(item: item, url: model.url(for: item))
                            .aspectRatio(16 / 10, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        LabeledContent("File", value: item.fileName)
                        LabeledContent("Size", value: "\(item.pixelWidth) × \(item.pixelHeight)")
                    } else {
                        Text("\(selected.count) slides selected").font(.headline)
                        Text("Changes apply to all of them.").foregroundStyle(.secondary)
                    }
                }

                lengthSection(first)
                transitionSection(first)
                kenBurnsSection(first)
                fitSection(first)
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No slide selected", systemImage: "cursorarrow.click",
                                   description: Text("Select a slide to set its length, transition and Ken Burns."))
        }
    }

    // MARK: Sections

    private enum LengthMode: Hashable { case inherit, seconds, clip }

    private func lengthSection(_ first: Slide) -> some View {
        let s = first.settings
        let mode: LengthMode = switch s.length {
        case nil: .inherit
        case .seconds: .seconds
        case .clip: .clip
        }
        let hasClip = selected.allSatisfy { model.itemsByID[$0.itemID]?.kind != .image }
        return Section {
            Picker("Length", selection: Binding(get: { mode }, set: { m in
                edit {
                    switch m {
                    case .inherit: $0.length = nil
                    case .seconds: $0.length = .seconds(show.defaults.length)
                    case .clip: $0.length = .clip
                    }
                }
            })) {
                Text("Show default (\(formatSeconds(show.defaults.length)))").tag(LengthMode.inherit)
                Text("Custom").tag(LengthMode.seconds)
                if hasClip || mode == .clip { Text("Clip length").tag(LengthMode.clip) }
            }
            if case .seconds(let v) = s.length {
                LabeledContent("Seconds") {
                    SecondsField(value: v) { new in edit { $0.length = .seconds(new) } }
                }
            }
        } footer: { mixedNote(mixed { $0.length }) }
    }

    private func transitionSection(_ first: Slide) -> some View {
        let t = first.settings.transition
        return Section {
            Picker("Transition in", selection: Binding(get: { t != nil }, set: { custom in
                edit { $0.transition = custom ? show.defaults.transition : nil }
            })) {
                Text("Show default (\(show.defaults.transition.style.title))").tag(false)
                Text("Custom").tag(true)
            }
            if let t {
                LabeledContent("Style") {
                    TransitionPicker(transition: t) { new in edit { $0.transition = new } }
                }
            }
        } footer: { mixedNote(mixed { $0.transition }) }
    }

    private enum KBMode: Hashable { case inherit, off, auto, custom }

    private func kenBurnsSection(_ first: Slide) -> some View {
        let mode: KBMode = switch first.settings.kenBurns {
        case nil: .inherit
        case .off: .off
        case .auto: .auto
        case .custom: .custom
        }
        let defaultTitle = show.defaults.kenBurns == .auto ? "Auto" : "Off"
        return Section {
            Picker("Ken Burns", selection: Binding(get: { mode }, set: { m in
                edit {
                    switch m {
                    case .inherit: $0.kenBurns = nil
                    case .off: $0.kenBurns = .off
                    case .auto: $0.kenBurns = .auto
                    case .custom: break
                    }
                }
            })) {
                Text("Show default (\(defaultTitle))").tag(KBMode.inherit)
                Text("Off").tag(KBMode.off)
                Text("Auto").tag(KBMode.auto)
                if mode == .custom { Text("Custom").tag(KBMode.custom) }
            }
        } footer: {
            VStack(alignment: .leading) {
                mixedNote(mixed { $0.kenBurns })
                Text("Drawing a custom start and end frame comes with the Phase 2 editor.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fitSection(_ first: Slide) -> some View {
        Section {
            Picker("Fit", selection: Binding(get: { first.settings.fit }, set: { f in edit { $0.fit = f } })) {
                Text("Show default (\(show.defaults.fit.title))").tag(Fit?.none)
                ForEach(Fit.allCases, id: \.self) { Text($0.title).tag(Fit?.some($0)) }
            }
        } footer: { mixedNote(mixed { $0.fit }) }
    }

    @ViewBuilder
    private func mixedNote(_ isMixed: Bool) -> some View {
        if isMixed && selected.count > 1 {
            Text("Mixed — the selected slides differ. Showing the first one's value.")
                .foregroundStyle(.orange)
        }
    }
}

/// The notice before slides are removed from a show. It says plainly that
/// nothing goes to the Trash, and carries AppKit's own suppression checkbox
/// so it can be turned off for good.
@MainActor
enum SlideRemovalNotice {
    static let suppressKey = "suppressSlideRemovalNotice"

    /// True to go ahead.
    static func confirm(count: Int) -> Bool {
        if UserDefaults.standard.bool(forKey: suppressKey) { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Remove this slide from the show?"
                                       : "Remove \(count) slides from the show?"
        alert.informativeText = "The image won't be moved to the Trash. It stays in your library and in any other shows that use it."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
        return ok
    }
}

// MARK: - Focus: which show the menu commands act on

struct ActiveShowKey: FocusedValueKey { typealias Value = Int64 }

extension FocusedValues {
    var activeShowID: Int64? {
        get { self[ActiveShowKey.self] }
        set { self[ActiveShowKey.self] = newValue }
    }
}
