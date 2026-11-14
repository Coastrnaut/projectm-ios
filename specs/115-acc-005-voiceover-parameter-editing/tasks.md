# Tasks: ACC-005 VoiceOver Parameter Editing

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/accessible-parameters.md](contracts/accessible-parameters.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap row (accessibility unit and UI tests). Budgets (owner rule 7): unit
test about 1–2 s, at most 10 s; UI test under 30 s. Tick a task `[X]` only when verified, with
" — Verified <date>: <how>".

## Phase 1: Setup

- [ ] ACC-005-T01 Add `AnnouncementKind.parameter` (end-of-range lane) in Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift and add `Views/AccessibleParameter.swift` to the checked files in scripts/check_status_events.py

## Phase 2: Foundational (pure core, blocks every story)

- [ ] ACC-005-T02 Create Apps/projectM-iOS/Views/AccessibleParameter.swift with `SpokenUnit`, `SpokenValueFormatter` (exact strings of contract C1.2, typed steps, no `+` chains with ternaries in modifiers), `AccessibleParameterSpec` ("step > 0", `withRange(_:)`), `ParameterStepper` (grid from the minimum, research D3; clamp; end flag) and `ParameterTarget`
- [ ] ACC-005-T03 Add `AccessibleParameterCatalog` with the ten specs of data-model.md in Apps/projectM-iOS/Views/AccessibleParameter.swift; glow range, unit and step hint read from `VisualParameterCatalog.descriptors` (registry hint × 5)
- [ ] ACC-005-T04 [P] Unit tests for the formatter (each unit, signs, singular), the stepper (on-grid ±1 step, off-grid to the next grid value, clamp at both ends, maximum reachable off-grid) and the catalog (glow steps are whole multiples of the registry hint; every spec without its own snapping step spans at most 25 steps; identifiers and labels equal the existing ones, R9) in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift

## Phase 3: User Story 1 — change a setting with VoiceOver swipes (P1) 🎯 MVP

**Independent test**: one increment and one decrement on each control change the stored value by one step and persist.

- [ ] ACC-005-T05 [US1] Add the `.accessibleParameter(_:value:set:didStep:)` modifier and the `\.parameterAnnouncer` environment value in Apps/projectM-iOS/Views/AccessibleParameter.swift (contract C1.1; disabled views are not adjusted)
- [ ] ACC-005-T06 [US1] Glow and text sliders: `glowSlider` takes a spec and a target and uses the modifier; each step ends undo coalescing; SettingsView gains `announcer` and puts it in the environment, in Apps/projectM-iOS/Views/SettingsView.swift; pass `announcer: coordinator.announcer` in `withPresentations` of Apps/projectM-iOS/Views/VisualizerView.swift (not `body`)
- [ ] ACC-005-T07 [P] [US1] Input trim and gate threshold use the modifier with `InputTrimSection.target(_:)` / `NoiseGateSection.target(_:)` in Apps/projectM-iOS/Views/InputTrimSection.swift and Apps/projectM-iOS/Views/NoiseGateSection.swift
- [ ] ACC-005-T08 [P] [US1] Visual delay uses the modifier with `LatencyOffsetSection.target(_:mode:)` (the picked source only) in Apps/projectM-iOS/Views/LatencyOffsetSection.swift
- [ ] ACC-005-T09 [P] [US1] Loop in and out use the modifier with the duration as the range's upper bound and `VideoLoopControls.inTarget(_:)` / `outTarget(_:)`; a step commits the loop (player and undo) in Apps/projectM-iOS/Views/VideoLoopControls.swift
- [ ] ACC-005-T10 [US1] Table test over all ten controls: through each section's own target, one increment and one decrement change the real setting by exactly one step, and a fresh setting on the same UserDefaults suite reads the stepped value (persisted) in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift
- [ ] ACC-005-T11 [US1] UI test `VoiceOverParameterUITests`: `increment()` on the glow intensity (50 % → "55 percent"), `decrement()` on the input trim ("minus 1 decibel"), relaunch, both kept, in Apps/projectM-iOS/UITests/VoiceOverParameterUITests.swift

## Phase 4: User Story 2 — values with units (P1)

**Independent test**: each slider's accessibility value is its number with the spelled unit.

- [ ] ACC-005-T12 [US2] Update the existing slider UI tests to the spoken values (visible readouts unchanged) in Apps/projectM-iOS/UITests/InputTrimUITests.swift, LatencyOffsetUITests.swift, GlowUITests.swift and any other suite that reads a slider value

## Phase 5: User Story 3 — ends announced (P2)

**Independent test**: a burst of increments at the maximum yields one announcement.

- [ ] ACC-005-T13 [US3] Unit test: an `AccessibilityAnnouncer` with a fake clock receives ten end texts within one second and speaks once; the end text is "Maximum, 250 milliseconds" for the delay at 250 ms, in Apps/projectM-iOS/Tests/AccessibleParameterTests.swift

## Phase 6: Polish

- [ ] ACC-005-T14 Run check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events and test_scripts
- [ ] ACC-005-T15 Run projectM-iOSTests and the slider UI suites (SettingsUITests, InputTrimUITests, NoiseGateUITests, LatencyOffsetUITests, VideoLoopUITests, GlowUITests, VoiceOverParameterUITests) on the own iOS 27.2 simulator; count PosterBoard reports before and after
- [ ] ACC-005-T16 `{device}` D1 with VoiceOver: swipe up and down on every slider (quickstart C); each step is one step and is read with its unit; ends announced once

## Dependencies

T01 → T02 → T03 → (T04, T05) → T06–T09 (T07–T09 in parallel) → T10, T11 → T12, T13 → T14 → T15 → T16.

## Implementation Strategy

MVP is User Story 1 (T01–T11): it alone meets the roadmap's acceptance. US2's formatter is built in T02
and only needs the existing tests updated; US3 is the end lane.
