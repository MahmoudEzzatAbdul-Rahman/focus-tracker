// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GazeCore"),
        .executableTarget(name: "FocusTracker", dependencies: ["GazeCore"]),
        .testTarget(name: "GazeCoreTests", dependencies: ["GazeCore"]),
    ]
)
