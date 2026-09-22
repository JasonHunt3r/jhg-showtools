import AppIntents
import SwiftUI
import WidgetKit

@main
struct BGControls: WidgetBundle {
    var body: some Widget {
        OpenBGToolsControl()
        DesktopShowControl()
        ColourAControl()
        ColourBControl()
        ColourCControl()
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

/// Part 6's tiles: one per route (see Intents.swift). ControlWidget needs
/// init(), so each is its own small type.
@MainActor func colourTile<I: AppIntent>(_ kind: String, _ title: String, _ intent: I) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.jhg.BGControlProbe.next.\(kind)") {
        ControlWidgetButton(action: intent) {
            Label(title, systemImage: "paintpalette")
        }
    }
    .displayName(LocalizedStringResource(stringLiteral: title))
    .description("Changes the probe app's colour without opening it.")
}

struct ColourAControl: ControlWidget {
    var body: some ControlWidgetConfiguration { colourTile("a", "Colour A", NextColourByNotificationIntent()) }
}
struct ColourBControl: ControlWidget {
    var body: some ControlWidgetConfiguration { colourTile("b", "Colour B", NextColourByURLIntent()) }
}
struct ColourCControl: ControlWidget {
    var body: some ControlWidgetConfiguration { colourTile("c", "Colour C", NextColourDirectIntent()) }
}
