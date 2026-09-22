// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShowTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShowToolsCore", targets: ["ShowToolsCore"]),
        .library(name: "ShowToolsPlayback", targets: ["ShowToolsPlayback"]),
        .executable(name: "ShowToolsApp", targets: ["ShowToolsApp"]),
        .executable(name: "stcli", targets: ["stcli"]),
    ],
    targets: [
        .target(name: "ShowToolsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ShowToolsPlayback", dependencies: ["ShowToolsCore"]),
        .executableTarget(name: "ShowToolsApp", dependencies: ["ShowToolsCore", "ShowToolsPlayback"]),
        .executableTarget(name: "stcli", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "ShowToolsCoreTests", dependencies: ["ShowToolsCore"]),
    ]
)
