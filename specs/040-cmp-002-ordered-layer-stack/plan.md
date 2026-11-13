# Implementation Plan: CMP-002 Ordered Layer Stack

**Branch**: `feature/cmp-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/040-cmp-002-ordered-layer-stack/spec.md`

## Summary

Add a value-type `LayerStack` to the `Compositor` target (CPU, builds on Linux): ordered entries,
index 0 the bottom, each with a stable `LayerInstanceID`, a `LayerDescriptor` (a `LayerKind` plus
numeric parameters) and `LayerCompositeSettings`; operations add-at-index, remove, duplicate
(directly above, new ID), move, with typed `LayerStackError`s, a limit of 8 layers and per-kind
instance limits (the camera kind: 1). The Metal `Compositor` gains `init(device:)` and
`apply(_:makeLayer:)`: between frames it keeps the layer object, pictures and slots of every ID
still present, creates new IDs through the caller's factory and prepares them at the current size
(the CMP-001 allocation points: prepare and resize), releases removed IDs, is atomic on error and a
no-op for an equal stack. Its per-layer state moves into one record per layer so a reorder is a
permutation. The Camera visual builds its fixed camera + circular spectrum stack through
`LayerStack` with unchanged behaviour. Tests: CPU stack tests (also in the Linux shape) and GPU
tests at 64 × 64: the acceptance red/blue swap, reuse and preparation counts, release, a 60-frame
steady loop with no picture creation. The 4-layer per-layer frame cost on D1-D3 is a `{device}`
task left open. The decision is recorded as a CMP-002 amendment to ADR-0013 (no new ADR number:
it extends CMP-001's compositor decision, and SHD-002 may claim 0019 in parallel).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI).

**Primary Dependencies**: Compositor (CMP-001), Metal; CameraLayer and SpectrumLayers declare
their kinds. No `Package.swift` change.

**Storage**: N/A (the stack is a value; saving belongs to scene rows).

**Testing**: XCTest via `swift test --package-path Packages/Compositor` (Mac host),
`-Xswiftc -DCOMPOSITOR_NO_METAL -Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE
--scratch-path .build/linuxshape` (Linux shape), `xcodebuild test -scheme Compositor` on an iOS
27.2 simulator; app tests `projectM-iOSTests`, `CameraUITests`, `CameraPrivacyStatusUITests`.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for tests, Linux for the CPU part.

**Project Type**: Swift package library (mobile app module) plus a small app change.

**Performance Goals**: `apply` runs between frames and allocates only for new layers; the frame
loop allocates nothing new (CMP-001-R9). Device per-layer frame cost: CMP-002-T15 `{device}`.

**Constraints**: Public Apple APIs; no wall-clock assertions; owner rule 7 test budgets; explicit
closure types for Xcode 26; one thread drives a compositor (not Sendable).

**Scale/Scope**: ≤ 8 layers; about 350 lines of source, 400 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Metal only; no new API | Pass |
| VI. Modular boundaries | The stack lives in Compositor (no projectM, ANGLE, capture or app imports); kinds are declared by the layer targets; the app maps kinds to live layers | Pass |
| VII. Real-time audio safety | No audio-path change | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Host, Linux-shape and simulator tests only; device cost is an open `{device}` task | Pass |
| Privacy (CAM-001, CAM-012) | The camera kind is limited to one instance: never a second capture session; the indicator and Stop camera stay on the one camera layer | Pass |
| Flash safety (ADR-0011, ADR-0013 decision 6) | Stack edits never reset the composite guard's history (CMP-002-R14) | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/040-cmp-002-ordered-layer-stack/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/layer-stack.md
└── checklists/requirements.md
docs/adr/0013-compositor-layer-protocol.md   # + "Amendment: CMP-002 ordered layer stack"
```

### Source Code (repository root)

```text
Packages/Compositor/
├── Sources/Compositor/
│   ├── LayerStack.swift            # NEW (CPU): LayerInstanceID, LayerKind, LayerDescriptor, LayerStackEntry, LayerStackError, LayerStack
│   └── Compositor.swift            # per-layer records; init(device:); apply(_:makeLayer:); appliedStack; layerID(at:); layerPreparations
├── Sources/CameraLayer/CameraLayerKind.swift        # NEW (CPU): LayerKind.camera (maximumInstances 1)
├── Sources/SpectrumLayers/SpectrumLayerKinds.swift  # NEW (CPU): LayerKind.circularSpectrum, .linearSpectrum
└── Tests/CompositorTests/
    ├── LayerStackTests.swift       # NEW (CPU, Linux too)
    └── LayerStackApplyTests.swift  # NEW (GPU 64 × 64)
Apps/projectM-iOS/Visuals/CameraVisualHost.swift     # builds its stack through LayerStack
```

**Structure Decision**: the stack is part of the `Compositor` target because the compositor
applies it and every layer target already depends on it; kinds are declared next to the layers
that implement them, so Compositor never names a camera or spectrum. `Package.swift` is not
touched (SHD-002 edits it in parallel). `ProceduralMaterials` kinds are left to the row that puts
materials in a stack (SHD-002 is editing that target now); the factory takes any kind.

## Complexity Tracking

None: no constitution violations.
