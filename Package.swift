// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShowTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShowToolsCore", targets: ["ShowToolsCore"]),
        .library(name: "ShowToolsPlayback", targets: ["ShowToolsPlayback"]),
        .library(name: "BGToolsCore", targets: ["BGToolsCore"]),
        .executable(name: "ShowToolsApp", targets: ["ShowToolsApp"]),
        .executable(name: "stcli", targets: ["stcli"]),
    ],
    dependencies: [
        .package(name: "PaneKit", path: "PaneKit"),
    ],
    targets: [
        .target(name: "ShowToolsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ShowToolsPlayback", dependencies: ["ShowToolsCore"]),
        .target(name: "BGToolsCore", dependencies: ["ShowToolsCore"]),
        // Info.plist is generated into the sources folder by XcodeGen (the app
        // bundle is built by Xcode; see project.yml), so SwiftPM must be told
        // it isn't a resource.
        .executableTarget(name: "ShowToolsApp",
                          dependencies: ["ShowToolsCore", "ShowToolsPlayback", "PaneKit"],
                          exclude: ["Info.plist"]),
        .executableTarget(name: "stcli", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "ShowToolsCoreTests", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "BGToolsCoreTests", dependencies: ["BGToolsCore", "ShowToolsCore"]),
    ]
)
