// swift-tools-version: 6.0
// RenderGoldens: golden render scenes (QA-002, specs/066-qa-002-golden-render-scenes,
// contracts/golden-suite.md; ADR-0030).
//
// * `GoldenImages` is plain Swift (Foundation only; builds and tests on Linux): RGBA8 images, an own
//   SHA-256 (no CryptoKit, no new dependency), the scene catalog (seeds, clocks, audio, generated
//   photos), the fixed QA-002 comparison rule and diff image, the per-platform manifest, the record
//   policy and CI guard, the suite's decision table and the manifest integrity check.
// * `SceneRenderHarness` (behind `#if canImport(Metal) && !COMPOSITOR_NO_METAL`) turns an SCN-001 scene's
//   live state into compositor layers (photo, material, graph, spectra, text), renders its fixed frames
//   through the `Compositor` with the flash guard on and captures the shown frame with REC-001's
//   capture, conversion and PNG coding. No new shader: only the existing layer and compositor passes.
// * `Scenes/` (canonical SCN-001 documents) and `Goldens/<class>/` (PNGs + manifest.json) sit at the
//   package root, outside the targets; the tests find them through `#filePath` so record mode can
//   write them back from the host and from the simulator.
// Linux shape on the Mac: `-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`.
// One library product, so CI's `-scheme RenderGoldens` builds and tests every target.
import PackageDescription

let package = Package(
    name: "RenderGoldens",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "RenderGoldens", targets: ["GoldenImages", "SceneRenderHarness"])],
    dependencies: [
        .package(path: "../SceneFormat"),
        .package(path: "../Compositor"),
        .package(path: "../VisualGenerators"),
        .package(path: "../ParameterGraph"),
        // The audio context's event type (no events are sent).
        .package(path: "../AnalysisFeatures"),
    ],
    targets: [
        .target(name: "GoldenImages"),
        .target(name: "SceneRenderHarness",
                dependencies: ["GoldenImages",
                               .product(name: "SceneFormat", package: "SceneFormat"),
                               .product(name: "Compositor", package: "Compositor"),
                               .product(name: "VisualGenerators", package: "VisualGenerators"),
                               .product(name: "ParameterGraph", package: "ParameterGraph"),
                               .product(name: "AnalysisFeatures", package: "AnalysisFeatures")]),
        .testTarget(name: "RenderGoldensTests",
                    dependencies: ["GoldenImages", "SceneRenderHarness",
                                   .product(name: "SceneFormat", package: "SceneFormat"),
                                   .product(name: "Compositor", package: "Compositor"),
                                   .product(name: "VisualGenerators", package: "VisualGenerators"),
                                   .product(name: "ParameterGraph", package: "ParameterGraph")]),
    ]
)
