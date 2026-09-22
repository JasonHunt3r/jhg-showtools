import SwiftUI

@main
struct BGControlProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var colour = ColourState.shared
    init() { ProbeLog.write("app launched") }

    var body: some Scene {
        Window("BGTools (probe)", id: "main") {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48))
                Text("BGTools would open here").font(.title2)
                Text("Opened \(Date().formatted(date: .omitted, time: .standard))").foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Self.swatches[colour.index % Self.swatches.count])
                    .frame(width: 220, height: 120)
                    .overlay(Text("\(Self.names[colour.index % Self.names.count])").font(.title).bold().foregroundStyle(.white))
                Text("Last change: \(colour.last)").foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }
}

extension BGControlProbeApp {
    static let swatches: [Color] = [.red, .green, .blue, .orange, .purple, .teal]
    static let names = ["Red", "Green", "Blue", "Orange", "Purple", "Teal"]
}

/// Routes A and B arrive here. URLs go through the delegate, not
/// SwiftUI's onOpenURL, so no window is opened or brought forward.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        DistributedNotificationCenter.default().addObserver(forName: NextColour.notification, object: nil, queue: .main) { n in
            let from = n.object as? String ?? "?"
            MainActor.assumeIsolated { ColourState.shared.next(via: from) }
        }
    }
    func application(_ app: NSApplication, open urls: [URL]) {
        ProbeLog.write("URL arrived: \(urls); active \(app.isActive)")
        MainActor.assumeIsolated { ColourState.shared.next(via: "B") }
    }
}
