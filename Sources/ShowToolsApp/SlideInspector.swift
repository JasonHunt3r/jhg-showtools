import SwiftUI
import ShowToolsCore

/// Per-slide settings for the selected slide(s). Each control can be left
/// on "Show default"; editing several slides writes the value to all of them.
struct SlideInspector: View {
    let show: Show
    let timeline: ShowTimeline
    let selection: Set<Int64>
    let mutate: ShowMutator
    /// Edit Show's inspector column gets a bar like the collection list's,
    /// with a close button; Edit Slides' system inspector has its toolbar
    /// toggle instead.
    var close: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    private var selected: [Slide] { show.slides.filter { selection.contains($0.id) } }

    private func edit(_ action: String, _ change: @escaping (inout SlideSettings) -> Void) {
        mutate(action) { s in
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
        if let close {
            VStack(spacing: 0) {
                bar(close)
                Divider()
                content
            }
        } else {
            content
        }
    }

    // MARK: The bar

    /// Final Cut's inspector header: what's selected and how long it is.
    /// The close button sits where the collection list's open arrow was
    /// before the list moved over, so the pointer is already on it.
    private func bar(_ close: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            Text(barTitle)
                .fontWeight(.semibold)
                .lineLimit(1).truncationMode(.middle)
            if let length = barLength {
                Text(formatSeconds(length)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Close the inspector (⌥⌘I)")
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var barTitle: String {
        switch selected.count {
        case 0: "Inspector"
        case 1: model.itemsByID[selected[0].itemID]?.fileName ?? "Slide"
        default: "\(selected.count) slides"
        }
    }

    /// The selected slides' total length.
    private var barLength: Double? {
        let lengths = timeline.slides.filter { selection.contains($0.slide.id) }.map(\.length)
        return lengths.isEmpty ? nil : lengths.reduce(0, +)
    }

    @ViewBuilder private var content: some View {
        if let first = selected.first {
            // Not a Form: pinned section headers (Transform, Effects) need a
            // LazyVStack in a ScrollView, which is where SwiftUI supports
            // sticking a header to the top while its section scrolls under it.
            // `card` reproduces the grouped-form look each section lost.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        card {
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
                            // The file's rating, the same in every show that uses it.
                            LabeledContent("Rating") {
                                StarRating(rating: model.itemsByID[first.itemID]?.rating ?? 0) { r in
                                    model.setRating(r, for: Set(selected.map(\.itemID)), undo: undoManager)
                                }
                            }
                        }
                    }

                    // The slide itself: where it sits and for how long. Then its
                    // effects: everything that changes the picture over time,
                    // with a timeline of when (Jason, 2026-09-21).
                    transformSection(first)
                    lengthSection(first)
                    if let r = timeline.slides.first(where: { $0.slide.id == first.id }) {
                        Section {
                            card { EffectsTimeline(slide: r, timeline: timeline) }
                        } header: {
                            header("Effects")
                        } footer: {
                            if selected.count > 1 {
                                Text("Showing the first selected slide.").padding(.horizontal, 16)
                            }
                        }
                    }
                    transitionSection(first)
                    kenBurnsSection(first)
                    rotationSection(first)
                }
                .padding(.vertical, 12)
            }
        } else {
            ContentUnavailableView("No slide selected", systemImage: "cursorarrow.click",
                                   description: Text("Select a slide to set its length, transition and Ken Burns."))
        }
    }

    /// A pinned section header: darker than the column, the same "sunken"
    /// colour the storyline's lane uses. It sticks to the top of the
    /// scroll view while its section's content scrolls under it, then the
    /// next header pushes it off (`pinnedViews: [.sectionHeaders]` above).
    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// A section's fields, in the rounded card a Form's `.grouped` style
    /// used to give them for free.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 16)
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
            card {
            Picker("Length", selection: Binding(get: { mode }, set: { m in
                edit("Change Length") {
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
                    SecondsField(value: v) { new in edit("Change Length") { $0.length = .seconds(new) } }
                }
            }
            }
        } footer: { mixedNote(mixed { $0.length }).padding(.horizontal, 16) }
    }

