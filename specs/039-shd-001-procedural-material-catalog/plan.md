# Implementation Plan: SHD-001 Procedural Material Catalog

**Branch**: `feature/shd-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/039-shd-001-procedural-material-catalog/spec.md`

## Summary

Add a `ProceduralMaterials` target to `Packages/Compositor`: a catalog of five curated materials
(Gradient Field, Plasma, Noise Flow, Ring Tunnel, Starfield), each described by a
`MaterialDefinition` whose parameters are MOD-001 `ParameterDescriptor`s (`material.<name>.<param>`)
and drawn by `ProceduralMaterialLayer`, a CMP-001 `LayerSource`. Shader source is one Swift string
constant in the module, compiled with `makeLibrary(source:)` when a layer is prepared (ADR-0009
decision 3: no Metal Toolchain on the build Mac), never from any other input; a source-scan test
enforces this. Motion is an accumulated phase advanced by the compositor's clamped frame duration,
with music changing only speed through a slew-limited band level. Tests: CPU catalog, values,
motion and source-scan tests (Linux too); GPU tests at 64 × 64 for load, validity, determinism,
extremes, golden signatures and the FlashSafety envelope. The frame-cost measurement on D1-D3 is a
`{device}` task left open. ADR-0018 records the shader-library and safety decision (number checked
again at commit time).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI), Metal
Shading Language compiled at run time from a constant.

**Primary Dependencies**: Compositor (CMP-001 contract), ParameterGraph (MOD-001), Metal; tests
add FlashSafety (FX-019 analysis).

**Storage**: N/A (values live in memory; persistence is a scene row's job).

**Testing**: XCTest via `swift test --package-path Packages/Compositor` on the Mac host,
`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`
for the Linux shape, and `xcodebuild test -scheme Compositor` on an iOS 27.2 simulator.

**Target Platform**: iOS/iPadOS 26+ (package platforms), macOS 15 host for tests, Linux for the
CPU part.

**Project Type**: Swift package library target (mobile app module).

**Performance Goals**: One full-screen fragment pass per material per frame; no allocation in
`render` beyond the per-frame render-pass descriptor CMP-001 layers already use. Device frame
cost recorded by SHD-001-T19 `{device}`.

**Constraints**: Public Apple APIs only; no networking or file reads; no wall clock; output
deterministic; parameters bounded; tests within owner rule 7 (unit ≤ 10 s, suite < 1 min).

**Scale/Scope**: 5 materials, 28 parameters, about 900 lines of source and 700 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal only (`makeLibrary(source:options:)`, render pipeline, `setFragmentBytes`); no `dlopen`/`dlsym` | Pass |
| VI. Modular boundaries | The target imports Compositor, ParameterGraph and Metal; no projectM, ANGLE, capture or app code | Pass |
| VII. Real-time audio safety | Reads the audio context's band values on the compositor thread only; never touches the audio path | Pass |
| VIII. Upstream fidelity | projectM untouched; materials draw beside it as layers (ADR-0008 decision 5) | Pass |
| X. Evidence | Simulator and host tests only; frame cost is a `{device}` task left open; golden values on the same GPU class | Pass |
| Security (untrusted input) | No shader is built from user text, files or downloads (SHD-001-R7, R8); a material is chosen only from the fixed catalog | Pass |
| Privacy | No data stored, sent or analysed | Pass |
| FR-068 (no networking) | No networking API; the source scan also rejects `URL`/`URLSession` | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Materials draw under the composite flash guard; bounded speeds and brightness; defaults tested against the Reduce flashing envelope | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/039-shd-001-procedural-material-catalog/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/material-catalog.md
└── checklists/requirements.md
docs/adr/0018-procedural-material-shaders.md   (number re-checked at commit)
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Package.swift                              # + ParameterGraph dependency, ProceduralMaterials target and tests
├── Sources/ProceduralMaterials/
│   ├── MaterialDefinition.swift               # MaterialKind, MaterialDefinition, slot rules (CPU)
│   ├── ProceduralMaterialCatalog.swift        # the five materials, registry, lookup, defaults (CPU)
│   ├── MaterialParameterValues.swift          # clamped values and uniform slots (CPU)
│   ├── MaterialMotion.swift                   # phase and slew-limited audio level (CPU)
│   ├── ProceduralMaterialShaders.swift        # the shader constant and the only library compile (Metal)
│   └── ProceduralMaterialLayer.swift          # the LayerSource and the factory (Metal)
└── Tests/ProceduralMaterialsTests/
    ├── MaterialCatalogTests.swift             # CPU
    ├── MaterialParameterValuesTests.swift     # CPU
    ├── MaterialMotionTests.swift              # CPU
    ├── MaterialSourceSafetyTests.swift        # CPU static scan
    ├── MaterialGPURig.swift                   # Metal helpers
    ├── MaterialRenderTests.swift              # GPU: load, validity, determinism, extremes, golden
    └── MaterialFlashSafetyTests.swift         # GPU: FX-019 envelope
```

**Structure Decision**: a target in the Compositor package, like `CameraLayer` (CAM-001): the
materials are layers, the package's one library product already makes CI's `-scheme Compositor`
build and test every target, and the five CI package loops need no change. A separate package was
rejected: it would duplicate the CI wiring for a target that only depends on Compositor and
ParameterGraph. Adding ParameterGraph (pure Swift, no dependencies) to Compositor keeps the Linux
build.

## Complexity Tracking

None: no constitution violations.
