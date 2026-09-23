import SwiftUI
import BGToolsCore
import ShowToolsCore
import ShowToolsPlayback

/// What the window's list has selected.
enum Selection: Hashable {
    case screen(String)
    case allSame
    case newScreens
    case randomPictures
}

/// BGTools' window (spec/bgtools.md, B4a): monitors and Spaces on the
/// left, drawn as they're arranged; the selected one's preview and
/// settings on the right.
struct MainWindow: View {
    @Environment(DesktopController.self) private var desktop
    @Environment(WindowState.self) private var state

    var body: some View {
        @Bindable var state = state
        let selection = state.selection
        NavigationSplitView {
            Sidebar(selection: $state.selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
        } detail: {
            switch selection {
            case .screen(let id):
                if let info = desktop.screens.first(where: { $0.id == id }) {
                    ScreenDetail(info: info)
                } else {
                    Placeholder(text: "That Space is gone.")
                }
            case .allSame: AllSameDetail()
            case .newScreens: NewScreensDetail()
            case .randomPictures: RandomPicturesDetail()
            case nil: Placeholder(text: "Choose a monitor or Space.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { LoginItem.isOn }, set: { LoginItem.setOn($0) }))
                    Divider()
                    Button("Quit BGTools") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle("Desktop Show", isOn: Binding(get: { desktop.settings.on },
                                                     set: { on in desktop.update { $0.on = on } }))
                    .toggleStyle(.switch)
                    .help("Turns the desktop show on or off on every screen")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if state.selection == nil, let current = desktop.screens.first(where: { $0.isMainDisplay && $0.isCurrent }) {
                state.selection = .screen(current.id)
            }
        }
    }
}

private struct Placeholder: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @Environment(DesktopController.self) private var desktop
    @Binding var selection: Selection?

    /// Monitors in the order macOS lists them, each with its Spaces.
    private var displays: [(name: String, display: String, spaces: [ScreenInfo])] {
        var order: [String] = []
        var byDisplay: [String: [ScreenInfo]] = [:]
        for s in desktop.screens {
            if byDisplay[s.key.display] == nil { order.append(s.key.display) }
            byDisplay[s.key.display, default: []].append(s)
        }
        return order.map { d in (byDisplay[d]![0].displayName, d, byDisplay[d]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Arrangement(selection: $selection)
                .frame(height: 110)
                .padding(12)
            List(selection: $selection) {
                ForEach(displays, id: \.display) { d in
                    Section(d.name) {
                        ForEach(d.spaces) { s in
                            SpaceRow(info: s).tag(Selection.screen(s.id))
                        }
                    }
                }
                Section {
                    HStack {
                        Label("All same", systemImage: "rectangle.on.rectangle")
                        Spacer()
                        Toggle("All same", isOn: Binding(get: { desktop.settings.allSame }, set: { on in
                            desktop.update {
                                $0.allSame = on
                                if on, $0.allSameSetting == nil { $0.allSameSetting = $0.newScreens }
                            }
                            if on { selection = .allSame }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("One choice on every monitor and Space, in sync")
                    }
                    .tag(Selection.allSame)
                    Label("New screens", systemImage: "plus.rectangle.on.rectangle").tag(Selection.newScreens)
                    Label("Random pictures", systemImage: "shuffle").tag(Selection.randomPictures)
                }
            }
        }
    }
}

private struct SpaceRow: View {
    @Environment(DesktopController.self) private var desktop
    let info: ScreenInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.spaceIndex > 0 ? "Space \(info.spaceIndex)" : "Every Space")
                Text(desktop.summary(for: info.id)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if info.isCurrent {
                Circle().fill(.green).frame(width: 7, height: 7).help("Showing now")
            }
        }
        .opacity(desktop.settings.allSame ? 0.5 : 1)
    }
}

/// The monitors drawn to scale where they sit, like System Settings ▸
/// Displays. Clicking one selects the Space it's showing.
private struct Arrangement: View {
    @Environment(DesktopController.self) private var desktop
    @Binding var selection: Selection?

    var body: some View {
        let displays = Dictionary(grouping: desktop.screens, by: \.key.display)
            .compactMap { $0.value.first }
            .sorted { $0.displayFrame.minX < $1.displayFrame.minX }
        GeometryReader { g in
            let union = displays.reduce(CGRect.null) { $0.union($1.displayFrame) }
            let scale = union.isNull ? 1 : min(g.size.width / union.width, g.size.height / union.height) * 0.95
            let offset = CGPoint(x: (g.size.width - union.width * scale) / 2,
                                 y: (g.size.height - union.height * scale) / 2)
            ZStack(alignment: .topLeading) {
                ForEach(displays) { d in
                    let f = d.displayFrame
                    // Screen coordinates rise upwards; the view's fall.
                    let rect = CGRect(x: offset.x + (f.minX - union.minX) * scale,
                                      y: offset.y + (union.maxY - f.maxY) * scale,
                                      width: f.width * scale, height: f.height * scale)
                    let selected = isSelected(d.key.display)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: selected ? 2 : 1))
                        .overlay(Text(d.displayName).font(.caption2).lineLimit(2).multilineTextAlignment(.center).padding(3))
                        .frame(width: rect.width - 3, height: rect.height - 3)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { select(d.key.display) }
                        .help(d.displayName)
                }
            }
        }
    }

    private func isSelected(_ display: String) -> Bool {
        if case .screen(let id) = selection { return desktop.screens.first { $0.id == id }?.key.display == display }
        return false
    }

    private func select(_ display: String) {
        let spaces = desktop.screens.filter { $0.key.display == display }
        if let s = spaces.first(where: \.isCurrent) ?? spaces.first { selection = .screen(s.id) }
    }
}

// MARK: Details

private struct ScreenDetail: View {
    @Environment(DesktopController.self) private var desktop
    let info: ScreenInfo

    var body: some View {
        let own = desktop.settings.screens[info.id]
        let effective = desktop.settings.setting(for: info.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(info.title).font(.title2.bold())
                    if info.isCurrent { Text("showing now").font(.caption).foregroundStyle(.green) }
                }
                Preview(player: desktop.player(for: info.id), aspect: info.displayFrame.width / max(info.displayFrame.height, 1))
                if desktop.settings.allSame {
                    Note("All same is on, so this screen plays All same's choice. Its own setting is kept for when All same is off.")
                }
                if let setting = own {
                    SettingEditor(setting: setting) { new in desktop.update { $0.screens[info.id] = new } }
                    if desktop.settings.newScreens != nil {
                        Button("Use the New screens default instead") { desktop.update { $0.screens[info.id] = nil } }
                    }
                } else {
                    Note(effective == nil
                         ? "Nothing chosen for this screen, and no New screens default: it shows your normal wallpaper."
                         : "This screen plays the New screens default. Choose something to give it its own.")
                    Button("Choose for this screen") {
                        if let start = effective ?? desktop.startingSetting() {
                            desktop.update { $0.screens[info.id] = start }
                        }
                    }
                    .disabled(effective == nil && desktop.startingSetting() == nil)
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct AllSameDetail: View {
    @Environment(DesktopController.self) private var desktop
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("All same").font(.title2.bold())
                Note(desktop.settings.allSame
                     ? "On: this plays on every monitor and Space, in sync."
                     : "Off. When it's on, this plays on every monitor and Space, in sync, and each screen's own setting waits.")
                Preview(player: desktop.settings.allSame ? desktop.players["all"] : nil, aspect: 16 / 10)
                OptionalSettingEditor(setting: desktop.settings.allSameSetting,
                                      emptyText: "Nothing chosen yet.") { new in desktop.update { $0.allSameSetting = new } }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct NewScreensDetail: View {
    @Environment(DesktopController.self) private var desktop
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New screens").font(.title2.bold())
                Note("Plays on any monitor or Space BGTools hasn't seen before, and on any screen without its own choice.")
                OptionalSettingEditor(setting: desktop.settings.newScreens,
                                      emptyText: "None: a new screen shows your normal wallpaper.") { new in
                    desktop.update { $0.newScreens = new }
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct RandomPicturesDetail: View {
    @Environment(DesktopController.self) private var desktop
    var body: some View {
        let d = desktop.settings.randomDefaults
        let set: ((inout ShowDefaults) -> Void) -> Void = { change in desktop.update { change(&$0.randomDefaults) } }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Random pictures").font(.title2.bold())
                Note("How the random modes show their pictures, which aren't slides of any show. Used on every screen.")
                Form {
                    LabeledContent("Length") {
                        HStack {
                            Slider(value: Binding(get: { d.length }, set: { v in set { $0.length = (v * 2).rounded() / 2 } }),
                                   in: 1...60)
                            Text("\(d.length, specifier: "%.1f") s").monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                    }
                    Picker("Transition", selection: Binding(get: { d.transition.style },
                                                            set: { v in set { $0.transition.style = v } })) {
                        ForEach(TransitionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if d.transition.style != .cut {
                        LabeledContent("Transition length") {
                            HStack {
                                Slider(value: Binding(get: { d.transition.duration },
                                                      set: { v in set { $0.transition.duration = (v * 10).rounded() / 10 } }),
                                       in: 0.2...5)
                                Text("\(d.transition.duration, specifier: "%.1f") s").monospacedDigit()
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                    Toggle("Pan and Zoom", isOn: Binding(get: { d.panAndZoom != .off },
                                                      set: { on in set { $0.panAndZoom = on ? .auto : .off } }))
                    Picker("Fit", selection: Binding(get: { d.fit }, set: { v in set { $0.fit = v } })) {
                        ForEach(Fit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

// MARK: Preview

/// The screen's own player, drawn large, with its controls. Pausing here
/// pauses the desktop too (it's the same player), until Play.
private struct Preview: View {
    let player: Player?
    let aspect: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle().fill(.black)
                if let engine = player?.engine {
                    ShowCanvasView(engine: engine)
                } else {
                    Text("Nothing playing").foregroundStyle(.secondary)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if let player, let engine = player.engine {
                Controls(player: player, engine: engine)
            }
        }
    }
}

private struct Controls: View {
    let player: Player
    let engine: PlaybackEngine

    var body: some View {
        HStack(spacing: 14) {
            Button { engine.step(-1) } label: { Image(systemName: "backward.end.fill") }.help("Previous picture")
            Button { engine.togglePlay() } label: { Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill") }
                .help(engine.isPlaying ? "Pause" : "Play")
            Button { engine.step(1) } label: { Image(systemName: "forward.end.fill") }.help("Next picture")
            Spacer()
            if let built = player.built {
                Text("\(built.show.name) · \(engine.currentIndex + 1) of \(built.show.slides.count)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: Setting editor

/// A setting that may not exist yet (All same, New screens).
private struct OptionalSettingEditor: View {
    @Environment(DesktopController.self) private var desktop
    let setting: ScreenSetting?
    let emptyText: String
    let onChange: (ScreenSetting?) -> Void

    var body: some View {
        if let setting {
            SettingEditor(setting: setting) { onChange($0) }
            Button("Clear") { onChange(nil) }
        } else {
            Note(emptyText)
            Button("Choose…") { onChange(desktop.startingSetting()) }
                .disabled(desktop.startingSetting() == nil)
        }
    }
}

/// Library, mode, the show or collection, Stills only, Sound.
struct SettingEditor: View {
    @Environment(DesktopController.self) private var desktop
    let setting: ScreenSetting
    let onChange: (ScreenSetting) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case show = "A show", shuffled = "A show, shuffled", collection = "Random from a collection"
        case randomShow = "A random show", allFiles = "Random from all files"
        var id: String { rawValue }
    }

    private var kind: Kind {
        switch setting.mode {
        case .show: .show
        case .shuffled: .shuffled
        case .collection: .collection
        case .randomShow: .randomShow
        case .allFiles: .allFiles
        }
    }

    var body: some View {
        let reader = desktop.reader(for: setting.library)
        let contents = reader?.contents
        Form {
            let choices = desktop.libraryChoices()
            Picker("Library", selection: Binding(get: {
                choices.first { LibraryChoices.same($0.path) == LibraryChoices.same(setting.library) }?.path ?? setting.library
            }, set: { path in
                guard LibraryChoices.same(path) != LibraryChoices.same(setting.library) else { return }
                var s = setting
                s.library = path
                // Ids belong to one library: start the new one on All files.
                s.mode = .allFiles
                onChange(s)
            })) {
                ForEach(choices) { Text($0.name).tag($0.path) }
            }
            if reader == nil {
                Note("This library can't be opened: see ~/Library/Logs/BGTools.log.")
            } else if desktop.isLocked(setting) {
                Note("This library is private, so it won't play until you unlock it. It locks again whenever the Mac sleeps or the screen locks.")
                Button("Unlock…") { Task { await desktop.unlock(setting) } }
            } else if reader?.isPrivate == true {
                Note("Private, and unlocked until the Mac sleeps or the screen locks.")
            }
            Picker("Plays", selection: Binding(get: { kind }, set: { k in onChange(with(k, contents)) })) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Toggle("Stills only", isOn: Binding(get: { setting.stillsOnly }, set: { v in
                var s = setting; s.stillsOnly = v; onChange(s)
            }))
            .help("Skips videos and animated images on this screen")
            Toggle("Sound", isOn: Binding(get: { setting.sound }, set: { v in
                var s = setting; s.sound = v; onChange(s)
            }))
            .help("Plays the show's music and video sound. Only the main display's current Space is heard.")
        }
        .formStyle(.grouped)
        if let contents, let reader {
            switch setting.mode {
            case .show(let id), .shuffled(let id):
                SourceGrid(items: contents.shows.map { show in
                    SourceGrid.Entry(id: show.id, name: show.name, detail: "\(show.slides.count) slides",
                                     cover: show.slides.first.flatMap { contents.items[$0.itemID] })
                }, selected: id, reader: reader) { picked in
                    var s = setting
                    s.mode = kind == .shuffled ? .shuffled(picked) : .show(picked)
                    onChange(s)
                }
            case .collection(let id):
                SourceGrid(items: contents.collections.map { c in
                    SourceGrid.Entry(id: c.id, name: c.name, detail: "\(c.itemIDs.count) items",
                                     cover: c.itemIDs.lazy.compactMap { contents.items[$0] }.first { $0.kind.isPicture })
                }, selected: id, reader: reader) { picked in
                    var s = setting
                    s.mode = .collection(picked)
                    onChange(s)
                }
            case .randomShow, .allFiles:
                EmptyView()
            }
        }
    }

    /// The setting in another mode, keeping the show when it can.
    private func with(_ k: Kind, _ contents: DesktopShow.Library?) -> ScreenSetting {
        var s = setting
        let currentShow: Int64? = { if case .show(let i) = setting.mode { return i }
                                    if case .shuffled(let i) = setting.mode { return i }
                                    return nil }()
        let firstShow = currentShow ?? contents?.shows.first?.id
        switch k {
        case .show: if let id = firstShow { s.mode = .show(id) }
        case .shuffled: if let id = firstShow { s.mode = .shuffled(id) }
        case .collection: if let id = contents?.collections.first?.id { s.mode = .collection(id) }
        case .randomShow: s.mode = .randomShow
        case .allFiles: s.mode = .allFiles
        }
        return s
    }
}

/// Shows or collections as thumbnails; one is chosen.
private struct SourceGrid: View {
    struct Entry: Identifiable {
        let id: Int64
        let name: String
        let detail: String
        let cover: MediaItem?
    }
    let items: [Entry]
    let selected: Int64
    let reader: LibraryReader
    let pick: (Int64) -> Void

    var body: some View {
        if items.isEmpty {
            Note("There aren't any in this library yet.")
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            ForEach(items) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Color.clear
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .overlay(Cover(item: e.cover, reader: reader))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(e.id == selected ? Color.accentColor : .clear, lineWidth: 3))
                    Text(e.name).lineLimit(1)
                    Text(e.detail).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { pick(e.id) }
            }
        }
    }
}

private struct Cover: View {
    let item: MediaItem?
    let reader: LibraryReader
    @State private var tick = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let item, let img = Thumbnails.shared.image(for: reader.url(for: item), kind: item.kind,
                                                           ready: { tick += 1 }) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .id(tick)
    }
}
