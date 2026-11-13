// swift-tools-version: 6.0
// FlashSafety: the strobe safety envelope (FX-019, ADR-0011,
// specs/022-fx-019-strobe-safety-envelope/contracts/flash-envelope.md).
//
// Pure Swift with no dependencies, so the one definition of a flash and of its limits builds and is
// tested on Linux, and both renderers share it: native visuals (VisualGenerators) call it on the
// CPU; projectM frames run its GLSL port in CFlashLimiter (Rendering), and GPU tests compare the two.
import PackageDescription

let package = Package(
    name: "FlashSafety",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "FlashSafety", targets: ["FlashSafety"])],
    targets: [
        .target(name: "FlashSafety"),
        .testTarget(name: "FlashSafetyTests", dependencies: ["FlashSafety"]),
    ]
)
