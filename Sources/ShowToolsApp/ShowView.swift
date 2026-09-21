import SwiftUI
import ShowToolsCore

struct ShowView: View {
    let showID: Int64
    @Environment(AppModel.self) private var model
    @State private var selection: Set<Int64> = []
    @State private var inspectorShown = true
    @State private var dropTargeted = false

    private var show: Show { model.show(showID) ?? Show(id: showID, name: "") }

    private func mutate(_ change: (inout Show) -> Void) {
        var s = show
        change(&s)
        model.update(s)
    }

    var body: some View {
        let timeline = model.timeline(for: show)
        VStack(spacing: 0) {
            DefaultsBar(show: show, duration: timeline.duration, mutate: mutate)
            Divider()
            slideList(timeline)
        }
        .navigationTitle(show.name)
        .navigationSubtitle("\(show.slides.count) slides · \(formatDuration(timeline.duration))")
        .toolbar {
            ToolbarItemGroup {
                Button { Player.open(show: show, model: model, fullScreen: false, startAt: firstSelectedIndex) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .help("Play in a window (⌥⇧⌘P)")
                .disabled(show.slides.isEmpty)
                Button { Player.open(show: show, model: model, fullScreen: true, startAt: firstSelectedIndex) } label: {
                    Label("Play Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Play full screen (⌥⌘P)")
                .disabled(show.slides.isEmpty)
                Button { inspectorShown.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
            }
        }
        .inspector(isPresented: $inspectorShown) {
            SlideInspector(show: show, selection: selection, mutate: mutate)
                .inspectorColumnWidth(min: 250, ideal: 280, max: 380)
        }
        .focusedSceneValue(\.activeShowID, showID)
        .onChange(of: showID) { selection = [] }
    }

    private var firstSelectedIndex: Int? {
        show.slides.firstIndex { selection.contains($0.id) }
    }

    private func slideList(_ timeline: ShowTimeline) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: timeline.slides.map { ($0.slide.id, $0) })
        return List(selection: $selection) {
            ForEach(Array(show.slides.enumerated()), id: \.element.id) { i, slide in
                SlideRow(number: i + 1, slide: slide, item: model.itemsByID[slide.itemID],
                         resolved: byID[slide.id], url: model.itemsByID[slide.itemID].flatMap(model.url(for:)))
                    .tag(slide.id)
            }
            .onMove { from, to in
                mutate { $0.slides.move(fromOffsets: from, toOffset: to) }
            }
        }
        .onDeleteCommand { removeSelected() }
        .contextMenu(forSelectionType: Int64.self) { ids in
            Button("Duplicate") { duplicate(ids) }
            Button("Remove from Show") { remove(ids) }
            Divider()
            Button("Play from Here") {
                let i = show.slides.firstIndex { ids.contains($0.id) }
                Player.open(show: show, model: model, fullScreen: false, startAt: i)
            }
        }
        .overlay {
            if show.slides.isEmpty {
                ContentUnavailableView("No slides yet", systemImage: "rectangle.stack",
                    description: Text("Select items in the Library and choose Add to Show, or drag files here."))
            }
        }
        .onDrop(of: droppableTypes, isTargeted: $dropTargeted) { providers in
            Task {
                let ids = await model.importProviders(providers)
                model.append(ids, to: showID)
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
    }

    private func removeSelected() { remove(selection) }

    /// Takes slides out of this show. The files stay in the library.
    private func remove(_ ids: Set<Int64>) {
        guard !ids.isEmpty, SlideRemovalNotice.confirm(count: ids.count) else { return }
        mutate { $0.slides.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
    }

    /// Copies go right after their originals, with their settings, as new uses.
    private func duplicate(_ ids: Set<Int64>) {
        mutate { s in
            var out: [Slide] = []
            for slide in s.slides {
                out.append(slide)
                if ids.contains(slide.id) { out.append(Slide(id: 0, itemID: slide.itemID, settings: slide.settings)) }
            }
            s.slides = out
        }
    }
}

struct SlideRow: View {
    let number: Int
    let slide: Slide
    let item: MediaItem?
    let resolved: ResolvedSlide?
    let url: URL?

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            if let item {
                ThumbnailView(item: item, url: url)
                    .frame(width: 72, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName).lineLimit(1).truncationMode(.middle)
                    if let r = resolved {
                        HStack(spacing: 6) {
                            setting(formatSeconds(r.length), custom: slide.settings.length != nil)
                            Text("·").foregroundStyle(.tertiary)
                            setting(r.transitionIn.style.title, custom: slide.settings.transition != nil)
                            if r.kenBurns != nil {
                                Text("·").foregroundStyle(.tertiary)
                                setting("Ken Burns", custom: slide.settings.kenBurns != nil)
                            }
                        }
                        .font(.caption)
                    }
                }
                Spacer()
                if let r = resolved {
                    Text(formatDuration(r.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Missing from library").foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    /// Values the slide sets itself are shown stronger than inherited ones.
    private func setting(_ text: String, custom: Bool) -> some View {
        Text(text)
            .foregroundStyle(custom ? Color.accentColor : .secondary)
            .fontWeight(custom ? .medium : .regular)
    }
}

// MARK: - Show defaults

struct DefaultsBar: View {
    let show: Show
    let duration: Double
    let mutate: ((inout Show) -> Void) -> Void

    var body: some View {
        let d = show.defaults
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                TextField("Name", text: Binding(get: { show.name },
                                                set: { v in mutate { $0.name = v } }))
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 140, maxWidth: 240)

                Divider().frame(height: 22)

                labelled("Length") {
                    SecondsField(value: d.length) { v in mutate { $0.defaults.length = v } }
                }
                labelled("Transition") {
                    TransitionPicker(transition: d.transition) { t in mutate { $0.defaults.transition = t } }
                }
                labelled("Ken Burns") {
                    Picker("", selection: Binding(get: { d.kenBurns == .auto },
                                                  set: { on in mutate { $0.defaults.kenBurns = on ? .auto : .off } })) {
                        Text("Off").tag(false)
                        Text("Auto").tag(true)
                    }
                    .labelsHidden().fixedSize()
                }
                labelled("Fit") {
                    Picker("", selection: Binding(get: { d.fit }, set: { f in mutate { $0.defaults.fit = f } })) {
                        ForEach(Fit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Toggle("Loop", isOn: Binding(get: { d.loop }, set: { v in mutate { $0.defaults.loop = v } }))
                Toggle("Videos play in full", isOn: Binding(get: { d.videoUsesClipLength },
                                                            set: { v in mutate { $0.defaults.videoUsesClipLength = v } }))
                    .help("Video slides use their clip's length unless given their own")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            content()
        }
        .fixedSize()
    }
}

/// A seconds value with a stepper. Commits on Return or when focus leaves.
struct SecondsField: View {
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { set(max(0.1, $0)) }),
                      format: .number.precision(.fractionLength(0...2)))
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
            Text("s").foregroundStyle(.secondary)
            Stepper("", value: Binding(get: { value }, set: { set(max(0.5, ($0 * 2).rounded() / 2)) }),
                    step: 0.5)
                .labelsHidden()
        }
    }
}

struct TransitionPicker: View {
    let transition: ShowToolsCore.Transition
    let set: (ShowToolsCore.Transition) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { transition.style },
                                          set: { var t = transition; t.style = $0; set(t) })) {
                ForEach(TransitionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
            if transition.style != .cut {
                SecondsField(value: transition.duration) { var t = transition; t.duration = $0; set(t) }
            }
            if transition.style.usesDirection {
                Picker("", selection: Binding(get: { transition.direction },
                                              set: { var t = transition; t.direction = $0; set(t) })) {
                    ForEach(Direction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}
