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
//   `-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) gives that shape on the Mac. CMP-002 adds the
//   `LayerStack` value (CPU) that `Compositor.apply` takes between frames (ADR-0013 amendment).
// * `SpectrumLayers` adapts the native spectra (VIS-001, VIS-002, FX-001 glow) to the contract.
// * `CameraLayer` (CAM-001, ADR-0017) draws the newest picture of a `CameraFrameProvider` (a stub,
//   or the iOS `AVCaptureSession` provider) as a layer. Its feed states and geometry are plain Swift
//   and build on Linux; the Metal layer, the stub and the AVFoundation provider compile out there.
// * `ProceduralMaterials` (SHD-001, ADR-0018) is the catalog of curated procedural materials: five
//   materials whose parameters are MOD-001 descriptors (ParameterGraph, pure Swift) and whose layer
//   draws them under the contract. The shader source is a constant in the module (no external code);
//   the catalog, values and motion build on Linux, the layer and shaders compile out there.
// * `GeneratorGraph` (SHD-002) compiles declarative node graphs (closed node set, typed ports, cycle
//   and limit checks) into plans that one fixed, module-authored interpreter shader draws; no shader
//   is ever built from a graph. Document, validation and compiler build on Linux.
// * `ImageLayer` (MED-001, specs/044-med-001-import-photo-layer) imports, sanitizes (pixels only, no
//   metadata) and draws one still image as a layer. Limits, errors and geometry are plain Swift and
//   build on Linux; the ImageIO decoder/sanitizer and the Metal layer compile out there. The
//   `ImageDecoding` protocol is the seam MED-014 (safe media decoder) hardens.
// * `VideoLayer` (MED-002, specs/048-med-002-import-video-layer) imports (remux without soundtrack or
//   metadata) and plays one video as a layer at its own rate through a bounded decode queue. Limits,
//   errors, the playback clock and the queue are plain Swift and build on Linux; AVFoundation reading
//   and the Metal layer compile out there. It reuses CameraLayer's rotation and aspect-fill geometry.
// Nothing here imports projectM, ANGLE, capture or the app (Constitution VI). The projectM layer is
// target `ProjectMLayer` in Packages/ANGLERendering.
// One library product, so CI's `-scheme Compositor` builds and tests every target.
import PackageDescription

let package = Package(
    name: "Compositor",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "Compositor", targets: ["Compositor", "SpectrumLayers", "CameraLayer", "ProceduralMaterials", "GeneratorGraph", "ImageLayer", "VideoLayer"])],
    dependencies: [
        .package(path: "../AnalysisFeatures"),
        .package(path: "../FlashSafety"),
        .package(path: "../VisualGenerators"),
        // SHD-001: material parameters are MOD-001 descriptors (pure Swift; ADR-0012).
        .package(path: "../ParameterGraph"),
    ],
    targets: [
        .target(name: "Compositor", dependencies: ["AnalysisFeatures", "FlashSafety"]),
        .target(name: "SpectrumLayers", dependencies: ["Compositor", .product(name: "VisualGenerators", package: "VisualGenerators")]),
        .target(name: "CameraLayer", dependencies: ["Compositor"]),
        .target(name: "ProceduralMaterials", dependencies: ["Compositor", "ParameterGraph"]),
        .target(name: "GeneratorGraph", dependencies: ["Compositor"]),
        .target(name: "ImageLayer", dependencies: ["Compositor"]),
        .target(name: "VideoLayer", dependencies: ["Compositor", "CameraLayer"]),
        .testTarget(name: "CompositorTests",
                    dependencies: ["Compositor", "SpectrumLayers", "CameraLayer", "ImageLayer", "VideoLayer", "AnalysisFeatures", "FlashSafety",
                                   .product(name: "VisualGenerators", package: "VisualGenerators")]),
        .testTarget(name: "ProceduralMaterialsTests",
                    dependencies: ["ProceduralMaterials", "Compositor", "ParameterGraph", "FlashSafety", "AnalysisFeatures"]),
        .testTarget(name: "GeneratorGraphTests",
                    dependencies: ["GeneratorGraph", "Compositor", "FlashSafety", "AnalysisFeatures", "ProceduralMaterials"]),
    ]
)
