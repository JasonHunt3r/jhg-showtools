import AppIntents
import SwiftUI
import WidgetKit

@main
struct BGControls: WidgetBundle {
    var body: some Widget {
        OpenBGToolsControl()
        DesktopShowControl()
    }
}

struct OpenBGToolsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jhg.BGControlProbe.open") {
            ControlWidgetButton(action: OpenBGToolsIntent()) {
                Label("BGTools", systemImage: "photo.on.rectangle.angled")
            }
        }
        .displayName("Open BGTools")
        .description("Opens BGTools' window.")
    }
}

struct DesktopShowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jhg.BGControlProbe.toggle") {
            ControlWidgetToggle("Desktop Show", isOn: UserDefaults.standard.bool(forKey: "desktopShowOn"),
                                action: SetDesktopShowIntent()) { on in
                Label(on ? "Playing" : "Off", systemImage: on ? "play.rectangle.fill" : "rectangle")
            }
        }
        .displayName("Desktop Show")
        .description("Turns the desktop show on or off.")
    }
}
