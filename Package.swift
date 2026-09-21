// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShowTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShowToolsCore", targets: ["ShowToolsCore"]),
        .executable(name: "ShowToolsApp", targets: ["ShowToolsApp"]),
        .executable(name: "stcli", targets: ["stcli"]),
    ],
    targets: [
        .target(name: "ShowToolsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "ShowToolsApp", dependencies: ["ShowToolsCore"]),
        .executableTarget(name: "stcli", dependencies: ["ShowToolsCore"]),
        .testTarget(name: "ShowToolsCoreTests", dependencies: ["ShowToolsCore"]),
    ]
)
