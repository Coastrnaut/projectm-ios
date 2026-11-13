// swift-tools-version: 6.0
// ANGLERendering: ADR-0003 Option B, the engine on ANGLE's Metal backend through EGL (task T077).
// A separate package so that Rendering (Option A) does not depend on the ANGLE binaries; ADR-0003
// (T079) decides which backend stays. Needs Build/ANGLEFrameworks/libEGL.xcframework and
// libGLESv2.xcframework (scripts/build_angle_xcframework.py) and Build/ProjectM.xcframework.
// iOS only; tests run on a simulator. Target ProjectMLayer: projectM as a CMP-001 layer (ADR-0013).
import PackageDescription

let package = Package(
    name: "ANGLERendering",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ANGLERendering", targets: ["ANGLERendering", "ProjectMLayer"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../ProjectMBridge"),
        .package(path: "../Rendering"),
        // PERF-011: the renderer and the preset warm-up are presentation-bound resources.
        .package(path: "../PresentationLifecycle"),
        // FX-019: the strobe safety envelope's definition (ADR-0011).
        .package(path: "../FlashSafety"),
        // CMP-001 (ADR-0013): the layer contract the projectM layer conforms to.
        .package(path: "../Compositor"),
    ],
    targets: [
        .binaryTarget(name: "libEGL", path: "../../Build/ANGLEFrameworks/libEGL.xcframework"),
        // libEGL loads libGLESv2 at run time; depending on it embeds it next to libEGL.
        .binaryTarget(name: "libGLESv2", path: "../../Build/ANGLEFrameworks/libGLESv2.xcframework"),
        .target(name: "CANGLE", dependencies: ["libEGL", "libGLESv2"]),
        .target(name: "ANGLERendering",
                dependencies: ["CANGLE", "AudioCore", "ProjectMBridge", "Rendering", "PresentationLifecycle", "FlashSafety",
                               .product(name: "CFlashLimiter", package: "Rendering"),
                               // PERF-014: the render fault model (RenderHealth, back-off, injection).
                               .product(name: "Compositor", package: "Compositor")],
                linkerSettings: [.linkedFramework("QuartzCore"), .linkedFramework("Metal")]),
        // CMP-001: projectM as a compositor layer (EGL image over a Metal texture, shared-event sync).
        // Knows the layer contract, the bridge and ANGLE's EGL; nothing of other layers or analysis.
        .target(name: "ProjectMLayer",
                dependencies: ["CANGLE", "AudioCore", "ProjectMBridge", .product(name: "Compositor", package: "Compositor")],
                linkerSettings: [.linkedFramework("Metal")]),
        .testTarget(name: "ANGLERenderingTests",
                    dependencies: ["ANGLERendering", "ProjectMLayer", .product(name: "Compositor", package: "Compositor"), "CANGLE", "Rendering", "AudioCore", "ProjectMBridge", "PresentationLifecycle", "FlashSafety",
                                   .product(name: "CFlashLimiter", package: "Rendering")]),
    ]
)
