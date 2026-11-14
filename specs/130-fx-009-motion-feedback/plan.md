# Implementation Plan: FX-009 Motion Feedback

**Branch**: `feature/fx-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add "Trails" to the compositor: after the stack phase, one full-screen pass `cmp_trails` writes
`max(composite, decay × previous)` (per channel, premultiplied; research FX-009-D1) into a pooled ping-pong pair at
composite size, and that frame goes on to FX-019's guard, FX-003's grade, FX-002's tone map and every output (D3).
The decay comes from a half-life in seconds and the frame clock's duration, `min(0.5^(Δt/h), 0.99)` (D2). A reset
flag makes the next frame write the composite unchanged (bit-identical to Trails off) and restarts the history (D4);
it is raised by `resetFeedback()`, `resetFlashHistory()` (every visual loop start: visual switch, resume),
`resetRenderHealth()`, size and output-format changes, enabling, unfinished frames, the transition bus's cut and
transition start, and in the app by show cue apply, scene reopen and undo/redo. CMP-013 never reuses the composite
while Trails are active (D5). ACC-012 caps the half-life (limit × 0.5 s; ≤ 0.25 s with Reduce flashing) (D6).
Inactive Trails hold no texture and add no pass, so output is bit-identical to today.

App: `MotionFeedbackSetting` (two UserDefaults keys), a Settings → Trails section (toggle, ACC-005 Length slider,
help), the keys in FILE-005's backup policy, the privacy allow-list and the UI-test reset, MOD-001 IDs
`effect.feedback.enabled` / `effect.feedback.halfLife`, and the effective value pushed to the Camera, Photo, Video
and Text compositors. ADR-0051 (feedback placement and reset rule).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), FlashSafety (`SafetyClamp`), ParameterGraph
(MOD-001), SwiftUI
**Storage**: two UserDefaults keys (`settings.feedback.enabled`, `settings.feedback.halfLife`)
**Testing**: XCTest. Compositor: `MotionFeedbackModelTests` (CPU, Linux shape: decay at 60/120 fps, caps, blend
reference), `MotionFeedbackCompositeTests` (GPU: reset per trigger, trailing vs reference, off identity, cache, pool,
guard, bus, timing). Catalog: `ColorGradeCatalogTests` (feedback descriptors). App: `MotionFeedbackSettingTests`,
backup/erase key tests, `TrailsUITests`. Regressions: RenderGoldens, LibraryBackup, scripts
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen read-read-write pass at composite size, two
pooled textures, no per-frame allocation; GPU time measured on the Mac (D10)
**Constraints**: inactive bit-identical; explicit closure types; small focused edits to `Compositor.swift` and
`AppCoordinator.swift` (MED-010 and a cleanup agent edit them in parallel); SwiftUI bodies small
(`-warn-long-function-bodies=300`, `-warn-long-expression-type-checking=150`); unit tests ≤ 10 s, suite < 1 min
**Scale/Scope**: ~6 edited source files, ~6 new files, ADR-0051

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal render encoders, run-time source compile; SwiftUI | Pass |
| VI Modular boundaries | Model and shader in `Packages/Compositor`; catalog in `ColorGradeParameters`; app sets a value | Pass |
| VII Real-time safety | GPU only; decay computed once per frame on the CPU; 16-byte `setFragmentBytes`; no per-frame allocation | Pass |
| VIII Upstream fidelity | Off is bit-identical; projectM untouched | Pass |
| X Evidence | Model and GPU tests on the Mac; device GPU check is `{device}` | Pass |
| Photosensitivity (FX-019, ACC-012) | Guard measures the trails frame; profile and Reduce flashing cap the length; max blend never brightens | Pass |
| Privacy | Two settings on the device, allow-listed; nothing sent | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

```text
specs/130-fx-009-motion-feedback/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/motion-feedback.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/MotionFeedback.swift              (new: value, decay, caps, reference blend)
Packages/Compositor/Sources/Compositor/MotionFeedbackPass.swift          (new: cmp_trails source, pass, pooled pair)
Packages/Compositor/Sources/Compositor/Compositor.swift                  (hook after the stack, resets, cache rule)
Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift          (reset on cut and transition start)
Packages/Compositor/Sources/ColorGradeParameters/MotionFeedbackCatalog.swift (new: MOD-001 descriptors)
Packages/Compositor/Tests/CompositorTests/MotionFeedbackModelTests.swift (new, CPU)
Packages/Compositor/Tests/CompositorTests/MotionFeedbackCompositeTests.swift (new, GPU)
Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift
Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift (registry)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py (keys)
Apps/projectM-iOS/Coordinators/MotionFeedbackSetting.swift               (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+MotionFeedback.swift       (new: apply and reset helpers)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift, +Show.swift, +SceneHistory.swift, SceneArchiveService.swift
Apps/projectM-iOS/Views/TrailsSection.swift (new), Views/SettingsView.swift, Views/VisualizerView.swift
Apps/projectM-iOS/Tests/MotionFeedbackSettingTests.swift (new), UITests/TrailsUITests.swift (new)
docs/adr/0051-motion-feedback-trails.md                                  (new)
```

**Structure Decision**: the pass lives in its own file with an extension on `Compositor` holding the encode helper;
`Compositor.swift` gets only the stored state, a call after the stack phase and the reset points.

## Complexity Tracking

None.
