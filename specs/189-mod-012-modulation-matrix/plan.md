# Implementation Plan: MOD-012 Modulation Matrix UI

**Branch**: `feature/mod-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/189-mod-012-modulation-matrix/spec.md`

## Summary

A Settings → Modulation screen lists every binding grouped by destination in fold order, toggles a layer on or
off, reorders layers within one destination and inspects one route; each change is one undo step and is autosaved.

- **ParameterGraph**: `AudioFeatureBinding.isEnabled` (default true). `AudioFeatureModulator`: the fold skips
  disabled layers; no enabled layer → the base exactly; `setEnabled(_:for:layer:)` and
  `moveLayer(of:from:to:)` in place (signals kept); `replaceBindings(_:)` (validated, all or nothing).
  `ModulationRouteList` (new, pure): the same two edits on a `[AudioFeatureBinding]` list and the
  destination grouping (research MOD-012-D1 to D3).
- **SceneFormat**: optional `enabled` field on `$.bindings` entries, written only when false (MOD-012-D4).
- **App**:
  - `ModulationMatrixCoordinator` (observable): the route mirror, the two edits, `restore(_:)` for undo, the
    rows and their text (MOD-012-D5).
  - `SceneInputs.bindings`, so each edit is a SCN-010 step ("Turn Off …", "Reorder …"); capture prefers it.
  - `NativeSpectrumHost`: forwards the in-place edits; `SceneAutosaveCoordinator.replaceCarriedBindings`.
  - Views: `ModulationMatrixView` (sections, switches, Edit mode, VoiceOver move actions, read-only triggers
    and macros), `ModulationRouteDetailView` (curve preview, envelope, 10 Hz live values, Inspect button).
  - The inspector marks a disabled layer "(off)". DEBUG seed `-uitestSeedModulationMatrix` and a probe.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new.

**Storage**: the scene document only (`enabled` optional field); no UserDefaults key.

**Testing**: XCTest. ParameterGraph and SceneFormat on the host (Linux in CI); app unit tests and one UI test
on the private simulator "MOD12 iPhone 17" (iOS 27.2).

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: per frame unchanged: ≤ 32 slots, ≤ 4 steps per parameter, no allocation.

**Constraints**: all-enabled results bit-identical to MOD-011; type-check budget (small SwiftUI bodies).

**Scale/Scope**: ≤ 32 routes, ≤ 4 per destination.

## Constitution Check

- I Public APIs only: SwiftUI, Foundation. Pass.
- VI Modular boundaries: evaluation and list edits in ParameterGraph, storage in SceneFormat, UI in the app. Pass.
- VII Real-time audio safety: edits happen on the main actor between frames; the frame path stays allocation-free. Pass.
- X Evidence-based quality: exact acceptance values, bit identity of untouched routes. Pass.
- Sensory safety (ACC-012): unchanged; the clamp still applies last to whatever the fold gives. Pass.

## Project Structure

```text
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureBinding.swift, AudioFeatureModulator.swift
Packages/ParameterGraph/Sources/ParameterGraph/ModulationRouteList.swift                      (new)
Packages/ParameterGraph/Tests/ParameterGraphTests/ModulationMatrixTests.swift                  (new)
Packages/SceneFormat/Sources/SceneFormat/SceneDocument.swift, SceneEncoding.swift, SceneDecoding.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneBindingEnabledTests.swift                    (new)
Apps/projectM-iOS/Coordinators/ModulationMatrixCoordinator.swift                              (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+ModulationMatrix.swift                          (new)
Apps/projectM-iOS/Coordinators/SceneAutosaveCapture.swift, SceneAutosaveCoordinator.swift, SceneHistoryCoordinator.swift
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, AppCoordinator+SceneHistory.swift, ParameterInspectorModel.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/ModulationMatrixView.swift, ModulationRouteDetailView.swift            (new)
Apps/projectM-iOS/Views/SettingsView.swift (one row)
Apps/projectM-iOS/Debug/UITestModulationMatrixFixture.swift                                   (new)
Apps/projectM-iOS/Tests/ModulationMatrixAppTests.swift                                        (new)
Apps/projectM-iOS/UITests/ModulationMatrixUITests.swift                                       (new)
```

## Complexity Tracking

None. No ADR: the enabled flag is an additive optional field and the fold order of ADR-0057 is unchanged
(a disabled layer is simply not in the fold).
