# Tasks: UIX-006 Touch Gesture Mapping

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/gesture-shortcuts.md](contracts/gesture-shortcuts.md)

## Phase 1: Pure rules (PerformanceControl)

- [ ] UIX-006-T01 Gestures, action catalogue, configuration (JSON, defaults, unknown names ignored) in `Packages/PerformanceControl/Sources/PerformanceControl/Gestures/GestureShortcuts.swift` (R1, R2, R9; data model)
- [ ] UIX-006-T02 Classifier with the R10 thresholds and the precedence resolver (G1, G2; R3, R4, R5, R6) in the same file
- [ ] UIX-006-T03 Pure tests `GestureShortcutTests.swift`: every overlapping pair resolves per the table, None hands over to the next or to nothing, master off and VoiceOver fire nothing, classifier thresholds, catalogue has no blackout/destructive action, JSON round trip and unknown names (S1, S2)

## Phase 2: App (US1, US3)

- [ ] UIX-006-T04 `GestureShortcutsSetting` (key `settings.gestures.shortcuts`, lock-refused writes, UI-test reset) and `AppCoordinator.gestureShortcuts` (R8, R9)
- [ ] UIX-006-T05 `AppCoordinator+GestureShortcuts.swift`: `performGestureShortcut`, `handleGestureShortcut` (G3; R7)
- [ ] UIX-006-T06 Recogniser + representable on `visualizerTapArea`, attached only while on and VoiceOver off; DEBUG probe (G5; R5, R6, R11)
- [ ] UIX-006-T07 Settings › Performance › Gesture shortcuts section with lock note and VoiceOver note (G4; R8)
- [ ] UIX-006-T08 Key lists: `ALLOWED_KEYS` (`scripts/run_device_tests.py`), FILE-005 `includedKeys`, `LibraryBackupAppTests` app keys (R9)

## Phase 3: Tests

- [ ] UIX-006-T09 `GestureShortcutsAppTests`: each action runs its coordinator path (Next cue advances the show, Next preset changes the preset, Tap tempo records a tap, HUD toggles), controls stay hidden, master off / VoiceOver nothing, lock refuses edits but not actions, mapping persists across a new setting instance (S3, S4)
- [ ] UIX-006-T10 `GestureShortcutsUITests`: map two-finger tap to Next preset in Settings, two-finger tap changes the preset without toggling the controls; set it to None, nothing changes (S5; < 30 s)
- [ ] UIX-006-T11 Regression: `LibraryBackupAppTests`, `SettingsTests`, `SceneHUDAppTests`, `PerformanceLockAcceptanceTests`; PerformanceControl package suite
- [ ] UIX-006-T12 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget

## Phase 4: Close

- [ ] UIX-006-T13 Spec status, `docs/autonomous` nothing; spec Status line updated with the test counts
- [ ] UIX-006-T14 {device} On D1 and D2: quickstart device steps 1-6 (S6)

## Dependencies

T01 → T02 → T03; T01 → T04 → T05 → T06, T07; T08 with T04; T09 after T05; T10 after T06, T07; T11, T12 after all; T14 needs a person and a device.
