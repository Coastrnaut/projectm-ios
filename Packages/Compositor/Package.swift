// swift-tools-version: 6.0
// Compositor: the render boundary (CMP-001, ADR-0013; specs/029-cmp-001-unified-layer-protocol/
// contracts/layer-source.md).
//
// * `Compositor` depends only on AnalysisFeatures (the ANL-016 value types of the audio context) and
//   FlashSafety (FX-019's envelope definition): the layer contract, the frame clock, the audio
//   context, the picture bookkeeping and, behind `#if canImport(Metal) && !COMPOSITOR_NO_METAL`, the
//   `LayerSource` protocol, the Metal compositor and the composite flash guard. Shader source is a
//   Swift constant compiled at run time (ADR-0009 decision 3), so the package has no resources and
//   builds on Linux, where only the Metal files compile out. `-Xswiftc -DCOMPOSITOR_NO_METAL` (with
//   `-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) gives that shape on the Mac.
// * `SpectrumLayers` adapts the native spectra (VIS-001, VIS-002, FX-001 glow) to the contract.
// Nothing here imports projectM, ANGLE, capture or the app (Constitution VI). The projectM layer is
// target `ProjectMLayer` in Packages/ANGLERendering.
// One library product, so CI's `-scheme Compositor` builds and tests every target.
import PackageDescription

let package = Package(
    name: "Compositor",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "Compositor", targets: ["Compositor", "SpectrumLayers"])],
    dependencies: [
        .package(path: "../AnalysisFeatures"),
        .package(path: "../FlashSafety"),
        .package(path: "../VisualGenerators"),
    ],
    targets: [
        .target(name: "Compositor", dependencies: ["AnalysisFeatures", "FlashSafety"]),
        .target(name: "SpectrumLayers", dependencies: ["Compositor", .product(name: "VisualGenerators", package: "VisualGenerators")]),
        .testTarget(name: "CompositorTests",
                    dependencies: ["Compositor", "SpectrumLayers", "AnalysisFeatures", "FlashSafety",
                                   .product(name: "VisualGenerators", package: "VisualGenerators")]),
    ]
)
