// swift-tools-version: 6.0
// CaptureUI: SwiftUI views shared by CaptureLab and ProjectMiOS — the source chooser,
// microphone explainer, and status banner — using the exact strings in
// specs/001-ios-projectm-visualizer/contracts/ui-states.md.
import PackageDescription

let package = Package(
    name: "CaptureUI",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "CaptureUI", targets: ["CaptureUI"])],
    dependencies: [.package(path: "../CaptureKit"), .package(path: "../AudioCore")],
    targets: [
        .target(name: "CaptureUI", dependencies: ["CaptureKit", "AudioCore"]),
        .testTarget(name: "CaptureUITests", dependencies: ["CaptureUI", "AudioCore"]),
    ]
)
