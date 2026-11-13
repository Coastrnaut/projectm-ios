# Implementation Plan: SCN-001 Versioned Scene Format

**Branch**: `feature/scn-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/059-scn-001-versioned-scene-format/spec.md`

## Summary

A new plain-Swift package `Packages/SceneFormat` defines the scene document (format
`projectm-ios.scene`, version 1): an ordered layer list with saved instance IDs, typed per-kind
content and CMP-005 transforms, MOD-001 tagged parameter values, MOD-002 bindings (MOD-003 mapping,
envelope, mix, optional SHD-009 expression), an optional MOD-014 modulation section and an asset
table of store identifiers and embedded text/graph documents. It owns a bounded JSON parser and a
canonical writer (research SCN-001-D1) so decode → encode is byte-identical for canonical input and
unknown content is preserved verbatim. Validation reuses the existing definitions (MOD-001 store
clamping, MOD-002 bind checks, MOD-014 graph validation, SHD-009 compiler, MED-009 and SHD-011
decoders). Adapters capture a live `LayerStack` plus contents, snapshot and bindings as a document
and rebuild them; `LayerStack` gains `init(restoring:)` and the material and generator-graph targets
gain their layer kinds. No app code changes.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the Mac, Xcode 26 in CI: explicit closure types)

**Primary Dependencies**: ParameterGraph (ParameterGraph, ParameterExpression), Compositor
(Compositor, CameraLayer, SpectrumLayers, ImageLayer, VideoLayer, TextLayer, ProceduralMaterials,
GeneratorGraph, GeneratorGraphImport); tests also VisualGenerators (VisualParameters catalog)

**Storage**: none (bytes in, bytes out; files are SCN-002)

**Testing**: XCTest, `swift test` on the Mac host and the Linux shape; Compositor's LayerStack tests

**Target Platform**: iOS 26+ / macOS 15 package, Linux CI

**Project Type**: Swift package (library)

**Performance Goals**: a realistic scene (≤ 10 KiB) decodes, validates and encodes in milliseconds;
the 500-scene property test under 1 s

**Constraints**: ≤ 1 MiB, depth ≤ 32, counts per research SCN-001-D8; no Foundation in the codec
except `Data` at the MED-009/SHD-011 edge; no wall-clock assertions; no C stdio

**Scale/Scope**: 8 layers, 32 bindings, 1,024 parameter values, 16 assets per scene

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pure Swift, no system frameworks beyond Foundation's `Data`. Pass. |
| VI Modular boundaries | Persistence lives in its own package; Compositor and ParameterGraph stay free of it; only the CMP-002 restore initializer and two layer-kind constants are added there. Pass. |
| VII Real-time safety | Not on any real-time path (edit-time only). Pass. |
| IX Dependencies | No third-party dependency. Pass. |
| X Evidence | Unit, property and validation-table tests; no device or simulator claims (no app change). Pass. |
| Security: untrusted input | Size before parsing, depth while parsing, counts before typed decoding, duplicate keys refused, no paths, nothing executed (SHD-011, ADR-0024 rules). Pass. |
| Privacy | No user media in the document (identifiers only), no telemetry. Pass. |

No deviations; Complexity Tracking empty. ADR: a new ADR records the scene format and version
policy (the next free number at commit time).

## Project Structure

### Documentation (this feature)

```text
specs/059-scn-001-versioned-scene-format/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/scene-document.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/SceneFormat/
├── Package.swift
├── Sources/SceneFormat/
│   ├── SceneJSON.swift            # value type, number text
│   ├── SceneJSONParser.swift      # bounded UTF-8 parser (depth, duplicates)
│   ├── SceneJSONWriter.swift      # canonical writer
│   ├── SceneDocument.swift        # model types, constants, limits
│   ├── SceneDecoding.swift        # JSON → model (+ decode warnings), SceneDecodeError
│   ├── SceneEncoding.swift        # model → JSON
│   ├── SceneIssue.swift           # issue type and codes
│   ├── SceneValidation.swift      # validate(registry:assets:)
│   └── SceneLiveState.swift       # capture / liveState adapters
└── Tests/SceneFormatTests/ (fixtures built in code)
Packages/Compositor/Sources/Compositor/LayerStack.swift          # init(restoring:), duplicateLayer
Packages/Compositor/Sources/ProceduralMaterials/MaterialLayerKind.swift
Packages/Compositor/Sources/GeneratorGraph/GeneratorGraphLayerKind.swift
.github/workflows/ios-ci.yml                                     # SceneFormat in the 5 package loops
docs/adr/00NN-scene-document-format.md
docs/test-reports/scene-format.md
```

**Structure Decision**: one package with one library target (the codec is small and every part
needs the same dependencies); tests in one test target.
