// swift-tools-version: 6.0
// PaneKit: our own pane system for Mac apps (spec/panekit.md in ShowTools).
// Its own package, so it builds and tests on its own, and any app can add
// it as a local or git package dependency.
//
//   swift test                 the layout tests
//   swift run PaneHarness      the test app
import PackageDescription

let package = Package(
    name: "PaneKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaneKit", targets: ["PaneKit"]),
        .executable(name: "PaneHarness", targets: ["PaneHarness"]),
    ],
    targets: [
        .target(name: "PaneKit"),
        .executableTarget(name: "PaneHarness", dependencies: ["PaneKit"], path: "Harness"),
        .testTarget(name: "PaneKitTests", dependencies: ["PaneKit"]),
    ]
)
