# Tasks: SHOW-003 Beat-Quantized Cue Advance

**Input**: Design documents from `specs/214-show-003-beat-quantized-cues/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cue-step-quantizer.md, quickstart.md

Tests are requested by the roadmap acceptance ("Synthetic beats trigger once and missing tempo uses explicit fallback").

## Phase 1: Setup

- [ ] SHOW-003-T01 Create the private simulator "SHOW3 iPhone 17" (iOS 27.2) and count PosterBoard reports before any run

## Phase 2: Foundational

- [ ] SHOW-003-T02 Add `CueStepRequest`, `CueStepRequestResult` and `QuantizedCueStep` (contract Q1; reuses `QuantizeMode`, `QuantizeImmediateReason`, `TempoSnapshot.nextBoundary(after:beats:)`; "at most one step is queued"; Cue mode stored as Off) in Packages/PerformanceControl/Sources/PerformanceControl/QuantizedCueStep.swift
- [ ] SHOW-003-T03 Add `ShowStepOutcome.queued` (documented as returned only by the app's quantized gate) in Packages/ShowControl/Sources/ShowControl/ShowCueList.swift

## Phase 3: User Story 1 - Next cue on the beat (P1) MVP

**Independent test**: synthetic 120 BPM grid, injected times; a mid-beat Next moves 0 times before, exactly once at, and 0 times over 3 further beats.

- [ ] SHOW-003-T04 [US1] Package tests (Beat once-only over 3 further beats, Bar ignores inner beats, request exactly on a beat waits, same request cancels, different replaces with a new deadline, timed keeps a pending manual request, clock jump returns once, setMode drops) in Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedCueStepTests.swift
- [ ] SHOW-003-T05 [US1] `ShowCueQuantizer` (mode under `settings.show.quantizeCues`, absent = Off; request, tick(at:), wake-up task, `willStep`, announcements, `queuedText`, `appliedAtBoundary`) in Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift; `AppSettings.showCueQuantizer` and `allKeys` in Apps/projectM-iOS/Coordinators/AppSettings.swift
- [ ] SHOW-003-T06 [US1] Gate in `ShowCoordinator.next/previous/go(to:)`, `stepNow(_:)` and `timedNext()` in Apps/projectM-iOS/Coordinators/ShowCoordinator.swift; wiring (tempo snapshot, monotonic clock, `.cue` lane, MOD-017 `tick` first) in Apps/projectM-iOS/Coordinators/AppCoordinator+ParameterQuantizer.swift
- [ ] SHOW-003-T07 [US1] App acceptance over a real show and store (Next mid-beat once at the beat and never again; Bar waits for the bar; Previous replaces Next; Next twice cancels; Next at the last cue is not queued; MOD-017 cue-mode change still lands on the queued cue's scene) in Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift

## Phase 4: User Story 2 - No tempo: explicit fallback (P1)

- [ ] SHOW-003-T08 [US2] Package and app tests: no tempo / no phase → `.applyNow(.noTempo)`, the show moves at once and "Cue changed now, no tempo" is announced (Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedCueStepTests.swift, Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift)

## Phase 5: User Story 3 - Know what is waiting (P2)

- [ ] SHOW-003-T09 [US3] "Quantize cue steps" picker (Off/Beat/Bar) as a new section in Apps/projectM-iOS/Views/QuantizeCueStepsSection.swift, added to a section property of Apps/projectM-iOS/Views/SettingsView.swift; queued text in Apps/projectM-iOS/Views/ShowControls.swift and Apps/projectM-iOS/Views/PerformancePad.swift
- [ ] SHOW-003-T10 [US3] SHOW-002 timed advance uses `timedNext()` in Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift; app test: a due timed advance moves once at the next beat (Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift)
- [ ] SHOW-003-T11 [US3] UI test (Settings offers the picker; with Beat and no tempo Next still moves the show) in Apps/projectM-iOS/UITests/QuantizedCueStepsUITests.swift, under 30 s

## Phase 6: Polish

- [ ] SHOW-003-T12 New key in `ALLOWED_KEYS` (scripts/run_device_tests.py), FILE-005 `excludedKeys` (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift), FILE-011 erase list (Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift); run `LibraryBackupAppTests` and the LibraryBackup package tests
- [ ] SHOW-003-T13 Regression: `ShowCoordinatorTests`, `ShowAutoAdvanceCoordinatorTests`, `ParameterQuantizerAcceptanceTests`, ShowControl package tests; type-check budget flags on the touched files
- [ ] SHOW-003-T14 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; PosterBoard count after; delete the simulator and derived data

## Dependencies

T02 → T04, T05; T03 → T06; T05 → T06 → T07, T08, T10; T09 after T05; T11 after T09; T12 after T05.

## Parallel examples

T02 and T03 (different packages); T09 and T12 (different files).

## Implementation strategy

MVP = US1 (T02-T07); then the fallback (US2), then the indication, timed advance and UI test (US3).
