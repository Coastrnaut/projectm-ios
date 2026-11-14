# Implementation Plan: SHD-004 Shader Variant Switching

**Branch**: `feature/shd-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/231-shd-004-shader-variant-switching/spec.md`

## Summary

SHD-003's metadata document gains an optional `variants` list (ID, label, optional Apple GPU family).
The validator checks it; the catalog exposes each material's variants. Two new fragment functions join
the reviewed module constant (`mat_plasmaDetailed`, `mat_noiseFlowLite`). `ProceduralMaterialLayer`
gets a selected variant, an injectable `MaterialGPUCapabilities`, a per-layer pipeline cache built in
`prepare` (default + every supported variant), and a resolution (drawn variant + notice) recomputed on
select and prepare, never in render. SceneFormat stores the selection as the optional layer field
`materialVariant`, carries it through live state and capture, and warns `unknownMaterialVariant`.
RenderGoldens' scene harness draws the stored variant. The app's layer inspector shows a read-only
"Variant" picker built from the metadata.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0), Xcode 27.2 (CI also Xcode 26)
**Primary Dependencies**: ShaderParameterMetadata (SHD-003), ProceduralMaterials (SHD-001), SceneFormat (SCN-001), Metal (`supportsFamily`, pipelines), SwiftUI (app)
**Storage**: scene JSON, one optional layer field; no UserDefaults keys
**Testing**: XCTest — metadata/validator and catalog tests (CPU, Linux shape), GPU tests on the host GPU (switch, goldens per variant, injected-capability fallback), SceneFormat round-trip tests, RenderGoldens scene test, app unit test + one UI test on "SHD4 iPhone 17" (iOS 27.2)
**Target Platform**: iOS 26+/macOS 15 (packages), Linux (CPU parts)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: switch = pointer swap (no pipeline creation in render); prepare builds ≤ 3 small pipelines
**Constraints**: SHD-011 (shader code only from the reviewed module constant); render path allocation-free; Xcode 26 type-check budget; short tests
**Scale/Scope**: 5 materials, 7 variants, 1 scene field, 1 issue code, 1 picker

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: `MTLDevice.supportsFamily`, `makeRenderPipelineState`, SwiftUI `Picker`. |
| VI Modular boundaries | Pass: variant metadata in ShaderParameterMetadata (plain Swift); capability and cache in ProceduralMaterials; SceneFormat stores text only. |
| VII Real-time audio safety | Pass: nothing on audio threads; render does no allocation or pipeline creation. |
| X Evidence-based quality | Pass: validator unit tests, GPU goldens per variant, fallback with injected capability; device look on D2/D3 left `{device}`. |
| SHD-011 / ADR-0024 | Pass: variants are functions of `ProceduralMaterialShaders.source`; `MaterialSourceSafetyTests` still sees one library creation. |

Post-design re-check: unchanged (Pass).

## Project Structure

```text
Packages/Compositor/Sources/ShaderParameterMetadata/
  ShaderVariantMetadata.swift        # new: ShaderGPUFamily, ShaderVariantSpec, variants reader
  ShaderMetadataValidator.swift      # reads optional "variants"
  ShaderMetadataError.swift          # variant errors
Packages/Compositor/Sources/ProceduralMaterials/
  MaterialParameterMetadata.swift    # plasma, noiseFlow variant lists
  MaterialDefinition.swift           # variants, fragmentFunction(for:)
  MaterialVariants.swift             # new: MaterialGPUCapabilities, MaterialVariantResolution/Notice (plain Swift)
  ProceduralMaterialLayer.swift      # selection, pipeline cache, resolution
  ProceduralMaterialShaders.swift    # mat_plasmaDetailed, mat_noiseFlowLite; capabilities(device:)
Packages/Compositor/Tests/{ShaderParameterMetadataTests,ProceduralMaterialsTests}/  # variant tests
Packages/SceneFormat/Sources/SceneFormat/  # SceneLayer.materialVariant, codec, live state, validation, issue
Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenLayerFactory.swift
Apps/projectM-iOS/  # MaterialInspectorModel variants, MaterialVariantSection, LayerInspectorRow, tests
```

**Structure Decision**: extend the existing SHD-001/SHD-003 targets; no new package or target.

## Complexity Tracking

None.
