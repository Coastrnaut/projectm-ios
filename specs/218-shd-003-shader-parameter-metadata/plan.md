# Implementation Plan: SHD-003 Shader Parameter Metadata

**Branch**: `feature/shd-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/218-shd-003-shader-parameter-metadata/spec.md`

## Summary

Each SHD-001 material's parameters move from Swift calls to one declarative JSON document (a string
constant next to the shader). A new plain-Swift target `ShaderParameterMetadata` (Compositor package)
reads the documents strictly, validates them (structure, ranges, IDs, enums, slots), checks them against
the shader's slot usage (a scan of the fragment function's `u.slots[i]` reads), maps them to MOD-001
descriptors, and builds an ordered list of generic inspector controls. `ProceduralMaterialCatalog`
builds its definitions from the validated documents; Gradient Field gains the enum Shape. The app's
layer inspector shows a "Material settings" section rendered generically from the control list.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0), Xcode 27.2 (CI also Xcode 26)
**Primary Dependencies**: Foundation (`JSONDecoder`), ParameterGraph (MOD-001), Compositor, Metal (layer only), SwiftUI (app)
**Storage**: none (documents are module constants; scene values already stored by SCN rows)
**Testing**: XCTest — package tests on the host and Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), GPU snapshot on the host GPU, app unit test and one UI test on the "SHD3 iPhone 17" simulator (iOS 27.2)
**Target Platform**: iOS 26+/macOS 15 (package), Linux (package CPU parts)
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: catalog validation once per process (< 5 ms for five documents); no per-frame cost
**Constraints**: data only (Constitution / SHD-011: no code from content); Xcode 26 type-check budget; short tests
**Scale/Scope**: 5 documents, 29 parameters, 5 control kinds

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: Foundation, Metal, SwiftUI only. |
| VI Modular boundaries | Pass: metadata target is plain Swift in Compositor, depends only on ParameterGraph; the app imports it. |
| VII Real-time audio safety | Pass: nothing on audio threads. |
| X Evidence-based quality | Pass: parser/validator unit tests, control-list equality test, GPU golden; device look left `{device}`. |
| SHD-011 / ADR-0024 | Pass: metadata is data decoded by `JSONDecoder`; no evaluation; shader source stays in the reviewed `ProceduralMaterialShaders.swift`. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/218-shd-003-shader-parameter-metadata/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/shader-parameter-metadata.md
└── tasks.md
```

### Source Code

```text
Packages/Compositor/
├── Package.swift                                   # + target ShaderParameterMetadata (+ tests)
├── Sources/ShaderParameterMetadata/
│   ├── ShaderMetadataDocument.swift                # strict JSON value + reader (R1, R2)
│   ├── ShaderMetadataError.swift                   # typed errors with path text
│   ├── ShaderMetadataValidator.swift               # R3; ValidatedShaderMetadata, ShaderParameterSpec
│   ├── ShaderSlotUsage.swift                       # R4 scan + check
│   ├── ShaderMetadataDescriptors.swift             # R5 mapping to ParameterDescriptor
│   └── ShaderParameterControls.swift               # R7 control builder
├── Sources/ProceduralMaterials/
│   ├── MaterialParameterMetadata.swift             # five JSON documents (R1, R6)
│   ├── ProceduralMaterialCatalog.swift             # built from metadata
│   ├── ProceduralMaterialShaders.swift             # gradient Shape (R6)
│   └── ProceduralMaterialLayer.swift               # slot check on prepare (R4)
└── Tests/ShaderParameterMetadataTests/ + ProceduralMaterialsTests/ (updated, + GPU golden)
Apps/projectM-iOS/
├── Coordinators/MaterialInspectorModel.swift       # rows for a material layer (R8)
├── Views/MaterialParametersSection.swift           # generic controls (R8)
├── Views/LayerDetailView.swift                     # one line: the section
├── Tests/MaterialInspectorTests.swift              # S3
└── UITests/MaterialInspectorUITests.swift          # S5
```

**Structure Decision**: a new target in the Compositor package (it already holds ProceduralMaterials and is
Linux-tested in the visual group), so no CI group change.

## Complexity Tracking

None.
