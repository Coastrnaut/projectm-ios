// swift-tools-version: 6.0
// AudioCore: pure-Swift audio types, real-time ring buffers, level meter, the audio-state
// classifier and the Normalizer. No UIKit. AVFAudio (AVAudioConverter) is used only by the
// Normalizer, behind `canImport`, so the tests also run on Linux toolchains (a fallback resampler
// stands in there; Accelerate is optional — see LevelMeter.swift).
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
