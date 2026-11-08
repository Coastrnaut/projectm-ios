// swift-tools-version: 6.0
// CaptureKit: the AudioSource contract, CaptureManager, and the three source adapters
// (System/App Capture, Microphone, In-App Playback). Platform capture types never leave this
// package (Constitution VI; contracts/audio-source.md guarantee 5).
import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "CaptureKit", targets: ["CaptureKit"])],
    dependencies: [.package(path: "../AudioCore")],
    targets: [
        .target(name: "CaptureKit", dependencies: ["AudioCore"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit", "AudioCore"]),
    ]
)
