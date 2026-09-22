import SwiftUI

@main
struct BGControlProbeApp: App {
    init() { ProbeLog.write("app launched") }

    var body: some Scene {
        Window("BGTools (probe)", id: "main") {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48))
                Text("BGTools would open here").font(.title2)
                Text("Opened \(Date().formatted(date: .omitted, time: .standard))").foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }
}
