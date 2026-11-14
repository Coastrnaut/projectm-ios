# Tasks: MOD-017 Quantized Parameter Changes

**Input**: Design documents from `specs/206-mod-017-quantized-changes/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/quantized-changes.md, quickstart.md

Tests are requested by the roadmap acceptance ("Change requested between beats applies exactly once at next boundary").

## Phase 1: Setup

- [X] MOD-017-T01 Create the private simulator "MOD17 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run — Verified 2026-11-14: simulator A2EDBA08 created on iOS 27.2; PosterBoard reports 25 before

## Phase 2: Foundational

- [X] MOD-017-T02 Add `QuantizeMode`, `QuantizeBoundary`, `QueuedChange`, `QuantizeRequestResult`, `TempoSnapshot.nextBoundary(after:beats:)` (strictly after) and `QuantizedChangeQueue` (contract Q1; "at most one per key") in Packages/PerformanceControl/Sources/PerformanceControl/QuantizedChangeQueue.swift — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl` (241 tests pass, 17.5 s)

## Phase 3: User Story 1 - Switch on the beat (P1) MVP

**Independent test**: synthetic 120 BPM grid, injected times; a mid-beat request is not applied before, exactly once at, and never after the next beat.

- [X] MOD-017-T03 [US1] Package acceptance and edge tests (Beat not-before/once/never-again over 3 further beats, latest wins of 5 requests, cancel on equal value, request exactly on a beat waits, no tempo / no phase → applyNow(.noTempo), clock jump applies once, request order, boundary helper before/after the anchor) in Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedChangeQueueTests.swift — Verified 2026-11-14: `swift test --filter QuantizedChangeQueue` (10 tests, 0.006 s), acceptance `testBeatChangeMidBeatAppliesExactlyOnceAtNextBeat`
- [ ] MOD-017-T04 [US1] `ParameterQuantizer` (mode persisted under `settings.modulation.quantize`, request, tick(at:), wake-up task, announcements, lock check at request and apply) in Apps/projectM-iOS/Coordinators/ParameterQuantizer.swift; `AppSettings.parameterQuantizer` in Apps/projectM-iOS/Coordinators/AppSettings.swift; wiring (tempo snapshot, monotonic clock, `.parameter` lane, apply through `ParameterInspectorTargets.target`) via one call in Apps/projectM-iOS/Coordinators/AppCoordinator.swift
- [ ] MOD-017-T05 [US1] `ParameterInspectorTargets.quantizedTarget(for:settings:)` (discrete = boolean, enumeration, integer or fixed `choices`) used by Apps/projectM-iOS/Views/ParameterInspectorView.swift, Apps/projectM-iOS/Views/ParameterShelfView.swift and Apps/projectM-iOS/Coordinators/MacroCoordinator.swift
- [ ] MOD-017-T06 [US1] App acceptance through the real write path (glow on: not before the beat, once at it, not again; lock at the boundary refuses and drops; continuous glow intensity applies at once; no tempo applies at once) in Apps/projectM-iOS/Tests/ParameterQuantizerAcceptanceTests.swift

## Phase 4: User Story 2 - Switch on the bar or the cue (P1)

**Independent test**: the same with bar boundaries every 4 beats from the anchor and with cue steps.

- [X] MOD-017-T07 [US2] Bar and Cue package acceptance (bar ignores the beats in between; cueStepped applies once in Cue mode, drops in Beat/Bar; no cues → applyNow(.noCue); setMode/clear drop counts) in Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedChangeQueueTests.swift — Verified 2026-11-14: `swift test --filter QuantizedChangeQueue`: `testBarChangeIgnoresTheBeatsInBetween`, `testCueChangeAppliesOnceAtTheNextCueStep`, `testCueStepInBeatModeAndModeChangeClearTheQueue`
- [ ] MOD-017-T08 [US2] Cue hook `cueApplied()` after the cue's scene in Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift, `hasCues` from `ShowCoordinator.hasCues`; app test of a bar boundary and a real cue step (a queued change lands on top of the next cue's scene once) in Apps/projectM-iOS/Tests/ParameterQuantizerAcceptanceTests.swift

## Phase 5: User Story 3 - Know what is waiting (P2)

**Independent test**: a queued change shows "Queued for the next …" and the announcements are posted.

- [ ] MOD-017-T09 [US3] Settings section (picker `quantize.mode`, Off/Beat/Bar/Cue, help text) in Apps/projectM-iOS/Views/QuantizeChangesSection.swift, added to `mediaSections` in Apps/projectM-iOS/Views/SettingsView.swift; queued indication `quantize.queued.<id>` in the inspector's value section and the shelf caption
- [ ] MOD-017-T10 [US3] UI test (Cue mode with a show fixture: toggling glow in the inspector shows the queued indication; under 30 s) in Apps/projectM-iOS/UITests/QuantizedChangesUITests.swift; announcement texts checked in the app test

## Phase 6: Polish

- [ ] MOD-017-T11 Key `settings.modulation.quantize` in `ALLOWED_KEYS` (scripts/run_device_tests.py), `LibrarySettingsPolicy.excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift) and the `-uitestResetNotice` reset; repo checks, privacy manifest and network-symbol checks, type-check budget, PosterBoard count, delete the simulator and derived data

## Dependencies

T01 → T02 → T03/T07 (package) → T04 → T05 → T06/T08 → T09 → T10 → T11. T03 and T07 share one test file (sequential).
Parallel: T03 and T04 touch different packages; T09's view can be written alongside T06.

## Implementation strategy

MVP is US1 (T02-T06). US2 adds the bar and cue boundaries; US3 the visible indication and UI test.
