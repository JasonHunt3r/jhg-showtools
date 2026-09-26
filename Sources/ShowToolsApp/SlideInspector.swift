import SwiftUI
import ShowToolsCore
import ShowToolsPlayback

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
    /// Only Edit Show has a preview to draw into, so only it passes an
    /// engine; without one the sliders behave as they always did and show
    /// their value on release.
    var engine: PlaybackEngine? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    /// Replace Image… (item 8, work order): only offered for one slide.
    @State private var replacingImage = false

    private var selected: [Slide] { show.slides.filter { selection.contains($0.id) } }

    private func edit(_ action: String, _ change: @escaping (inout SlideSettings) -> Void) {
        mutate(action) { s in
            for i in s.slides.indices where selection.contains(s.slides[i].id) {
                change(&s.slides[i].settings)
            }
        }
        // The saved show takes over from anything a drag was drawing.
        engine?.endLiveEdit()
    }

    /// The same change as `edit`, drawn in the preview but never saved.
    ///
    /// A slider drag calls this as the knob moves and `edit` once on
    /// release, so the picture follows the drag while the history still
    /// gets a single undo step. `showLiveEdit` is the seam the preview's
    /// own drag handles already use.
    private func previewEdit(_ change: (inout SlideSettings) -> Void) {
        guard let engine else { return }
        var s = show
        for i in s.slides.indices where selection.contains(s.slides[i].id) {
            change(&s.slides[i].settings)
        }
        engine.showLiveEdit(s)
    }

    /// True when the selected slides don't agree on a value.
    private func mixed<T: Equatable>(_ key: (SlideSettings) -> T) -> Bool {
        guard let first = selected.first.map({ key($0.settings) }) else { return false }
        return selected.contains { key($0.settings) != first }
    }

    /// Aligned to the top (item 14): the bar sits at the top of the column
    /// whatever's under it. With nothing selected there's nothing under it,
    /// and the message is an overlay centred on the whole pane.
    var body: some View {
        ZStack(alignment: .top) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay { if selected.isEmpty { emptyMessage } }
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
        // The whole bar, not just its text and icons: a right-click on its
        // empty stretch opened nothing (Jason, 2026-09-26).
        .contentShape(Rectangle())
        // Settled 2026-09-24 (`spec/conventions.md` §3, item 6).
        .contextMenu {
            Button("Play from Here") { playFromHere() }
            if let itemID = selected.first?.itemID {
                Button("Show in Library") { showInLibrary(itemID, model: model, undoManager: undoManager) }
                if selected.count == 1 { Button("Replace Image…") { replacingImage = true } }
            }
        }
        .sheet(isPresented: $replacingImage) {
            if let slide = selected.first {
                ReplaceImagePicker(show: show, currentItemID: slide.itemID) { newItemID in
                    SlideActions.replaceImage(slide.id, with: newItemID, mutate: mutate)
                }
            }
        }
    }

    /// Uses the live engine if there is one (Edit Show); otherwise opens a
    /// player window at the slide, as Edit Slides' own Play from Here does.
    private func playFromHere() {
        guard let id = selected.first?.id else { return }
        if let engine {
            engine.seek(timeline.slides.first { $0.slide.id == id }?.start ?? 0)
            engine.play()
        } else {
            Player.open(show: show, model: model, fullScreen: false, startAt: show.slides.firstIndex { $0.id == id })
        }
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
                        card("File") {
                            if selected.count == 1, let item = model.itemsByID[first.itemID] {
                                ThumbnailView(item: item, url: model.url(for: item))
                                    .aspectRatio(16 / 10, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    // A video slide's sound, over the preview
                                    // itself (Jason, 2026-09-22): the same line
                                    // as the storyline's, with the picture
                                    // behind it to aim by.
                                    .overlay(alignment: .bottom) { previewVolume(first, item) }
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
                    soundSection(first)
                    if let r = timeline.slides.first(where: { $0.slide.id == first.id }) {
                        Section {
                            card("Effects") {
                                EffectsTimeline(slide: r, timeline: timeline,
                                                commitAudio: r.item.kind == .video
                                                    ? { curve, action in editAudio(action) { _ in curve } }
                                                    : nil)
                            }
                        } header: {
                            header("Effects")
                                .noMenuYet("Show › Inspector › Effects section header",
                                           planned: "Reset Section to Show Default, Copy/Paste Section Settings")
                        } footer: {
                            if selected.count > 1 {
                                Text("Showing the first selected slide.").padding(.horizontal, 16)
                            }
                        }
                    }
                    transitionSection(first)
                    panAndZoomSection(first)
                    rotationSection(first)
                }
                .padding(.vertical, 12)
            }
        }
    }

    /// Shown centred on the whole pane when nothing's selected (`body`'s
    /// overlay), not stacked under the bar.
    private var emptyMessage: some View {
        ContentUnavailableView("No slide selected", systemImage: "cursorarrow.click",
                               description: Text("Select a slide to set its length, transition and Pan and Zoom."))
            .noMenuYet("Show › Inspector › empty (no slide selected)")
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
    /// used to give them for free. Right-clicked, it names itself
    /// (`noMenuYet`): the settled per-control Reset to Default isn't built.
    private func card<Content: View>(_ section: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .noMenuYet("Show › Inspector › \(section) section", planned: "a single control: Reset to Default")
        .padding(.horizontal, 16)
    }

    // MARK: Sections

    private enum LengthMode: Hashable { case inherit, seconds, clip }

    /// The level line along the bottom of the inspector's preview.
    @ViewBuilder
    private func previewVolume(_ first: Slide, _ item: MediaItem) -> some View {
        if item.kind == .video,
           let r = timeline.slides.first(where: { $0.slide.id == first.id }) {
            GeometryReader { g in
                CurveLine(curve: r.audio, length: max(r.length, 0.001),
                          pps: Double(g.size.width) / max(r.length, 0.001),
                          width: g.size.width, height: Self.previewVolumeHeight,
                          colour: .orange, name: "Volume",
                          begin: {},
                          commit: { curve, action in editAudio(action) { _ in curve } })
            }
            .frame(height: Self.previewVolumeHeight)
            .background(.black.opacity(0.22))
        }
    }

    static let previewVolumeHeight: CGFloat = 54

    // MARK: Sound

    /// A video slide's own sound (spec/video-audio.md), mirroring the level
    /// line on its block: one volume while the line is flat, and the points
    /// themselves once it's been shaped. Only the first selected slide, as
    /// the Effects timeline does — the points belong to one clip.
    @ViewBuilder
    private func soundSection(_ first: Slide) -> some View {
        if let resolved = timeline.slides.first(where: { $0.slide.id == first.id }),
           resolved.item.kind == .video {
            let curve = first.settings.audio ?? LevelCurve()
            let levels = Set(curve.points.map { Int(($0.level * 100).rounded()) })
            let shaped = levels.count > 1
            Section {
                card("Sound") {
                    VStack(alignment: .leading, spacing: 8) {
                        if shaped {
                            ForEach(curve.points) { point in
                                pointRow(point, curve: curve, length: resolved.length)
                            }
                            Button("Add Point") {
                                editAudio("Add Volume Point") {
                                    $0.addingOnLine(at: (resolved.length / 2 * 10).rounded() / 10)
                                }
                            }
                            .controlSize(.small)
                        } else {
                            CommitSlider(title: "Volume", value: curve.points.first?.level ?? 0,
                                         range: 0...1, display: 100, unit: "%") { v in
                                setFlatVolume(v, length: resolved.length)
                            }
                            Text(curve.isEmpty
                                 ? "Silent. Turn it up here, or drag the line along the slide."
                                 : "⌥-click the line along the slide to shape it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                header("Sound").contextMenu { soundSectionMenu(first) }
            } footer: {
                if selected.count > 1 {
                    Text("Showing the first selected slide.").padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder private func soundSectionMenu(_ first: Slide) -> some View {
        Button("Reset Section to Show Default") { edit("Reset Section to Show Default") { $0.audio = nil } }
        Divider()
        Button("Copy Section Settings") {
            SectionClipboard.copy(first.settings.audio ?? LevelCurve(), key: "sound")
        }
        Button("Paste Section Settings") {
            guard let v = SectionClipboard.paste(LevelCurve.self, key: "sound") else { return }
            edit("Paste Section Settings") { $0.audio = v.isEmpty ? nil : v }
        }
        .disabled(!SectionClipboard.canPaste(key: "sound"))
    }

    private func pointRow(_ point: LevelPoint, curve: LevelCurve, length: Double) -> some View {
        HStack(spacing: 4) {
            TextField("", value: Binding(
                get: { point.time },
                set: { t in
                    editAudio("Move Volume Point") {
                        $0.moving(point.id, toTime: min(max(t, 0), max(length, 0)), level: point.level)
                    }
                }), format: .number.precision(.fractionLength(1)))
                .frame(width: 48)
            Text("s").foregroundStyle(.secondary)
            Spacer(minLength: 4)
            TextField("", value: Binding(
                get: { (point.level * 100).rounded() },
                set: { l in
                    editAudio("Change Volume Point") {
                        $0.moving(point.id, toTime: point.time, level: min(max(l / 100, 0), 1))
                    }
                }), format: .number.precision(.fractionLength(0)))
                .frame(width: 40)
            Text("%").foregroundStyle(.secondary)
            Button {
                editAudio("Remove Volume Point") { $0.removing(point.id) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this point")
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption.monospacedDigit())
    }

    /// One level across the whole clip. Turning it down to nothing clears
    /// the field altogether, so the slide is silent again rather than
    /// carrying a flat zero.
    private func setFlatVolume(_ v: Double, length: Double) {
        editAudio("Change Volume") { _ in
            guard v > 0 else { return LevelCurve() }
            return LevelCurve(points: [LevelPoint(time: 0, level: v),
                                       LevelPoint(time: max(length, 0), level: v)])
        }
    }

    /// Edits the first selected slide's curve, one undo step.
    private func editAudio(_ action: String, _ change: @escaping (LevelCurve) -> LevelCurve) {
        guard let first = selected.first else { return }
        mutate(action) { s in
            guard let i = s.slides.firstIndex(where: { $0.id == first.id }) else { return }
            let c = change(s.slides[i].settings.audio ?? LevelCurve())
            s.slides[i].settings.audio = c.isEmpty ? nil : c
        }
    }

    private func lengthSection(_ first: Slide) -> some View {
        let s = first.settings
        let mode: LengthMode = switch s.length {
        case nil: .inherit
        case .seconds: .seconds
        case .clip: .clip
        }
        let hasClip = selected.allSatisfy { model.itemsByID[$0.itemID]?.kind != .image }
        return Section {
            card("Length") {
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
            card("Transition") {
            Picker("Transition in", selection: Binding(get: { t != nil }, set: { custom in
                edit("Change Transition") { $0.transition = custom ? show.defaults.transition : nil }
            })) {
                Text("Show default (\(show.defaults.transition.style.title))").tag(false)
                Text("Custom").tag(true)
            }
            if let t {
                // The label is fixed so it can't be squeezed. `TransitionPicker`
                // is three controls wide, and in a card (a plain VStack, not a
                // Form) `LabeledContent` gives the content what it asks for and
                // compresses the label to nothing — which drew "Style" as a
                // column of single letters. Measured in a harness at the
                // inspector's narrowest width, 320pt, 2026-09-22.
                LabeledContent {
                    TransitionPicker(transition: t) { new in edit("Change Transition") { $0.transition = new } }
                } label: {
                    Text("Style").fixedSize()
                }
            }
            }
        } footer: { mixedNote(mixed { $0.transition }).padding(.horizontal, 16) }
    }

    private enum KBMode: Hashable { case inherit, off, auto, custom }

    private func panAndZoomSection(_ first: Slide) -> some View {
        let mode: KBMode = switch first.settings.panAndZoom {
        case nil: .inherit
        case .off: .off
        case .auto: .auto
        case .custom: .custom
        }
        let defaultTitle = show.defaults.panAndZoom == .auto ? "Auto" : "Off"
        return Section {
            card("Pan and Zoom") {
            Picker("Pan and Zoom", selection: Binding(get: { mode }, set: { m in
                let seed = customStart(for: first)
                edit("Change Pan and Zoom") {
                    switch m {
                    case .inherit: $0.panAndZoom = nil
                    case .off: $0.panAndZoom = .off
                    case .auto: $0.panAndZoom = .auto
                    case .custom: $0.panAndZoom = .custom(seed)
                    }
                }
            })) {
                Text("Show default (\(defaultTitle))").tag(KBMode.inherit)
                Text("Off").tag(KBMode.off)
                Text("Auto").tag(KBMode.auto)
                Text("Custom").tag(KBMode.custom)
            }
            if case .custom(let kb) = first.settings.panAndZoom, let item = model.itemsByID[first.itemID] {
                PanAndZoomEditor(item: item, url: model.url(for: item),
                               fit: first.settings.fit ?? show.defaults.fit, kb: kb) { new in
                    edit("Edit Pan and Zoom") { $0.panAndZoom = .custom(new) }
                }
                AccelerationSlider(value: kb.acceleration) { a in
                    editPanAndZoom("Change Acceleration") { $0.acceleration = a }
                } preview: { a in
                    previewPanAndZoom { $0.acceleration = a }
                }
                Toggle("Freeze on transition", isOn: Binding(get: { kb.freezeOnTransition }, set: { on in
                    editPanAndZoom("Change Freeze on Transition") { $0.freezeOnTransition = on }
                }))
                .help("Hold the start frame through the transition in and the end frame through the transition out")
            }
            }
        } footer: { mixedNote(mixed { $0.panAndZoom }).padding(.horizontal, 16) }
    }

    /// Changes one field of each selected slide's custom move, leaving the
    /// rest of each move as it is.
    private func editPanAndZoom(_ action: String, _ change: @escaping (inout PanAndZoom) -> Void) {
        edit(action) { s in
            if case .custom(var k) = s.panAndZoom {
                change(&k)
                s.panAndZoom = .custom(k)
            }
        }
    }

    private func previewPanAndZoom(_ change: @escaping (inout PanAndZoom) -> Void) {
        previewEdit { s in
            if case .custom(var k) = s.panAndZoom {
                change(&k)
                s.panAndZoom = .custom(k)
            }
        }
    }

    /// Custom starts from whatever the slide does now, so switching to it
    /// never jumps: an Auto move is kept, Off becomes a gentle push in.
    private func customStart(for slide: Slide) -> PanAndZoom {
        if let r = timeline.slides.first(where: { $0.slide.id == slide.id }), let kb = r.panAndZoom {
            return kb
        }
        return PanAndZoom(start: .centred, end: PanAndZoomFrame(x: 0.5, y: 0.5, zoom: 1.25))
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
        // The same change, drawn but not saved, for a slider being dragged.
        func previewTransform(_ change: @escaping (inout Transform) -> Void) {
            previewEdit { s in
                var x = s.transform ?? .identity
                change(&x)
                s.transform = x == .identity ? nil : x
            }
        }
        return Section {
            card("Transform") {
            Picker("Fit", selection: Binding(get: { first.settings.fit }, set: { f in edit("Change Fit") { $0.fit = f } })) {
                Text("Show default (\(show.defaults.fit.title))").tag(Fit?.none)
                ForEach(Fit.allCases, id: \.self) { Text($0.title).tag(Fit?.some($0)) }
            }
            CommitSlider(title: "Position X", value: t.offsetX, range: -1...1, display: 100, unit: "%") { v in
                editTransform("Move") { $0.offsetX = v }
            } preview: { v in
                previewTransform { $0.offsetX = v }
            }
            CommitSlider(title: "Position Y", value: t.offsetY, range: -1...1, display: 100, unit: "%") { v in
                editTransform("Move") { $0.offsetY = v }
            } preview: { v in
                previewTransform { $0.offsetY = v }
            }
            CommitSlider(title: "Zoom", value: t.scale, range: 0.1...4, display: 100, unit: "%",
                         fieldRange: 0.01...20) { v in
                editTransform("Zoom") { $0.scale = v }
            } preview: { v in
                previewTransform { $0.scale = v }
            }
            CommitSlider(title: "Rotation", value: t.rotation, range: -180...180, unit: "°",
                         fieldRange: -3600...3600) { v in
                editTransform("Rotate") { $0.rotation = v }
            } preview: { v in
                previewTransform { $0.rotation = v }
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
            header("Transform").contextMenu { transformSectionMenu(first) }
        } footer: {
            mixedNote(mixed { $0.fit } || mixed { $0.transform } || mixed { $0.background }).padding(.horizontal, 16)
        }
    }

    /// A section header's own menu (`spec/conventions.md` §3, item 6):
    /// Reset Section to Show Default, Copy/Paste this section's settings.
    /// Transform's section is Fit, the transform itself and the background.
    private struct TransformCopy: Codable { var fit: Fit?; var transform: Transform?; var background: SRGBColor? }

    @ViewBuilder private func transformSectionMenu(_ first: Slide) -> some View {
        Button("Reset Section to Show Default") {
            edit("Reset Section to Show Default") { s in
                s.fit = nil; s.transform = nil; s.background = nil
            }
        }
        Divider()
        Button("Copy Section Settings") {
            let s = first.settings
            SectionClipboard.copy(TransformCopy(fit: s.fit, transform: s.transform, background: s.background),
                                   key: "transform")
        }
        Button("Paste Section Settings") {
            guard let v = SectionClipboard.paste(TransformCopy.self, key: "transform") else { return }
            edit("Paste Section Settings") { s in
                s.fit = v.fit; s.transform = v.transform; s.background = v.background
            }
        }
        .disabled(!SectionClipboard.canPaste(key: "transform"))
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
        func previewRotation(_ change: @escaping (inout Rotation) -> Void) {
            previewEdit { s in
                var x = s.rotation ?? Rotation()
                change(&x)
                s.rotation = x
            }
        }
        return Section {
            card("Rotation") {
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
                } preview: { v in
                    previewRotation { $0.startAngle = v }
                }
                switch r.mode {
                case .angles:
                    CommitSlider(title: "End angle", value: r.endAngle, range: -360...360, unit: "°",
                                 fieldRange: -36000...36000) { v in
                        editRotation("Change End Angle") { $0.endAngle = v }
                    } preview: { v in
                        previewRotation { $0.endAngle = v }
                    }
                case .speed:
                    CommitSlider(title: "Speed", value: r.speed, range: -360...360, unit: "°/s",
                                 fieldRange: -3600...3600) { v in
                        editRotation("Change Speed") { $0.speed = v }
                    } preview: { v in
                        previewRotation { $0.speed = v }
                    }
                }
                if let note = rotationNote(first, r) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }

                AccelerationSlider(value: r.acceleration) { a in
                    editRotation("Change Acceleration") { $0.acceleration = a }
                } preview: { a in
                    previewRotation { $0.acceleration = a }
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

/// Reject, then five stars: click one to rate, click the current rating's
/// star (or the reject mark) again to clear it. Hovering shows what a
/// click would set.
struct StarRating: View {
    let rating: Int
    let set: (Int) -> Void
    @State private var hover: Int?

    var body: some View {
        let shown = hover ?? rating
        HStack(spacing: 2) {
            Image(systemName: shown == Rating.rejected ? "xmark.circle.fill" : "xmark.circle")
                .foregroundStyle(shown == Rating.rejected ? Color.red : Color.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onHover { inside in hover = inside ? Rating.rejected : (hover == Rating.rejected ? nil : hover) }
                .onTapGesture { set(rating == Rating.rejected ? 0 : Rating.rejected) }
                .padding(.trailing, 4)
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= shown ? "star.fill" : "star")
                    .foregroundStyle(n <= shown ? Color.yellow : Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
                    .onHover { inside in hover = inside ? n : (hover == n ? nil : hover) }
                    .onTapGesture { set(n == rating ? 0 : n) }
            }
        }
        .help(rating == 0 ? "Not rated. Click a star to rate. Keys, in the grids: 1–5, 0 clears, 9 rejects, − and = step."
              : rating == Rating.rejected ? "Rejected. Click the mark again to clear."
              : "\(rating) star\(rating == 1 ? "" : "s"). Click the last star again to clear.")
    }
}

/// A file's rating as a grid tile or browser row shows it: stars, or a
/// red ✕ for a reject. Nothing when unrated.
struct RatingBadge: View {
    let rating: Int
    var font: Font = .caption2

    var body: some View {
        if rating == Rating.rejected {
            Image(systemName: "xmark").font(font.weight(.bold)).foregroundStyle(.red)
                .help("Rejected")
        } else if rating > 0 {
            Text(String(repeating: "★", count: rating)).font(font).foregroundStyle(.yellow)
        }
    }
}

/// The grids' and the browser's rating filter (`Rating.Filter`): rejects
/// are hidden unless one of the first or last choices asks for them.
struct RatingFilterPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("Rating", selection: $selection) {
            Text("Show All").tag(Rating.Filter.showAll)
            Text("Unrated or Better").tag(Rating.Filter.unratedOrBetter)
            ForEach(1...5, id: \.self) { n in
                Text(String(repeating: "★", count: n) + (n < 5 ? " or more" : "")).tag(n)
            }
            Text("Rejected Only").tag(Rating.Filter.rejectedOnly)
        }
        .pickerStyle(.inline)
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

/// The notice before a group is deleted (plan, "Groups inside collections",
/// Jason 2026-09-24): its sub-groups go with it, as in Finder, but the
/// files always stay in the collection unless the checkbox below is on.
@MainActor
enum GroupDeleteNotice {
    static let suppressKey = "suppressGroupDeleteNotice"

    /// True to go ahead; `alsoFromLibrary` is the checkbox's state — item
    /// 16, `ShowTools Feedback — Worklist for Next CC Session.md`. Not a
    /// suppression: it's asked fresh, unchecked, every time, since it
    /// changes what the delete itself does, not whether to ask again.
    static func confirm(name: String, subgroupCount: Int) -> (delete: Bool, alsoFromLibrary: Bool) {
        if UserDefaults.standard.bool(forKey: suppressKey) { return (true, false) }
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = (subgroupCount > 0
            ? "This also deletes \(subgroupCount) group\(subgroupCount == 1 ? "" : "s") inside it. "
            : "") + "The files stay in the collection unless you check the box below. You can undo this."
        alert.addButton(withTitle: "Delete Group")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also delete the files from the library"
        let ok = alert.runModal() == .alertFirstButtonReturn
        return (ok, ok && alert.suppressionButton?.state == .on)
    }
}

/// The notice before a collection is deleted. Same shape as
/// `GroupDeleteNotice`, and the same "also delete from the library"
/// checkbox (item 16).
@MainActor
enum CollectionDeleteNotice {
    static func confirm(name: String, showCount: Int) -> (delete: Bool, alsoFromLibrary: Bool) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = (showCount > 0
            ? "Its \(showCount == 1 ? "show" : "\(showCount) shows") will be deleted too. "
            : "") + "The images stay in the library unless you check the box below. You can undo this."
        alert.addButton(withTitle: "Delete Collection")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also delete the images from the library"
        let ok = alert.runModal() == .alertFirstButtonReturn
        return (ok, ok && alert.suppressionButton?.state == .on)
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

// MARK: - Focus: the Library grid's selection, for its File-menu commands
// (Rename…, Get Info). One shared count, one action closure per command.

struct LibrarySelectionCountKey: FocusedValueKey { typealias Value = Int }
struct LibraryRenameKey: FocusedValueKey { typealias Value = () -> Void }
struct LibraryGetInfoKey: FocusedValueKey { typealias Value = () -> Void }
/// Quick Look, ⌘Y (B5): a real menu shortcut, not `SingleKeys` — unlike
/// Delete/⌘A, ⌘Y still needs to work while the Quick Look panel itself is
/// key (a different `NSWindow`, which a window-scoped `SingleKeys` monitor
/// never sees), and a menu key equivalent fires wherever the app's focus is.
struct LibraryQuickLookKey: FocusedValueKey { typealias Value = () -> Void }
/// New Collection, named before it's made (audit H1). Published by
/// `MainView` itself, not the grid: it's always available, whatever the
/// detail pane is showing.
struct NewCollectionKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var librarySelectionCount: Int? {
        get { self[LibrarySelectionCountKey.self] }
        set { self[LibrarySelectionCountKey.self] = newValue }
    }
    var requestLibraryRename: (() -> Void)? {
        get { self[LibraryRenameKey.self] }
        set { self[LibraryRenameKey.self] = newValue }
    }
    var requestLibraryGetInfo: (() -> Void)? {
        get { self[LibraryGetInfoKey.self] }
        set { self[LibraryGetInfoKey.self] = newValue }
    }
    var requestLibraryQuickLook: (() -> Void)? {
        get { self[LibraryQuickLookKey.self] }
        set { self[LibraryQuickLookKey.self] = newValue }
    }
    var requestNewCollection: (() -> Void)? {
        get { self[NewCollectionKey.self] }
        set { self[NewCollectionKey.self] = newValue }
    }
}

// MARK: - Focus: the open show's slide selection, for Edit ▸ Duplicate (A2),
// Get Info (F4) and Show ▸ Play starting at the selection (G5). Published by
// `ShowView`, which holds `selection` for both modes alike.

struct ActiveSlideSelectionKey: FocusedValueKey { typealias Value = Set<Int64> }
struct DuplicateSlidesKey: FocusedValueKey { typealias Value = () -> Void }
struct SlideGetInfoKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var activeSlideSelection: Set<Int64>? {
        get { self[ActiveSlideSelectionKey.self] }
        set { self[ActiveSlideSelectionKey.self] = newValue }
    }
    var requestDuplicateSlides: (() -> Void)? {
        get { self[DuplicateSlidesKey.self] }
        set { self[DuplicateSlidesKey.self] = newValue }
    }
    var requestSlideGetInfo: (() -> Void)? {
        get { self[SlideGetInfoKey.self] }
        set { self[SlideGetInfoKey.self] = newValue }
    }
}

// MARK: - Focus: Edit Show's transport and timeline commands (F1), for the
// Show and View menus — bundled in one value, since they're all published
// together from `EditShowView` and only make sense there (timeline-only;
// absent, so their menu items disable themselves, in Edit Slides — see
// spec/hig-audit.md, "G. Edit Slides vs Edit Show").

struct EditShowCommandsValue {
    var togglePlay: () -> Void
    var addMarker: () -> Void
    var setRangeIn: () -> Void
    var setRangeOut: () -> Void
    var clearRange: () -> Void
    /// W7: the range button's ⌥⌘-click and ⇧⌥⌘-click, also from the Show
    /// menu since a modifier-click can't be seen (F1).
    var setRangeToView: () -> Void
    var setRangeToWholeShow: () -> Void
    var toggleRangeLock: () -> Void
    var rangeLocked: Bool
    var toggleLoop: () -> Void
    var loopOn: Bool
    var zoomToFit: () -> Void
    /// W8, item 7: the playhead's own history, out of ⌘Z on purpose
    /// (plan, "Go Back, not undo").
    var goBack: () -> Void
    var goForward: () -> Void
    var canGoBack: Bool
    var canGoForward: Bool
}
