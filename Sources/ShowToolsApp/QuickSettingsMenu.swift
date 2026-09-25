import SwiftUI
import ShowToolsCore

/// The quick-settings submenus (`spec/conventions.md` §3, items 3 and 4):
/// Length ▸, Transition ▸, Pan and Zoom ▸, each applying to every id passed
/// in, in one undo step. Shared by Edit Slides' slide row and Edit Show's
/// viewer (`PreviewStage`) so a third place (the timeline pane, item 7)
/// doesn't have to re-derive it.
@MainActor
enum QuickSettingsMenu {
    /// Custom… opens the inspector on this setting, per the settled design,
    /// rather than a value picker here — `openInspector` does whatever that
    /// means for the caller (select the slide(s) and show the inspector).
    @ViewBuilder static func length(_ ids: [Int64], mutate: @escaping ShowMutator,
                                     openInspector: @escaping () -> Void) -> some View {
        Menu("Length") {
            ForEach([3.0, 3.5, 5.0, 8.0], id: \.self) { secs in
                Button(formatSeconds(secs)) {
                    mutate("Change Length") { s in
                        for i in s.slides.indices where ids.contains(s.slides[i].id) {
                            s.slides[i].settings.length = .seconds(secs)
                        }
                    }
                }
            }
            Divider()
            Button("Show Default") {
                mutate("Change Length") { s in
                    for i in s.slides.indices where ids.contains(s.slides[i].id) { s.slides[i].settings.length = nil }
                }
            }
            Button("Custom…") { openInspector() }
        }
    }

    /// Each style keeps the slide's current duration, direction and lead —
    /// only the style changes, exactly as `TransitionPicker`'s own style
    /// picker does. A slide with no override of its own starts from the
    /// show's default transition.
    @ViewBuilder static func transition(_ ids: [Int64], mutate: @escaping ShowMutator) -> some View {
        Menu("Transition") {
            ForEach(TransitionStyle.allCases, id: \.self) { style in
                Button(style.title) {
                    mutate("Change Transition") { s in
                        for i in s.slides.indices where ids.contains(s.slides[i].id) {
                            let base = s.slides[i].settings.transition ?? s.defaults.transition
                            s.slides[i].settings.transition = ShowToolsCore.Transition(
                                style: style, duration: base.duration, direction: base.direction, lead: base.lead)
                        }
                    }
                }
            }
            Divider()
            Button("Show Default") {
                mutate("Change Transition") { s in
                    for i in s.slides.indices where ids.contains(s.slides[i].id) { s.slides[i].settings.transition = nil }
                }
            }
        }
    }

    @ViewBuilder static func panAndZoom(_ ids: [Int64], mutate: @escaping ShowMutator) -> some View {
        Menu("Pan and Zoom") {
            Button("Off") { set(ids, .off, mutate: mutate) }
            Button("Auto") { set(ids, .auto, mutate: mutate) }
            Divider()
            Button("Show Default") { set(ids, nil, mutate: mutate) }
        }
    }

    private static func set(_ ids: [Int64], _ v: PanAndZoomSetting?, mutate: @escaping ShowMutator) {
        mutate("Change Pan and Zoom") { s in
            for i in s.slides.indices where ids.contains(s.slides[i].id) { s.slides[i].settings.panAndZoom = v }
        }
    }
}
