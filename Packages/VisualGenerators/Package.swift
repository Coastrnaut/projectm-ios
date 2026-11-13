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
// * `VisualEffects` (FX-001, ADR-0010) holds post-processing effects and the effect chain; it
//   depends only on `VisualGenerators`. CPU parts (parameters, plans, the chain description) build
//   everywhere; the Metal effects compile out like the generators.
// One library product, so CI's `-scheme VisualGenerators` builds and tests every target.
import PackageDescription

let package = Package(
    name: "VisualGenerators",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "VisualGenerators", targets: ["VisualGenerators", "VisualBandFeed", "VisualEffects"])],
    dependencies: [
        .package(path: "../AudioCore"),
        .package(path: "../AnalysisFeatures"),
    ],
    targets: [
        .target(name: "VisualGenerators"),
        .target(name: "VisualBandFeed", dependencies: ["VisualGenerators", "AudioCore", "AnalysisFeatures"]),
        .target(name: "VisualEffects", dependencies: ["VisualGenerators"]),
        .testTarget(name: "VisualGeneratorsTests",
                    dependencies: ["VisualGenerators", "VisualBandFeed", "VisualEffects", "AudioCore", "AnalysisFeatures"]),
    ]
)