    private func transitionSection(_ first: Slide) -> some View {
        let t = first.settings.transition
        return Section {
            card {
            Picker("Transition in", selection: Binding(get: { t != nil }, set: { custom in
                edit("Change Transition") { $0.transition = custom ? show.defaults.transition : nil }
            })) {
                Text("Show default (\(show.defaults.transition.style.title))").tag(false)
                Text("Custom").tag(true)
            }
            if let t {
                LabeledContent("Style") {
                    TransitionPicker(transition: t) { new in edit("Change Transition") { $0.transition = new } }
                }
            }
            }
        } footer: { mixedNote(mixed { $0.transition }).padding(.horizontal, 16) }
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
            card {
            Picker("Ken Burns", selection: Binding(get: { mode }, set: { m in
                let seed = customStart(for: first)
                edit("Change Ken Burns") {
                    switch m {
                    case .inherit: $0.kenBurns = nil
                    case .off: $0.kenBurns = .off
                    case .auto: $0.kenBurns = .auto
                    case .custom: $0.kenBurns = .custom(seed)
                    }
                }
            })) {
                Text("Show default (\(defaultTitle))").tag(KBMode.inherit)
                Text("Off").tag(KBMode.off)
                Text("Auto").tag(KBMode.auto)
                Text("Custom").tag(KBMode.custom)
            }
            if case .custom(let kb) = first.settings.kenBurns, let item = model.itemsByID[first.itemID] {
                KenBurnsEditor(item: item, url: model.url(for: item),
                               fit: first.settings.fit ?? show.defaults.fit, kb: kb) { new in
                    edit("Edit Ken Burns") { $0.kenBurns = .custom(new) }
                }
                AccelerationSlider(value: kb.acceleration) { a in
                    editKenBurns("Change Acceleration") { $0.acceleration = a }
                }
                Toggle("Freeze on transition", isOn: Binding(get: { kb.freezeOnTransition }, set: { on in
                    editKenBurns("Change Freeze on Transition") { $0.freezeOnTransition = on }
                }))
                .help("Hold the start frame through the transition in and the end frame through the transition out")
            }
            }
        } footer: { mixedNote(mixed { $0.kenBurns }).padding(.horizontal, 16) }
    }

    /// Changes one field of each selected slide's custom move, leaving the
    /// rest of each move as it is.
    private func editKenBurns(_ action: String, _ change: @escaping (inout KenBurns) -> Void) {
        edit(action) { s in
            if case .custom(var k) = s.kenBurns {
                change(&k)
                s.kenBurns = .custom(k)
            }
        }
    }

    /// Custom starts from whatever the slide does now, so switching to it
    /// never jumps: an Auto move is kept, Off becomes a gentle push in.
    private func customStart(for slide: Slide) -> KenBurns {
        if let r = timeline.slides.first(where: { $0.slide.id == slide.id }), let kb = r.kenBurns {
            return kb
        }
        return KenBurns(start: .centred, end: KenBurnsFrame(x: 0.5, y: 0.5, zoom: 1.25))
    }

    /// Fit plus the still placement on top of it: where the image starts
    /// before anything moves it.
    private func transformSection(_ first: Slide) -> some View {
        let t = first.settings.transform ?? .identity
        func editTransform(_ action: String, _ change: @escaping (inout Transform) -> Void) {
            edit(action) { s in
                var x = s.transform ?? .identity
                change(&x)
                s.transform = x == .identity ? nil : x
            }
        }
        return Section {
            card {
            Picker("Fit", selection: Binding(get: { first.settings.fit }, set: { f in edit("Change Fit") { $0.fit = f } })) {
                Text("Show default (\(show.defaults.fit.title))").tag(Fit?.none)
                ForEach(Fit.allCases, id: \.self) { Text($0.title).tag(Fit?.some($0)) }
            }
            CommitSlider(title: "Position X", value: t.offsetX, range: -1...1, display: 100, unit: "%") { v in
                editTransform("Move") { $0.offsetX = v }
            }
            CommitSlider(title: "Position Y", value: t.offsetY, range: -1...1, display: 100, unit: "%") { v in
                editTransform("Move") { $0.offsetY = v }
            }
            CommitSlider(title: "Zoom", value: t.scale, range: 0.1...4, display: 100, unit: "%",
                         fieldRange: 0.01...20) { v in
                editTransform("Zoom") { $0.scale = v }
            }
            CommitSlider(title: "Rotation", value: t.rotation, range: -180...180, unit: "°",
                         fieldRange: -3600...3600) { v in
                editTransform("Rotate") { $0.rotation = v }
            }
            LabeledContent("Background") {
                HStack(spacing: 8) {
                    if first.settings.background != nil {
                        Button("Use show's") { edit("Change Background") { $0.background = nil } }
                            .buttonStyle(.link)
                            .fixedSize()
                    }
                    SettledColorPicker(title: "Background", colour: first.settings.background ?? show.defaults.background) { c in
                        edit("Change Background") { $0.background = c }
                    }
                    .labelsHidden()
                }
            }
            HStack {
                Spacer()
                Button("Reset Transform") { edit("Reset Transform") { $0.transform = nil } }
                    .disabled(first.settings.transform == nil)
            }
            if let r = timeline.slides.first(where: { $0.slide.id == first.id }) {
                let m = r.peakMagnification(outputSize: outputPixelSize)
                if m > ResolvedSlide.softAbove {
                    Label {
                        Text("Soft at this zoom: at its closest it's shown at \(String(format: "%.1f", m))× the file's own pixels on this screen.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.caption)
                }
            }
            }
        } header: {
            header("Transform")
        } footer: {
            mixedNote(mixed { $0.fit } || mixed { $0.transform } || mixed { $0.background }).padding(.horizontal, 16)
        }
    }

    /// Rotation's own section: a checkbox, then Angles or Speed, acceleration,
    /// the pivot pads, and freeze. Turning it off keeps its settings.
    private func rotationSection(_ first: Slide) -> some View {
        let r = first.settings.rotation
        let on = r?.enabled ?? false
        func editRotation(_ action: String, _ change: @escaping (inout Rotation) -> Void) {
            edit(action) { s in
                var x = s.rotation ?? Rotation()
                change(&x)
                s.rotation = x
            }
        }
        return Section {
            card {
            Toggle("Rotation", isOn: Binding(get: { on }, set: { v in
                editRotation(v ? "Turn On Rotation" : "Turn Off Rotation") { $0.enabled = v }
            }))
            if let r, r.enabled {
                Picker("Mode", selection: Binding(get: { r.mode }, set: { m in
                    editRotation("Change Rotation Mode") { $0.mode = m }
                })) {
                    Text("Angles").tag(Rotation.Mode.angles)
                    Text("Speed").tag(Rotation.Mode.speed)
                }
                .pickerStyle(.segmented)

                CommitSlider(title: "Start angle", value: r.startAngle, range: -360...360, unit: "°",
                             fieldRange: -36000...36000) { v in
                    editRotation("Change Start Angle") { $0.startAngle = v }
                }
                switch r.mode {
                case .angles:
                    CommitSlider(title: "End angle", value: r.endAngle, range: -360...360, unit: "°",
                                 fieldRange: -36000...36000) { v in
                        editRotation("Change End Angle") { $0.endAngle = v }
                    }
                case .speed:
                    CommitSlider(title: "Speed", value: r.speed, range: -360...360, unit: "°/s",
                                 fieldRange: -3600...3600) { v in
                        editRotation("Change Speed") { $0.speed = v }
                    }
                }
                if let note = rotationNote(first, r) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }

                AccelerationSlider(value: r.acceleration) { a in
                    editRotation("Change Acceleration") { $0.acceleration = a }
                }

                if let item = model.itemsByID[first.itemID] {
                    let size = CGSize(width: item.pixelWidth, height: item.pixelHeight)
                    HStack(alignment: .top, spacing: 16) {
                        Spacer(minLength: 0)
                        PolarPad(title: r.pivotLocked ? "Pivot" : "Start pivot", point: r.pivotStart,
                                 imageSize: size) { p in
                            editRotation("Move Pivot") { $0.pivotStart = p }
                        }
                        if !r.pivotLocked {
                            PolarPad(title: "End pivot", point: r.pivotEnd, imageSize: size) { p in
                                editRotation("Move Pivot") { $0.pivotEnd = p }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Toggle("Lock start and end pivot", isOn: Binding(get: { r.pivotLocked }, set: { v in
                        // Unlocking starts the end pivot where the start is, so nothing jumps.
                        editRotation(v ? "Lock Pivot" : "Unlock Pivot") { x in
                            x.pivotLocked = v
                            if !v { x.pivotEnd = x.pivotStart }
                        }
                    }))
                }

                Toggle("Freeze on transition", isOn: Binding(get: { r.freezeOnTransition }, set: { v in
                    editRotation("Change Freeze on Transition") { $0.freezeOnTransition = v }
                }))
                .help("Hold the start angle through the transition in and the end angle through the transition out")
            }
            }
        } footer: { mixedNote(mixed { $0.rotation }).padding(.horizontal, 16) }
    }

    /// The other half of the numbers: the speed that Angles gives, or the
    /// angle that Speed ends on, over the time this slide actually turns.
    private func rotationNote(_ slide: Slide, _ r: Rotation) -> String? {
        guard let rs = timeline.slides.first(where: { $0.slide.id == slide.id }) else { return nil }
        // Frozen, it turns only while on screen alone.
        let span = rs.motionSpan(frozen: r.freezeOnTransition)
        guard span > 0 else { return nil }
        let secs = formatSeconds(span)
        switch r.mode {
        case .angles:
            let speed = (r.endAngle - r.startAngle) / span
            return "About \(String(format: "%.1f", speed))°/s over \(secs)."
        case .speed:
            return "Ends at \(String(format: "%.1f", r.startAngle + r.sweep(span: span)))° after \(secs). Trimming the slide changes this."
        }
    }

    @ViewBuilder
    private func mixedNote(_ isMixed: Bool) -> some View {
        if isMixed && selected.count > 1 {
            Text("Mixed — the selected slides differ. Showing the first one's value.")
                .foregroundStyle(.orange)
        }
    }
}

/// Five stars: click one to rate, click the current rating's star again to
/// clear it. Hovering shows what a click would set.
struct StarRating: View {
    let rating: Int
    let set: (Int) -> Void
    @State private var hover: Int?

    var body: some View {
        let shown = hover ?? rating
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= shown ? "star.fill" : "star")
                    .foregroundStyle(n <= shown ? Color.yellow : Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onHover { inside in hover = inside ? n : (hover == n ? nil : hover) }
                    .onTapGesture { set(n == rating ? 0 : n) }
            }
        }
        .help(rating == 0 ? "Not rated. Click a star to rate."
                          : "\(rating) star\(rating == 1 ? "" : "s"). Click the last star again to clear.")
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
