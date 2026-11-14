# Implementation Plan: MOD-011 Modulation Mix Modes

**Branch**: `feature/mod-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/178-mod-011-mix-modes/spec.md`

## Summary

Several bindings may now act on one parameter, folded in binding list order with MOD-002's formulas and a
clamp after every step; the order is one documented contract (ADR, code, inspector):

- **ParameterGraph**: `ModulationMixOrder.swift` (new): the pure order, `step(_:mapped:mode:minimum:maximum:)`
  (one mix step, non-finite → running value, clamp) and `fold`. `AudioFeatureModulator`: up to
  `maximumBindingsPerTarget` = 4 layers per parameter; `addLayer(_:)` appends one (new error
  `tooManyLayers`), `bind(_:)` keeps MOD-002's meaning (one binding, in the first one's place), `unbind`
  removes all layers, `bindings(for:)`, `layerCount(for:)`, `setEnvelope(_:for:layer:)`; `value(for:manual:)`
  folds the target's layers; integer rounding once at the end (research MOD-011-D1 to D4).
- **VisualParameters** (VisualGenerators package): `GlowModulationOrder.resolve(base:modulator:clamp:)`, the
  glow's whole order after the base: modulation fold, then ACC-012 excursion scaling, then the intensity cap.
  The app host calls it, so the full order is tested on Linux (research MOD-011-D5).
- **SceneFormat**: restore applies up to 4 bindings per parameter in document order (`addLayer`); a fifth, or
  an expression on a later layer, is `duplicateBindingTarget` (kept verbatim). `SceneBinding.list(_:expressions:)`
  writes a parameter's expression on its first binding only, used by both capture paths (research MOD-011-D6).
- **App**: `NativeSpectrumHost` uses `GlowModulationOrder`, adds `addLayer`; scene restore adds layers in
  order; the inspector numbers layered bindings and shows the order line (research MOD-011-D7).
- **ADR** (next free number): the order contract, since it changes the one-binding-per-parameter default.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new (VisualParameters gains a direct dependency on the in-repo FlashSafety).

**Storage**: the scene document only; no format version change; no UserDefaults key.

**Testing**: XCTest. ParameterGraph, VisualGenerators and SceneFormat on the host (Linux in CI); app unit
tests on the private simulator "MOD11 iPhone 17" (iOS 27.2).

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: per frame, ≤ 32 slots scanned and ≤ 4 mix steps per parameter; no allocation.

**Constraints**: single-binding results bit-identical to MOD-002; type-check budget.

**Scale/Scope**: ≤ 4 layers per parameter, ≤ 32 bindings.

## Constitution Check

- I Public APIs only: Foundation. Pass.
- VI Modular boundaries: order in ParameterGraph, glow order in VisualParameters, persistence in SceneFormat. Pass.
- VII Real-time audio safety: frame path only (main actor), allocation-free, never on an audio callback. Pass.
- X Evidence-based quality: table-driven acceptance with exact values; a bit-identity grid. Pass.
- Sensory safety (FR-072, ACC-012): the clamp stays last and is tested last. Pass.

## Project Structure

```text
Packages/ParameterGraph/Sources/ParameterGraph/ModulationMixOrder.swift        (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureModulator.swift
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift      (error case)
Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMixOrderTests.swift (new)
Packages/VisualGenerators/Package.swift
Packages/VisualGenerators/Sources/VisualParameters/GlowModulationOrder.swift   (new)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/GlowModulationOrderTests.swift (new)
Packages/SceneFormat/Sources/SceneFormat/SceneModulationRestore.swift, SceneDocument.swift, SceneLiveState.swift
Packages/SceneFormat/Tests/SceneFormatTests/ (restore and validation updates, layered round trip)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Coordinators/AppCoordinator.swift,
Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift, ParameterInspectorModel.swift
Apps/projectM-iOS/Tests/ModulationMixOrderAppTests.swift (new)
docs/adr/00NN-modulation-mix-order.md (new)
```

## Complexity Tracking

None.
