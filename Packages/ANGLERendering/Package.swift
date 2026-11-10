// swift-tools-version: 6.0
// ANGLERendering: ADR-0003 Option B, the engine on ANGLE's Metal backend through EGL (task T077).
// A separate package so that Rendering (Option A) does not depend on the ANGLE binaries; ADR-0003
// (T079) decides which backend stays. Needs Build/ANGLEFrameworks/libEGL.xcframework and
// libGLESv2.xcframework (scripts/build_angle_xcframework.py) and Build/ProjectM.xcframework.
// iOS only; tests run on a simulator.
import PackageDescription

let package = Package(
    name: "ANGLERendering",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ANGLERendering", targets: ["ANGLERendering"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../ProjectMBridge"),
        .package(path: "../Rendering"),
    ],
    targets: [
        .binaryTarget(name: "libEGL", path: "../../Build/ANGLEFrameworks/libEGL.xcframework"),
        // libEGL loads libGLESv2 at run time; depending on it embeds it next to libEGL.
        .binaryTarget(name: "libGLESv2", path: "../../Build/ANGLEFrameworks/libGLESv2.xcframework"),
        .target(name: "CANGLE", dependencies: ["libEGL", "libGLESv2"]),
        .target(name: "ANGLERendering",
                dependencies: ["CANGLE", "AudioCore", "ProjectMBridge", "Rendering",
                               .product(name: "CFlashLimiter", package: "Rendering")],
                linkerSettings: [.linkedFramework("QuartzCore"), .linkedFramework("Metal")]),
        .testTarget(name: "ANGLERenderingTests",
                    dependencies: ["ANGLERendering", "CANGLE", "Rendering", "AudioCore", "ProjectMBridge",
                                   .product(name: "CFlashLimiter", package: "Rendering")]),
    ]
)
