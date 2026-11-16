# Tasks: UIX-006 Touch Gesture Mapping

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/gesture-shortcuts.md](contracts/gesture-shortcuts.md)

## Phase 1: Pure rules (PerformanceControl)

- [X] UIX-006-T01 Gestures, action catalogue, configuration (JSON, defaults, unknown names ignored) in `Packages/PerformanceControl/Sources/PerformanceControl/Gestures/GestureShortcuts.swift` (R1, R2, R9; data model)
- [X] UIX-006-T02 Classifier with the R10 thresholds and the precedence resolver (G1, G2; R3, R4, R5, R6) in the same file
- [X] UIX-006-T03 Pure tests `GestureShortcutTests.swift`: every overlapping pair resolves per the table, None hands over to the next or to nothing, master off and VoiceOver fire nothing, classifier thresholds, catalogue has no blackout/destructive action, JSON round trip and unknown names (S1, S2) — Verified 2026-11-15: `swift test --filter GestureShortcutTests` (PerformanceControl), 8 tests pass

## Phase 2: App (US1, US3)

- [X] UIX-006-T04 `GestureShortcutsSetting` (key `settings.gestures.shortcuts`, lock-refused writes, UI-test reset) and `AppCoordinator.gestureShortcuts` (R8, R9) — Verified 2026-11-15: GestureShortcutsAppTests.testMappingPersists and testAppCoordinatorResolvesQuietlyAndHonoursSwitchVoiceOverAndLock pass
- [X] UIX-006-T05 `AppCoordinator+GestureShortcuts.swift`: `performGestureShortcut`, `handleGestureShortcut` (G3; R7) — Verified 2026-11-15: GestureShortcutsAppTests.testEachActionRunsItsControlsPath and the coordinator test pass
- [X] UIX-006-T06 Recogniser + representable on `visualizerTapArea`, attached only while on and VoiceOver off; DEBUG probe (G5; R5, R6, R11; the one-finger tap path is checked by T10's controls assertion) — Verified 2026-11-15: GestureShortcutsUITests (two-finger tap fires once, the controls' tap does not also fire) passes on UIX6 iPhone 17
- [X] UIX-006-T07 Settings › Performance › Gesture shortcuts section with lock note and VoiceOver note (G4; R8) — Verified 2026-11-15: GestureShortcutsUITests drives the switch and the picker; the lock disables it (coordinator test: edits refused)
- [X] UIX-006-T08 Key lists: `ALLOWED_KEYS` (`scripts/run_device_tests.py`), FILE-005 `includedKeys`, `LibraryBackupAppTests` app keys (R9) — Verified 2026-11-15: LibraryBackupAppTests (all) and LibraryBackup package (88 tests) pass

## Phase 3: Tests

- [X] UIX-006-T09 `GestureShortcutsAppTests`: each action runs its coordinator path (Next cue advances the show, Next preset changes the preset, Tap tempo records a tap, HUD toggles), controls stay hidden, master off / VoiceOver nothing, lock refuses edits but not actions, mapping persists across a new setting instance (S3, S4) — Verified 2026-11-15: GestureShortcutsAppTests 3 tests pass (0.07 s)
- [X] UIX-006-T10 `GestureShortcutsUITests`: map two-finger tap to Next preset in Settings, two-finger tap changes the preset without toggling the controls; set it to None, nothing changes (S5; < 30 s) — Verified 2026-11-15: GestureShortcutsUITests 1 test passes in 21.0 s on UIX6 iPhone 17 (iOS 27.2)
- [X] UIX-006-T11 Regression: `LibraryBackupAppTests`, `SettingsTests`, `SceneHUDAppTests`, `PerformanceLockAcceptanceTests`; PerformanceControl package suite — Verified 2026-11-15: 30 unit tests (GestureShortcutsAppTests, LibraryBackupAppTests, SettingsTests, SceneHUDAppTests, PerformanceLockAcceptanceTests, LibraryEraseAppTests) and SceneHUDUITests 3 pass; PerformanceControl 345 tests pass
- [X] UIX-006-T12 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app, type-check budget — Verified 2026-11-15: six repo checks exit 0; check_privacy_manifest and check_network_symbols OK on the Debug app; type-check: no new function over 300 ms; one expression (first AppCoordinator member use in GestureShortcutViews.swift) at ~260 ms, the same per-file cost existing files show in the same build (OneHandedControls.swift, UITestMemoryPanel.swift)

## Phase 4: Close

- [X] UIX-006-T13 Spec Status line updated with the verified test counts and the open {device} task — Verified 2026-11-15: spec Status line
- [ ] UIX-006-T14 {device} On D1 and D2: quickstart device steps 1-6 (S6) D2 partly automated 2026-11-15 (docs/test-reports/qa-011/acceptance/D2-B02.md): GestureShortcutsUITests on D2, a two-finger tap runs the mapped action and the switch disables it. Open: the remaining quickstart device steps on D1 and D2.

## Dependencies

T01 → T02 → T03; T01 → T04 → T05 → T06, T07; T08 with T04; T09 after T05; T10 after T06, T07; T11, T12 after all; T14 needs a person and a device.

## Analysis (speckit-analyze, 2026-11-15)

- Coverage: R1-R2 T01/T03; R3-R6 T02/T03/T06; R7 T05/T09; R8 T04/T07/T09; R9 T04/T08/T09; R10 T02/T03; R11 T06/T10. S1-S2 T03; S3-S4 T09; S5 T10; S6 T14.
- Fixed: T13 wording (no stray reference); T06 names how R11 is checked. The key is not in `AppSettings.allKeys`, so `SettingsTests` needs no change (it is still run in T11).
- No constitution conflicts; no ADR needed (no default overridden).
