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
//   PERF-004 (specs/052-perf-004-texture-pool) adds the `TexturePool` the compositor takes its pictures
//   from: plain-Swift bookkeeping (`TexturePoolCore`, Linux-testable) and a locked Metal wrapper.
//   CMP-013 (specs/113-cmp-013-render-caching, ADR-0040) adds render caching: the plain-Swift dependency and
//   key model (`LayerRenderCache.swift`, Linux-testable) and, in the compositor, reuse of unchanged layer
//   pictures and of an unchanged composite; the photo and text layers declare their dependencies.
//   CMP-014 (specs/116-cmp-014-compositor-transition-bus, ADR-0041) adds the scene transition model (spec, easing,
//   the frame-timeline clock, weights; `SceneTransition.swift`, Linux-testable) and `SceneTransitionBus`, which blends
//   two compositors' composites and runs one flash guard on the shown frame (`Compositor.encodeScene`).
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
//   and the Metal layer compile out there. It reuses CameraLayer's rotation type; CMP-006 fits it with `LayerFitPlacement` on the upright size.
// * `GeneratorGraphImport` (SHD-011, ADR-0024) turns the bytes of an imported file into a validated,
//   compiled generator graph or one typed refusal: size limit before decoding, executables, scripts
//   and archives refused by their first bytes, `JSONDecoder` into the SHD-002 document. It reads no
//   files and loads nothing; Foundation only, builds on Linux.
// * `TextLayer` (MED-009, specs/053-med-009-text-overlay) draws one styled message as a layer: spec,
//   cleaning, limits, direction and placement are plain Swift and build on Linux; the CoreText
//   rasterizer and the Metal upload (clear + blit, no shader) compile out there.
// * `FrameCapture` (REC-001, specs/055-rec-001-still-frame-capture) turns a captured frame (linear
//   premultiplied half floats from the compositor, or 8-bit sRGB from the native and projectM paths)
//   into 8-bit sRGB pixels per format policy and encodes PNG or HEIF with ImageIO (no metadata). The
//   conversion and refusal rules are plain Swift and build on Linux; ImageIO compiles out there.
// * `MediaSniffing` (MED-014, specs/056-med-014-safe-media-decoder) checks the structure of untrusted
//   image and movie bytes (PNG, JPEG, HEIF, ISO/QuickTime boxes) before ImageIO or AVFoundation sees
//   them: bounded, plain Swift, no dependencies, builds on Linux. ImageLayer and VideoLayer call it.
// * `FrameRecording` (REC-003, specs/058-rec-003-video-recording, ADR-0027) records shown frames into an
//   MP4 video: settings, geometry, the timestamp timeline, the bounded frame gate and the outcomes are
//   plain Swift and build on Linux; the AVAssetWriter writer, the read-back inspector and the Metal
//   recorder (IOSurface pixel buffers through a texture cache, no CPU read-back) compile out there.
// Nothing here imports projectM, ANGLE, capture or the app (Constitution VI). The projectM layer is
// target `ProjectMLayer` in Packages/ANGLERendering.
// One library product, so CI's `-scheme Compositor` builds and tests every target.
import PackageDescription

let package = Package(
    name: "Compositor",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "Compositor", targets: ["Compositor", "SpectrumLayers", "CameraLayer", "ProceduralMaterials", "GeneratorGraph", "GeneratorGraphImport", "ImageLayer", "VideoLayer", "TextLayer", "FrameCapture", "MediaSniffing", "FrameRecording"])],
    dependencies: [
        .package(path: "../AnalysisFeatures"),
        .package(path: "../FlashSafety"),
        .package(path: "../VisualGenerators"),
        // SHD-001: material parameters are MOD-001 descriptors (pure Swift; ADR-0012).
        .package(path: "../ParameterGraph"),
    ],
    targets: [
        // REC-001: still frame capture: formats, color conversion, ImageIO encoding (pure Swift + ImageIO).
        .target(name: "FrameCapture"),
        // REC-003: video recording (pure Swift rules + AVFoundation writer + Metal recorder).
        .target(name: "FrameRecording"),
        .target(name: "Compositor", dependencies: ["AnalysisFeatures", "FlashSafety", "FrameCapture"]),
        .target(name: "SpectrumLayers", dependencies: ["Compositor", .product(name: "VisualGenerators", package: "VisualGenerators")]),
        .target(name: "CameraLayer", dependencies: ["Compositor"]),
        .target(name: "ProceduralMaterials", dependencies: ["Compositor", "ParameterGraph"]),
        .target(name: "GeneratorGraph", dependencies: ["Compositor"]),
        .target(name: "MediaSniffing"),
        .target(name: "ImageLayer", dependencies: ["Compositor", "MediaSniffing"]),
        .target(name: "VideoLayer", dependencies: ["Compositor", "CameraLayer", "MediaSniffing"]),
        .target(name: "GeneratorGraphImport", dependencies: ["GeneratorGraph"]),
        .target(name: "TextLayer", dependencies: ["Compositor"]),
        .testTarget(name: "CompositorTests",
                    dependencies: ["Compositor", "SpectrumLayers", "CameraLayer", "ImageLayer", "VideoLayer", "MediaSniffing", "AnalysisFeatures", "FlashSafety", "FrameCapture", "FrameRecording",
                                   .product(name: "VisualGenerators", package: "VisualGenerators")]),
        .testTarget(name: "ProceduralMaterialsTests",
                    dependencies: ["ProceduralMaterials", "Compositor", "ParameterGraph", "FlashSafety", "AnalysisFeatures"]),
        .testTarget(name: "GeneratorGraphTests",
                    dependencies: ["GeneratorGraph", "Compositor", "FlashSafety", "AnalysisFeatures", "ProceduralMaterials"]),
        .testTarget(name: "FrameCaptureTests", dependencies: ["FrameCapture"]),
        .testTarget(name: "FrameRecordingTests", dependencies: ["FrameRecording"]),
        .testTarget(name: "GeneratorGraphImportTests", dependencies: ["GeneratorGraphImport", "GeneratorGraph"]),
        .testTarget(name: "MediaSniffingTests", dependencies: ["MediaSniffing"]),
        .testTarget(name: "TextLayerTests", dependencies: ["TextLayer", "Compositor", "FlashSafety", "AnalysisFeatures"]),
    ]
)
