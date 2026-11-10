// swift-tools-version: 6.0
// ProjectMBridge: Objective-C++ bridge over the libprojectM C API (tasks T067-T069;
// contracts/projectm-bridge.md), plus the static OpenGL ES 3.0 load-proc table. The engine is the
// binary target Build/ProjectM.xcframework from scripts/build_projectm_xcframework.py (build it
// first). iOS only: the xcframework has device and simulator slices, so tests run on a simulator.
import PackageDescription

let package = Package(
    name: "ProjectMBridge",
    platforms: [.iOS("26.0")],
    products: [.library(name: "ProjectMBridge", targets: ["ProjectMBridge"])],
    targets: [
        .binaryTarget(name: "ProjectM", path: "../../Build/ProjectM.xcframework"),
        .target(name: "ProjectMBridge", dependencies: ["ProjectM"],
                // OpenGL ES is deprecated on iOS but is the Phase C renderer (ADR-0003 Option A). The
                // define must reach the module build of the system header, so it is set here.
                cSettings: [.define("GLES_SILENCE_DEPRECATION")],
                cxxSettings: [.define("GLES_SILENCE_DEPRECATION")],
                linkerSettings: [.linkedFramework("OpenGLES")]),
        .testTarget(name: "ProjectMBridgeTests", dependencies: ["ProjectMBridge"]),
    ],
    cxxLanguageStandard: .cxx17
)
