// swift-tools-version: 6.0
// AudioCore: pure-Swift audio types, real-time ring buffer, level meter, and the audio-state
// classifier. No UIKit/AVFoundation, so its tests run with `swift test` on a macOS host
// (and on Linux toolchains; Accelerate is optional — see LevelMeter.swift).
import PackageDescription

let package = Package(
    name: "AudioCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "AudioCore", targets: ["AudioCore"])],
    targets: [
        .target(name: "AudioCore"),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore"]),
    ]
)
