// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShowTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShowToolsCore", targets: ["ShowToolsCore"]),
        .library(name: "ShowToolsPlayback", targets: ["ShowToolsPlayback"]),
        .library(name: "BGToolsCore", targets: ["BGToolsCore"]),
        // Our own pane system, meant for any Mac app (spec/panekit.md).
        .library(name: "PaneKit", targets: ["PaneKit"]),
        .executable(name: "ShowToolsApp", targets: ["ShowToolsApp"]),
        .executable(name: "stcli", targets: ["stcli"]),
    ],
    targets: [
        .target(name: "ShowToolsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ShowToolsPlayback", dependencies: ["ShowToolsCore"]),
        .target(name: "BGToolsCore", dependencies: ["ShowToolsCore"]),
        // Depends on nothing in ShowTools, so it can be lifted out later.
        .target(name: "PaneKit"),
        // PaneKit's test app: `swift run PaneHarness`.
        .executableTarget(name: "PaneHarness", dependencies: ["PaneKit"], path: "tools/pane-harness"),
        // Info.plist is generated into the sources folder by XcodeGen (the app
        // bundle is built by Xcode; see project.yml), so SwiftPM must be told
        // it isn't a resource.
        .executableTarget(name: "ShowToolsApp", dependencies: ["ShowToolsCore", "ShowToolsPlayback"],
                          exclude: ["Info.plist"]),
        .executableTarget(name: "stcli", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "ShowToolsCoreTests", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "BGToolsCoreTests", dependencies: ["BGToolsCore", "ShowToolsCore"]),
        .testTarget(name: "PaneKitTests", dependencies: ["PaneKit"]),
    ]
)
