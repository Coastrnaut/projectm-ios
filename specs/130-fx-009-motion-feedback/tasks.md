# Tasks: FX-009 Motion Feedback

**Input**: design documents in `specs/130-fx-009-motion-feedback/` (spec, plan, research, data-model,
contracts/motion-feedback.md, quickstart)

**Tests**: requested by the roadmap row (snapshot, shader unit, device GPU) and the spec (FX-009-S1-S8).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute; UI test under 30 s.

Format: `- [ ] FX-009-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac cannot
finish. Logs go to `.autonomous/logs-fx-009/`.

## Phase 1: Setup

- [ ] FX-009-T01 Audit: confirm no frame feedback exists (`grep -rni "feedback\|trail\|echo"` over
  `Packages/*/Sources` and `Apps/projectM-iOS`), that every compositor frame starts from a cleared composite, and
  how scene changes are signalled; record it in spec.md's audit.

## Phase 2: Foundational

- [ ] FX-009-T02 Write `Packages/Compositor/Sources/Compositor/MotionFeedback.swift` (plain Swift): fields, ranges,
  `clamped`, `isActive`, `decay(frameDuration:)` (research FX-009-D2), `limited(by: SafetyClamp)` (D6) and the CPU
  reference `blend(current:previous:decay:reset:)` (D1, D4).
- [ ] FX-009-T03 [P] Write `Packages/Compositor/Tests/CompositorTests/MotionFeedbackModelTests.swift` (CPU, Linux
  shape): half-life fade 0.5 within 1% at 60 and 120 fps from injected durations (FX-009-S2), 0.99 ceiling, zero
  and NaN durations, clamping, Strict ≤ 0.125 s, Reduced ≤ 0.25 s, Reduce flashing ≤ 0.25 s, Custom 0 → off,
  Standard unchanged, blend: reset returns current, max never exceeds the brighter input, premultiplied validity,
  non-finite current passed through, non-finite history ignored.
- [ ] FX-009-T04 Write `Packages/Compositor/Sources/Compositor/MotionFeedbackPass.swift`: `cmp_trails` source, the
  16-byte `TrailsBlock`, the pipeline, the pooled pair (take, swap, return) and the encode helper; wire it into
  `Packages/Compositor/Sources/Compositor/Compositor.swift` after the stack phase (D3), the shown texture for
  `encodeOutput`, the reset points (D4), the CMP-013 rule (D5) and pool return at disable, size change and `deinit`
  (D7).

## Phase 3: User Story 2 - A new scene starts clean (P1, the acceptance)

**Goal**: the first frame after any reset has no prior-scene content. **Independent test**:
`MotionFeedbackCompositeTests`.

- [ ] FX-009-T05 [US2] Write `Packages/Compositor/Tests/CompositorTests/MotionFeedbackCompositeTests.swift` (GPU):
  red scene with Trails on for several frames, then blue; the first new frame is bit-identical to the Trails-off
  blue frame (both output formats) after each trigger: `resetFeedback`, `resetFlashHistory` (visual switch / loop
  start), `resetRenderHealth`, a layer-stack scene change with `resetFeedback` (cue apply, restore), size change,
  output format change, enabling (FX-009-S1); trails rebuild from the new scene only.
- [ ] FX-009-T06 [US2] Reset both scenes in `SceneTransitionBus.show(_:)` and `transition(to:spec:reduceMotion:)`
  (`Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift`); a bus test in
  `MotionFeedbackCompositeTests.swift`: the first frame of a transition carries no trail of the earlier scene.

## Phase 4: User Story 1 - Trails (P1)

- [ ] FX-009-T07 [US1] In `MotionFeedbackCompositeTests.swift`: a trailing frame equals `MotionFeedback.blend` of
  the composite and the previous frame (within half-float rounding) at 60 and 120 fps; a still picture stays
  itself; transparent stays transparent.
- [ ] FX-009-T08 [P] [US1] `Packages/Compositor/Sources/ColorGradeParameters/MotionFeedbackCatalog.swift`
  (`effect.feedback.enabled`, `effect.feedback.halfLife`, D8); tests in
  `Packages/Compositor/Tests/ColorGradeParametersTests/ColorGradeCatalogTests.swift`; register in
  `Apps/projectM-iOS/Coordinators/SceneArchiveService.swift` and
  `Packages/RenderGoldens/Sources/SceneRenderHarness/GoldenSceneRenderer.swift`.

## Phase 5: User Story 3 - Off is exactly today (P1)

- [ ] FX-009-T09 [US3] In `MotionFeedbackCompositeTests.swift`: Trails off is bit-identical to a compositor that
  never had Trails, holds no picture, runs no pass; enable → disable returns both pictures; CMP-013 never reuses
  the composite while on and reuses it as before when off (FX-009-S4); pool checkouts return to the start after
  many enable/disable/size cycles (FX-009-S6). RenderGoldens unchanged (FX-009-S3).
- [ ] FX-009-T10 [US3] GPU timing on the Mac (bench test, not asserted): 1170 × 2532, 120 frames with and without
  Trails; record in research FX-009-D10 and the ADR (FX-009-S8).

## Phase 6: User Story 4 - Safety (P1)

- [ ] FX-009-T11 [US4] In `MotionFeedbackCompositeTests.swift`: a red/black strobe at 30 Hz with Trails on (and on
  Strict-capped trails) still makes the flash guard lower its gain below 1 (FX-009-S5).

## Phase 7: App

- [ ] FX-009-T12 `Apps/projectM-iOS/Coordinators/MotionFeedbackSetting.swift` (keys, read rule, `effective(clamp:)`,
  readout "0.20 s"); keys in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift` and
  `scripts/run_device_tests.py`; the UI-test reset in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`.
- [ ] FX-009-T13 `Apps/projectM-iOS/Coordinators/AppCoordinator+MotionFeedback.swift` (`applyMotionFeedback`,
  `resetTrailsHistory`); wiring in `AppCoordinator.swift` (property, init, onChange, the four prepare paths,
  `applyReduceFlashing`), `AppCoordinator+Show.swift` (cue apply), `AppCoordinator+SceneHistory.swift` (undo/redo),
  `finishReopen` (reopen).
- [ ] FX-009-T14 Settings → Trails: `Apps/projectM-iOS/Views/TrailsSection.swift` (toggle, ACC-005 Length slider,
  readout, help) in `mediaSections` of `Apps/projectM-iOS/Views/SettingsView.swift`, passed from
  `Apps/projectM-iOS/Views/VisualizerView.swift`.
- [ ] FX-009-T15 App tests: `Apps/projectM-iOS/Tests/MotionFeedbackSettingTests.swift` (persistence, read rule,
  caps, readout, spoken value, the coordinator pushing the effective value and resetting history) and the backup /
  erase key tests (`LibraryBackupAppTests`, `LibraryEraseAppTests`); `Apps/projectM-iOS/UITests/TrailsUITests.swift`
  (toggle on shows the Length slider, value survives relaunch). FILE-011's Settings erase category derives from
  `LibrarySettingsPolicy.includedKeys`, so `LibraryEraseAppTests` must list `MotionFeedbackSetting.allKeys` too.

## Phase 8: Polish

- [ ] FX-009-T16 ADR `docs/adr/0051-motion-feedback-trails.md` (placement, blend, decay, reset rule, cache, safety)
  and the ADR index; spec status.
- [ ] FX-009-T17 Gates: `check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`,
  `check_status_events`, `test_scripts`; Compositor, RenderGoldens and LibraryBackup package suites; app unit and
  `TrailsUITests` on an own simulator; long-body warnings in the changed SwiftUI files.
- [ ] FX-009-T18 `{device}` On D1 (and D2 at 120 Hz): Trails on in the Camera or Photo visual, cue step shows no ghost,
  frame rate with and without Trails recorded in `docs/test-reports/performance.md`.

## Dependencies

T02 → T03, T04 → T05-T07, T09-T11; T08 independent; T12 → T13 → T14 → T15; T16-T17 last; T18 after integration.
