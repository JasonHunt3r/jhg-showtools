import SwiftUI
import AppKit
import ShowToolsCore
import ShowToolsPlayback

/// The Slide Editor (`spec/windows.md`): a slide alone, large, in front of
/// everything, with its settings beside it — the deep version of the
/// inspector, opened on purpose (double-click a slide, in either mode;
/// `spec/conventions.md` §"Double-click", settled 2026-09-24). "Like a big
/// popover: you work in it, and when you're done it goes away" — one at a
/// time, like `InfoPanel`.
///
/// **v1 scope** (settled 2026-09-24): the image, its Transform/Rotation
/// handles and the full inspector. No playback controls — it's one slide,
/// not the show. The collage maker and clicking to aim the Pan and Zoom
/// point are Later, not here (`spec/plan.md`).
///
/// Owns its own `PlaybackEngine`, paused on the one slide, rather than
/// sharing the show's session engine — so opening it never disturbs
/// whatever the main window's preview is doing, and it works from Edit
/// Slides too, which has no engine running at all.
@MainActor
final class SlideEditorWindow: NSObject, NSWindowDelegate {
    private static var shared: SlideEditorWindow?

    static func show(slideID: Int64, show: Show, model: AppModel, mutate: @escaping ShowMutator,
                      undoManager: UndoManager?) {
        if let shared {
            shared.retarget(slideID: slideID, show: show)
            shared.window.makeKeyAndOrderFront(nil)
            return
        }
        let editor = SlideEditorWindow(model: model, mutate: mutate, undoManager: undoManager)
        Self.shared = editor
        editor.retarget(slideID: slideID, show: show)
        editor.present()
    }

    static func closeIfOpen() { shared?.window.close() }

    private let model: AppModel
    private let mutate: ShowMutator
    private let state = SlideEditorState()
    private var engine: PlaybackEngine?
    private let window: SlideEditorPanel

    private init(model: AppModel, mutate: @escaping ShowMutator, undoManager: UndoManager?) {
        self.model = model
        self.mutate = mutate
        window = SlideEditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Slide Editor"
        window.minSize = NSSize(width: 640, height: 420)
        window.isFloatingPanel = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.sharedUndoManager = undoManager
        window.onEscape = { [weak self] in self?.window.close() }
        window.setFrameAutosaveName("slideEditor")
    }

    /// Switches the engine to `show` (a fresh one if it's a different show
    /// than before) and pauses it on `slideID`.
    private func retarget(slideID: Int64, show: Show) {
        if engine == nil || engine?.showID != show.id {
            engine?.shutdown()
            let e = PlaybackEngine(showID: show.id, model: model)
            engine = e
            window.contentView = NSHostingView(
                rootView: SlideEditorContent(mutate: mutate, engine: e, state: state).environment(model))
        }
        engine?.showSlide(id: slideID)
        state.slideID = slideID
        state.show = show
        let i = show.slides.firstIndex(where: { $0.id == slideID })
        window.title = i.map { "Slide Editor — Slide \($0 + 1)" } ?? "Slide Editor"
    }

    private func present() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        engine?.shutdown()
        Self.shared = nil
    }
}

/// Overriding `undoManager` matters the same way it does for `InfoPanel`
/// (see its own note): without it, ⌘Z right after an edit here would ask
/// the wrong manager. `onEscape` closes the window, `spec/conventions.md`
/// §2's "Esc … close the Slide Editor".
final class SlideEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var sharedUndoManager: UndoManager?
    override var undoManager: UndoManager? { sharedUndoManager }
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// What slide is open, read by `SlideEditorContent` — a class, not a
/// `@State`, so `retarget` can change it without tearing down and rebuilding
/// the hosting view (which would lose the picture's zoom and selection).
@MainActor
@Observable
final class SlideEditorState {
    var slideID: Int64?
    var show: Show?
}

/// The image, its handles, and the full inspector beside it.
struct SlideEditorContent: View {
    let mutate: ShowMutator
    let engine: PlaybackEngine
    let state: SlideEditorState
    @Environment(AppModel.self) private var model
    @State private var imageSlideID: Int64?
    @State private var selectedOverlay: UUID?
    @State private var selection: Set<Int64> = []
    @State private var editTarget: TransformOverlay.Target = .transform

    /// Rotation mode is only offered for a slide with Rotation on.
    private var rotationAvailable: Bool {
        guard let id = state.slideID else { return false }
        return engine.show.slides.first(where: { $0.id == id })?.settings.rotation?.enabled == true
    }

    var body: some View {
        if let show = state.show, let slideID = state.slideID {
            HStack(spacing: 0) {
                canvas
                Divider()
                SlideInspector(show: show, timeline: model.timeline(for: show), selection: [slideID],
                               mutate: mutate, engine: engine)
                    .frame(width: 300)
            }
            .onAppear { imageSlideID = slideID; selection = [slideID] }
            .onChange(of: slideID) { _, new in imageSlideID = new; selection = [new] }
        } else {
            Color.black
        }
    }

    private var canvas: some View {
        ZStack {
            Color.black
            GeometryReader { g in
                let stage = ShowCanvas.Stage(zoom: 1, onionSlideID: nil, onionOpacity: 0, aspect: outputAspect)
                ShowCanvasView(engine: engine, stage: stage)
                TransformOverlay(engine: engine, frame: PreviewStage.pictureRect(in: g.size, zoom: 1),
                                 target: rotationAvailable ? editTarget : .transform,
                                 imageSlideID: $imageSlideID, selectedOverlay: $selectedOverlay,
                                 selection: $selection, mutate: mutate)
            }
            if rotationAvailable {
                VStack {
                    HStack {
                        Spacer()
                        Picker("", selection: $editTarget) {
                            Text("Transform").tag(TransformOverlay.Target.transform)
                            Text("Rotation").tag(TransformOverlay.Target.rotation)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .padding(10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(10)
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
            }
        }
        .frame(minWidth: 400)
    }
}
