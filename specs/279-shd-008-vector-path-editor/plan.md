# Implementation Plan: SHD-008 Vector Path Editor

**Branch**: `feature/shd-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A pure, validated `VectorPath` (closed polygon, 3…32 points in the unit square) lives in VisualGenerators
(the lowest package both users reach). It is used as a new CMP-007 mask shape `.path`, rasterised by the
existing polygon shader kind (no shader change), saved in `composite.mask` with `"shape": "path"`; and as a
new SHD-007 spawn shape `.path`, sampled uniformly inside by a precomputed triangulation. A pure
`VectorPathDraft` editing model refuses invalid edits; a SwiftUI `VectorPathEditorView` (handles as in
OUT-007's corner pin) opens from the layer inspector's mask section and the emitter editor's spawn section.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); CI also Xcode 26 (type-check budget)
**Primary Dependencies**: VisualGenerators, Compositor, SceneFormat packages; SwiftUI app
**Storage**: scenes (`composite.mask`), UserDefaults `settings.particleFountain.emitter` (existing key)
**Testing**: XCTest (packages on host and Linux shape; app tests and one UI test on "SHD8 iPhone 17")
**Target Platform**: iOS 26+/27
**Performance Goals**: validation O(n²) for n ≤ 32 (≤ 496 edge pairs); spawning allocation-free
**Constraints**: no new UserDefaults keys; no shader change; Linux builds (no Apple-only API in the model)
**Scale/Scope**: ~6 new source files, small hooks in LayerMask, SceneDecoding/Encoding, emitter settings,
fountain simulation, LayerInspectorModel, LayerDetailView, ParticleEmitterEditorView

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI, Metal through the existing compositor |
| VI Modular boundaries | Pass: model in a package, UI in the app |
| VII Real-time safety | Pass: triangulation precomputed; spawn draws allocate nothing |
| X Evidence-based quality | Pass: pure, GPU, simulation, app and UI tests; one `{device}` task left open |
| SHD-011 (parameters only) | Pass: a path is numbers only |
| Privacy | Pass: no new storage keys, nothing leaves the device |

Re-checked after design: unchanged.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/VectorPath.swift          (new: model, validation, triangulation, sampling)
Packages/VisualGenerators/Sources/VisualGenerators/VectorPathDraft.swift     (new: editing model)
Packages/VisualGenerators/Sources/VisualGenerators/ParticleEmitterSettings.swift (hook: .path shape, path field)
Packages/VisualGenerators/Sources/VisualGenerators/ParticleFountainSimulation.swift (hook: one case)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/VectorPathTests.swift   (new)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/VectorPathEmitterTests.swift (new)
Packages/Compositor/Sources/Compositor/LayerMask.swift                        (hook: .path shape)
Packages/Compositor/Tests/CompositorTests/LayerPathMaskTests.swift            (new: GPU coverage)
Packages/SceneFormat/Sources/SceneFormat/SceneDecoding.swift, SceneEncoding.swift (hook: "path")
Packages/SceneFormat/Tests/SceneFormatTests/ScenePathMaskTests.swift          (new)
Apps/projectM-iOS/Views/VectorPathEditorView.swift                            (new)
Apps/projectM-iOS/Coordinators/LayerInspectorModel.swift, LayerInspectorCoordinator.swift, Views/LayerDetailView.swift (hooks)
Apps/projectM-iOS/Views/ParticleEmitterEditorView.swift                       (hook)
Apps/projectM-iOS/Tests/VectorPathEditorTests.swift                           (new)
Apps/projectM-iOS/UITests/VectorPathEditorUITests.swift                       (new)
```

**Structure Decision**: existing packages and app; no new package (so no CI group change).

## Complexity Tracking

None.
