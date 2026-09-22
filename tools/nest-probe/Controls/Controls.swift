import AppIntents
import AppKit
import SwiftUI
import WidgetKit

/// The tile lives in the HOST app. Does it register from there, and can it
/// reach the nested helper by URL?
@main
struct NestControls: WidgetBundle {
    var body: some Widget { PingControl() }
}

struct PingIntent: AppIntent {
    static let title: LocalizedStringResource = "Nest Ping"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.open(URL(string: "nesthelper://ping")!, configuration: config)
        return .result()
    }
}

struct PingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jhg.nestprobe.ping") {
            ControlWidgetButton(action: PingIntent()) {
                Label("Nest Ping", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .displayName("Nest Ping")
        .description("Pokes the nested helper.")
    }
}
