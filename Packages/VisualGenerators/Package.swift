// swift-tools-version: 6.0
// VisualGenerators: native visuals beside projectM (VIS rows; ADR-0009,
// specs/019-vis-001-circular-spectrum/contracts/visual-generator.md).
//
// * `VisualGenerators` has no package dependencies: the generator contract, CPU geometry, palettes,
//   the Reduce-flashing limiter, the band triple buffer and, behind
//   `#if canImport(Metal) && !VISUAL_NO_METAL`, the Metal generators. Shader source is a Swift
//   constant compiled at runtime (research VIS-001-D3), so the package has no resources and builds on
//   Linux, where only the Metal files compile out. `-Xswiftc -DVISUAL_NO_METAL` gives that shape on
//   the Mac.
// * `VisualBandFeed` turns the normalized ring's analysis tap into normalized bands
//   (AnalysisFeatures, ANL-001/002) on its own queue. Nothing here feeds projectM (Constitution
//   VIII, ADR-0008 decision 5).
// One library product, so CI's `-scheme VisualGenerators` builds and tests both targets.
import PackageDescription

let package = Package(
    name: "VisualGenerators",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "VisualGenerators", targets: ["VisualGenerators", "VisualBandFeed"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../AnalysisFeatures"),
    ],
    targets: [
        .target(name: "VisualGenerators"),
        .target(name: "VisualBandFeed", dependencies: ["VisualGenerators", "AudioCore", "AnalysisFeatures"]),
        .testTarget(name: "VisualGeneratorsTests",
                    dependencies: ["VisualGenerators", "VisualBandFeed", "AudioCore", "AnalysisFeatures"]),
    ]
)
