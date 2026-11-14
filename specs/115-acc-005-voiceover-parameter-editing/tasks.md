# Tasks: ACC-005 VoiceOver Parameter Editing

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/accessible-parameters.md](contracts/accessible-parameters.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap row (accessibility unit and UI tests). Budgets (owner rule 7): unit
test about 1–2 s, at most 10 s; UI test under 30 s. Tick a task `[X]` only when verified, with
" — Verified <date>: <how>".

## Phase 1: Setup

- [X] ACC-005-T01 Add `AnnouncementKind.parameter` (end-of-range lane) in Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift and add `Views/AccessibleParameter.swift` to the checked files in scripts/check_status_events.py — Verified 2026-11-14: `AnnouncementKind.parameter` used by `testABurstOfEndSwipesIsAnnouncedOnce` (passed); `check_status_events.py` OK with `Views/AccessibleParameter.swift` in its list

## Phase 2: Foundational (pure core, blocks every story)

- [X] ACC-005-T02 Create Apps/projectM-iOS/Views/AccessibleParameter.swift with `SpokenUnit`, `SpokenValueFormatter` (exact strings of contract C1.2, typed steps, no `+` chains with ternaries in modifiers), `AccessibleParameterSpec` ("step > 0", `withRange(_:)`), `ParameterStepper` (grid from the minimum, research D3; clamp; end flag) and `ParameterTarget` — Verified 2026-11-14: AccessibleParameterTests `testSpokenValuesNameTheirUnit`, `testStepsFollowTheGridFromTheMinimum`, `testValuesClampAndEndsAreReported` passed (projectM-iOSTests, own iOS 27.2 simulator)
- [X] ACC-005-T03 Add `AccessibleParameterCatalog` with the ten specs of data-model.md in Apps/projectM-iOS/Views/AccessibleParameter.swift; glow range, unit and step hint read from `VisualParameterCatalog.descriptors` (registry hint × 5) — Verified 2026-11-14: `testCatalogFollowsTheRegistryAndKeepsIdentifiers` passed (glow range and hint read from `VisualParameterCatalog`, step = hint × 5)
- [X] ACC-005-T04 [P] Unit tests for the formatter (each unit, signs, singular), the stepper (on-grid ±1 step, off-grid to the next grid value, clamp at both ends, maximum reachable off-grid) and the catalog (glow steps are whole multiples of the registry hint; every spec without its own snapping step spans at most 25 steps; identifiers and labels equal the existing ones, R9) in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift — Verified 2026-11-14: 7 AccessibleParameterTests passed in 0.03 s

## Phase 3: User Story 1 — change a setting with VoiceOver swipes (P1) 🎯 MVP

**Independent test**: one increment and one decrement on each control change the stored value by one step and persist.

- [X] ACC-005-T05 [US1] Add the `.accessibleParameter(_:value:set:didStep:)` modifier and the `\.parameterAnnouncer` environment value in Apps/projectM-iOS/Views/AccessibleParameter.swift (contract C1.1; disabled views are not adjusted) — Verified 2026-11-14: VoiceOverParameterUITests passed (25.2 s): the accessibility increment on the glow intensity moved 50 % → "55 percent"; research D1 revised: the modifier makes one element of its own because the platform `UISlider`'s increment ignored the action
- [X] ACC-005-T06 [US1] Glow and text sliders: `glowSlider` takes a spec and a target and uses the modifier; each step ends undo coalescing; SettingsView gains `announcer` and puts it in the environment, in Apps/projectM-iOS/Views/SettingsView.swift; pass `announcer: coordinator.announcer` in `withPresentations` of Apps/projectM-iOS/Views/VisualizerView.swift (not `body`) — Verified 2026-11-14: glow and text sliders use the modifier with `SettingsView.glowTarget`/`textTarget`; table test and GlowUITests (2), SceneUndoUITests passed; SettingsView gets `announcer` from `withPresentations` (VisualizerView.body untouched)
- [X] ACC-005-T07 [P] [US1] Input trim and gate threshold use the modifier with `InputTrimSection.target(_:)` / `NoiseGateSection.target(_:)` in Apps/projectM-iOS/Views/InputTrimSection.swift and Apps/projectM-iOS/Views/NoiseGateSection.swift — Verified 2026-11-14: table test rows inputTrimSlider and noiseGateThresholdSlider passed; InputTrimUITests and NoiseGateUITests passed
- [X] ACC-005-T08 [P] [US1] Visual delay uses the modifier with `LatencyOffsetSection.target(_:mode:)` (the picked source only) in Apps/projectM-iOS/Views/LatencyOffsetSection.swift — Verified 2026-11-14: table test row latencyOffsetSlider and `testDelayStepsOnlyThePickedSourceAndReachesTheActiveControl` passed; LatencyOffsetUITests passed
- [X] ACC-005-T09 [P] [US1] Loop in and out use the modifier with the duration as the range's upper bound and `VideoLoopControls.inTarget(_:)` / `outTarget(_:)`; a step commits the loop (player and undo) in Apps/projectM-iOS/Views/VideoLoopControls.swift — Verified 2026-11-14: table test rows videoLoopIn/videoLoopOut passed (stored region moved 0.1 s and read back by a fresh coordinator); VideoLoopUITests passed
- [X] ACC-005-T10 [US1] Table test over all ten controls: through each section's own target, one increment and one decrement change the real setting by exactly one step, and a fresh setting on the same UserDefaults suite reads the stepped value (persisted) in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift — Verified 2026-11-14: `testEveryControlStepsTheRealSettingByOneStepAndPersists` passed: 10 of 10 controls, +1 and −1 step each, persisted
- [X] ACC-005-T11 [US1] UI test `VoiceOverParameterUITests` (accessibility increment and decrement through the DEBUG probe, research D2): increment on the glow intensity (50 % → "55 percent"), decrement on the input trim ("minus 1 decibel"), relaunch, both kept, in Apps/projectM-iOS/UITests/VoiceOverParameterUITests.swift — Verified 2026-11-14: VoiceOverParameterUITests passed in 25.2 s (glow 55 percent, trim minus 1 decibel then plus 1 decibel, both kept after relaunch)

## Phase 4: User Story 2 — values with units (P1)

**Independent test**: each slider's accessibility value is its number with the spelled unit.

- [X] ACC-005-T12 [US2] Update the existing slider UI tests to the spoken values (visible readouts unchanged) in Apps/projectM-iOS/UITests/InputTrimUITests.swift, LatencyOffsetUITests.swift, GlowUITests.swift and any other suite that reads a slider value — Verified 2026-11-14: GlowUITests, InputTrimUITests, LatencyOffsetUITests, SceneUndoUITests updated to the spoken values and to `app.slider`/`dragSlider` (UITestSliders.swift); all passed

## Phase 5: User Story 3 — ends announced (P2)

**Independent test**: a burst of increments at the maximum yields one announcement.

- [X] ACC-005-T13 [US3] Unit test: an `AccessibilityAnnouncer` with a fake clock receives ten end texts within one second and speaks once; the end text is "Maximum, 250 milliseconds" for the delay at 250 ms, in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift — Verified 2026-11-14: `testABurstOfEndSwipesIsAnnouncedOnce` passed (ten end swipes in 0.9 s, one "Maximum, 250 milliseconds")

## Phase 6: Polish

- [X] ACC-005-T14 Run check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events and test_scripts — Verified 2026-11-14: check_compliance, validate_docs (1020 files), check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 tests OK (1 skipped)
- [X] ACC-005-T15 Run projectM-iOSTests and the slider UI suites (SettingsUITests, InputTrimUITests, NoiseGateUITests, LatencyOffsetUITests, VideoLoopUITests, GlowUITests, VoiceOverParameterUITests) on the own iOS 27.2 simulator; count PosterBoard reports before and after — Verified 2026-11-14: projectM-iOSTests 520 passed (39 s run); UI suites 12 tests passed (302 s run, each test under 30 s); Release simulator build succeeded with 0 probe symbols (`nm -U`); PosterBoard reports 25 before and after
- [ ] ACC-005-T16 `{device}` D1 with VoiceOver: swipe up and down on every slider (quickstart C); each step is one step and is read with its unit; ends announced once

## Dependencies

T01 → T02 → T03 → (T04, T05) → T06–T09 (T07–T09 in parallel) → T10, T11 → T12, T13 → T14 → T15 → T16.

## Implementation Strategy

MVP is User Story 1 (T01–T11): it alone meets the roadmap's acceptance. US2's formatter is built in T02
and only needs the existing tests updated; US3 is the end lane.
