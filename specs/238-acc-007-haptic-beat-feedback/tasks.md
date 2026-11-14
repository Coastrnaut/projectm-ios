# Tasks: ACC-007 Haptic Beat Feedback

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/haptic-beat.md](contracts/haptic-beat.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap's acceptance ("Off setting produces zero haptic calls; high event rate is
throttled"). Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min, UI test < 30 s. Simulator results
are never device evidence.

## Phase 1: Setup

- [X] ACC-007-T01 Create the private simulator "ACC7 iPhone 17" (iOS 27.2), run `xcodegen generate`, initialise the preset submodules and keep the `Build` symlink — Verified 2026-11-14: simulator 093C05C7 created, `xcodegen generate`, submodules initialised, `Build` symlink kept, baseline build-for-testing succeeded

## Phase 2: Foundational

- [X] ACC-007-T02 Implement `HapticBeatChoice`, `HapticPulseStrength`, `HapticCue`, `HapticPulseRules`, `HapticPulseDecision` and `HapticPulseGate` (contract C1) in Packages/PerformanceControl/Sources/PerformanceControl/HapticPulseGate.swift — Verified 2026-11-14: `HapticPulseGateTests` (6) passed on the host
- [X] ACC-007-T03 Implement `HapticCue.init?(_: AnalysisEvent)` (C2) in Packages/PerformanceControl/Sources/PerformanceControlAnalysis/HapticCue+Analysis.swift and `TempoSubscriptionReader.poll(onEvent:)` in TempoAnalyzer.swift — Verified 2026-11-14: `HapticPulseGateTests.testAnalysisEventsMapToCues` and `testPollHandsEveryDrainedEventToTheObserver` passed
- [X] ACC-007-T04 [P] Package tests: limits at 30 Hz with a deterministic stream, downbeat counting across sessions, choice filtering, stale and suppressed decisions, mapping, `poll(onEvent:)` sees every event, in Packages/PerformanceControl/Tests/PerformanceControlTests/HapticPulseGateTests.swift — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl`: 263 tests, 0 failures (20.6 s); HapticPulseGateTests 6 passed

## Phase 3: User Story 1 — feel the beat, only when asked (P1, MVP)

- [X] ACC-007-T05 [US1] `HapticPlaying` and the `UIImpactFeedbackGenerator` player (generators created lazily, on first play) in Apps/projectM-iOS/Coordinators/HapticPlayer.swift — Verified 2026-11-14: `HapticBeatAcceptanceTests` (9) passed with a fake; `ImpactHapticPlayer` builds with no warning (generators made only in `play`)
- [X] ACC-007-T06 [US1] `HapticBeatCoordinator` (C3, C5 keys, `-uitestResetNotice`, conditions, observer install/remove) in Apps/projectM-iOS/Coordinators/HapticBeatCoordinator.swift; `analysisEventObserver` and the 40 ms poll in Apps/projectM-iOS/Coordinators/TempoCoordinator.swift; one lazy property attached at init in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: `HapticBeatAcceptanceTests.testOffInstallsNoTempoObserverAndKeepsTheSlowPoll`, `testNoHapticHardwareInstallsNothingEvenWhenOn` passed; `TempoCoordinatorTests` (9) still pass
- [X] ACC-007-T07 [US1] Acceptance tests S1, S2 (Off → 0 calls over 60 s at 30 Hz; On → spacing, windows, determinism) and the tempo observer install/remove in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift — Verified 2026-11-14: `testOffMakesZeroHapticCallsOverADenseStream` (0 calls, 0 players over 60 s at 30 Hz), `testHighEventRateIsThrottled` (gaps ≥ 150 ms, ≤ 4 per 1 s, ≤ 180 per 60 s, identical second run), `testLateEventsAreDroppedNotPlayedLate` passed
- [X] ACC-007-T08 [US1] Settings section (C4) in Apps/projectM-iOS/Views/HapticBeatSection.swift, one row in `safetySections` of Apps/projectM-iOS/Views/SettingsView.swift, the argument in Apps/projectM-iOS/Views/VisualizerView.swift, the "haptics" ID in Apps/projectM-iOS/Debug/UITestSettingsSection.swift's list — Verified 2026-11-14: `HapticBeatUITests.testSwitchShowsAndHidesTheChoices` passed; type-check build shows no warning in the new files
- [X] ACC-007-T09 [US1] UI test: the switch is off, the choices are hidden, turning it on shows them, turning it off hides them, in Apps/projectM-iOS/UITests/HapticBeatUITests.swift (S5) — Verified 2026-11-14: `HapticBeatUITests.testSwitchShowsAndHidesTheChoices` passed (15.8 s)

## Phase 4: User Story 2 — choose what pulses (P2)

- [X] ACC-007-T10 [US2] Acceptance test S3 (Beats, Downbeats, Kicks over one mixed stream; strength reaches the player) in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift — Verified 2026-11-14: `testEachChoicePulsesOnlyOnItsEvents` passed (Beats, Downbeats 1 and 5, Kicks; strength reaches the player)

## Phase 5: User Story 3 — safe and quiet when it should be (P2)

- [X] ACC-007-T11 [US3] Acceptance test S4 (Strict, Custom ≤ 0.25, Low Power Mode, inactive app, no hardware → 0 calls; Reduced → intensity 0.5) in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift — Verified 2026-11-14: `testStrictLowPowerBackgroundAndMissingHardwareMakeNoCalls`, `testReducedPlaysAtHalfIntensityAndReduceFlashingAloneChangesNothing` passed
- [X] ACC-007-T12 [US3] ACC-012 footer and note (R10) in Apps/projectM-iOS/Views/SensorySafetySection.swift, Packages/FlashSafety/Sources/FlashSafety/SensorySafetyProfile.swift (comment) and specs/121-acc-012-sensory-safety-profile/spec.md (R9 amendment note) — Verified 2026-11-14: footer, comment and ACC-012-R9 amendment written; `SensorySafetyAppTests` (9) and FlashSafety package (27) pass; `validate_docs` OK
- [ ] ACC-007-T13 {device} On D1: Settings → Haptics on, Beats, In-App Playback music: taps on the beat; Kicks and Downbeats change them; Strict, Low Power Mode and the switch off give none (quickstart step 4)

## Phase 6: Polish

- [X] ACC-007-T14 Register the keys (R8): `ALLOWED_KEYS` in scripts/run_device_tests.py, FILE-005 `includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, the app keys in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift; check that no scene, cue, MIDI or OSC code reads the keys (R9); run `LibraryBackupAppTests` and the LibraryBackup package tests — Verified 2026-11-14: keys in the three lists; no scene/MIDI/OSC/ParameterGraph code reads them (grep: 0); `LibraryBackupAppTests` (5) passed; LibraryBackup package 83 tests passed
- [X] ACC-007-T15 Type-check budget build, the six repo checks, `check_privacy_manifest` and `check_network_symbols` on the Debug app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 177 OK; check_privacy_manifest OK; check_network_symbols OK; no type-check warning in the touched files except the pre-existing `AppCoordinator.init` (unchanged body)
- [X] ACC-007-T16 Spec status, analyze notes, delete the simulator and derived data, PosterBoard counts — Verified 2026-11-14: spec status updated; simulator and derived data deleted; PosterBoard reports 26 before and after

## Dependencies

T01 → T02 → T03 → T04; T02 → T05 → T06 → (T07, T08, T10, T11) → T09; T12, T14 any time after T06; T13 after
T08; T15–T16 last. Parallel: T04 with T05; T12 with T07.

## Implementation strategy

MVP = US1 (both acceptance clauses). US2 and US3 are further tests on the same coordinator.

## Analyze notes (speckit-analyze, 2026-11-14)

- C1 (fixed): R9 (never in scenes, cues, MIDI, OSC, modulation) had no task; T14 now also checks that no scene, MIDI or OSC code references the keys (grep in the polish step).
- C2 (fixed): R11 (labels, identifiers, Dynamic Type) is covered by T08 (identifiers and labels) and T09 (the UI test finds them by identifier).
- I1 (accepted, LOW): the footer text lives in contract C4 only; the spec states its content (R1, R6), not its wording.
- Coverage: R1 T08/T09, R2 T06/T07, R3 T02/T04/T10, R4 T02/T04/T07, R5 T06/T11, R6 T06/T08/T11, R7 T03/T06, R8 T14, R9 T14, R10 T12, R11 T08/T09; S1-S5 map to T07, T07, T10, T11, T09. No constitution conflict.
