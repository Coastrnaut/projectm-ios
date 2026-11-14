# Tasks: ACC-007 Haptic Beat Feedback

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/haptic-beat.md](contracts/haptic-beat.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap's acceptance ("Off setting produces zero haptic calls; high event rate is
throttled"). Budgets (owner rule 7): unit test ≤ 10 s, package suite < 1 min, UI test < 30 s. Simulator results
are never device evidence.

## Phase 1: Setup

- [ ] ACC-007-T01 Create the private simulator "ACC7 iPhone 17" (iOS 27.2), run `xcodegen generate`, initialise the preset submodules and keep the `Build` symlink

## Phase 2: Foundational

- [ ] ACC-007-T02 Implement `HapticBeatChoice`, `HapticPulseStrength`, `HapticCue`, `HapticPulseRules`, `HapticPulseDecision` and `HapticPulseGate` (contract C1) in Packages/PerformanceControl/Sources/PerformanceControl/HapticPulseGate.swift
- [ ] ACC-007-T03 Implement `HapticCue.init?(_: AnalysisEvent)` (C2) in Packages/PerformanceControl/Sources/PerformanceControlAnalysis/HapticCue+Analysis.swift and `TempoSubscriptionReader.poll(onEvent:)` in TempoAnalyzer.swift
- [ ] ACC-007-T04 [P] Package tests: limits at 30 Hz with a deterministic stream, downbeat counting across sessions, choice filtering, stale and suppressed decisions, mapping, `poll(onEvent:)` sees every event, in Packages/PerformanceControl/Tests/PerformanceControlTests/HapticPulseGateTests.swift

## Phase 3: User Story 1 — feel the beat, only when asked (P1, MVP)

- [ ] ACC-007-T05 [US1] `HapticPlaying` and the `UIImpactFeedbackGenerator` player (generators created lazily, on first play) in Apps/projectM-iOS/Coordinators/HapticPlayer.swift
- [ ] ACC-007-T06 [US1] `HapticBeatCoordinator` (C3, C5 keys, `-uitestResetNotice`, conditions, observer install/remove) in Apps/projectM-iOS/Coordinators/HapticBeatCoordinator.swift; `analysisEventObserver` and the 40 ms poll in Apps/projectM-iOS/Coordinators/TempoCoordinator.swift; one lazy property attached at init in Apps/projectM-iOS/Coordinators/AppCoordinator.swift
- [ ] ACC-007-T07 [US1] Acceptance tests S1, S2 (Off → 0 calls over 60 s at 30 Hz; On → spacing, windows, determinism) and the tempo observer install/remove in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift
- [ ] ACC-007-T08 [US1] Settings section (C4) in Apps/projectM-iOS/Views/HapticBeatSection.swift, one row in `safetySections` of Apps/projectM-iOS/Views/SettingsView.swift, the argument in Apps/projectM-iOS/Views/VisualizerView.swift, the "haptics" ID in Apps/projectM-iOS/Debug/UITestSettingsSection.swift's list
- [ ] ACC-007-T09 [US1] UI test: the switch is off, the choices are hidden, turning it on shows them, turning it off hides them, in Apps/projectM-iOS/UITests/HapticBeatUITests.swift (S5)

## Phase 4: User Story 2 — choose what pulses (P2)

- [ ] ACC-007-T10 [US2] Acceptance test S3 (Beats, Downbeats, Kicks over one mixed stream; strength reaches the player) in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift

## Phase 5: User Story 3 — safe and quiet when it should be (P2)

- [ ] ACC-007-T11 [US3] Acceptance test S4 (Strict, Custom ≤ 0.25, Low Power Mode, inactive app, no hardware → 0 calls; Reduced → intensity 0.5) in Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift
- [ ] ACC-007-T12 [US3] ACC-012 footer and note (R10) in Apps/projectM-iOS/Views/SensorySafetySection.swift, Packages/FlashSafety/Sources/FlashSafety/SensorySafetyProfile.swift (comment) and specs/121-acc-012-sensory-safety-profile/spec.md (R9 amendment note)
- [ ] ACC-007-T13 {device} On D1: Settings → Haptics on, Beats, In-App Playback music: taps on the beat; Kicks and Downbeats change them; Strict, Low Power Mode and the switch off give none (quickstart step 4)

## Phase 6: Polish

- [ ] ACC-007-T14 Register the keys (R8): `ALLOWED_KEYS` in scripts/run_device_tests.py, FILE-005 `includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, the app keys in Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift; run `LibraryBackupAppTests` and the LibraryBackup package tests
- [ ] ACC-007-T15 Type-check budget build, the six repo checks, `check_privacy_manifest` and `check_network_symbols` on the Debug app
- [ ] ACC-007-T16 Spec status, analyze notes, delete the simulator and derived data, PosterBoard counts

## Dependencies

T01 → T02 → T03 → T04; T02 → T05 → T06 → (T07, T08, T10, T11) → T09; T12, T14 any time after T06; T13 after
T08; T15–T16 last. Parallel: T04 with T05; T12 with T07.

## Implementation strategy

MVP = US1 (both acceptance clauses). US2 and US3 are further tests on the same coordinator.
