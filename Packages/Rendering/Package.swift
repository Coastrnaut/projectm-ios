// swift-tools-version: 6.0
// Rendering: VisualizerRenderer and its backends (tasks T070, T071; contracts/projectm-bridge.md).
// Consumes audio only through AudioCore's NormalizedPCMReader; never imports CaptureKit. The GLES
// backend uses ProjectMBridge, which needs Build/ProjectM.xcframework
// (scripts/build_projectm_xcframework.py). iOS only (UIKit, OpenGL ES); tests run on a simulator.
import PackageDescription

let package = Package(
    name: "Rendering",
    platforms: [.iOS("26.0")],
    products: [.library(name: "Rendering", targets: ["Rendering"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../ProjectMBridge"),
    ],
    targets: [
        .target(name: "Rendering", dependencies: ["AudioCore", "ProjectMBridge"],
                // OpenGL ES is deprecated on iOS but is ADR-0003 Option A; the define must reach the
                // Clang importer, so it is passed with -Xcc (a local path package may use unsafeFlags).
                swiftSettings: [.unsafeFlags(["-Xcc", "-DGLES_SILENCE_DEPRECATION"])],
                linkerSettings: [.linkedFramework("OpenGLES"), .linkedFramework("QuartzCore")]),
        .testTarget(name: "RenderingTests", dependencies: ["Rendering", "AudioCore", "ProjectMBridge"],
                    swiftSettings: [.unsafeFlags(["-Xcc", "-DGLES_SILENCE_DEPRECATION"])]),
    ]
)
