# Tasks: UIX-013 Scene Performance HUD

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/scene-hud.md](contracts/scene-hud.md), [quickstart.md](quickstart.md)

Tests are requested by the roadmap's acceptance ("HUD is excluded from external output and recording").
Budgets (owner rule 7): unit test ≤ 10 s, UI test < 30 s. Simulator results are never device evidence.

## Phase 1: Setup

- [X] UIX-013-T01 Create the private simulator "UIX13 iPhone 17" (iOS 27.2), run `xcodegen generate`, initialise the preset submodules and keep the `Build` symlink (worktree root) — Verified 2026-11-14: simulator AEDC3F7C created, `xcodegen generate`, submodules initialised, `Build` symlink kept

## Phase 2: Foundational

- [X] UIX-013-T02 Add `SceneHUDSetting` (key `settings.visualizer.sceneHUD`, Bool, "absent → false; written on change only", removed by `-uitestResetNotice`) in Apps/projectM-iOS/Coordinators/SceneHUDSetting.swift and one lazy `sceneHUD` property in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: `SceneHUDAppTests.testPreferenceIsOffByDefaultAndStoredOnChange` passed; app builds
- [X] UIX-013-T03 [P] Register the key: `ALLOWED_KEYS` in scripts/run_device_tests.py, FILE-005 `includedKeys` in Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, the app keys of Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (R11, C5) — Verified 2026-11-14: `LibraryBackupAppTests` (5 tests incl. `testIncludedKeysAndFolderNamesAgreeWithTheStores`) passed; LibraryBackup package 80 tests passed on the host

## Phase 3: User Story 1 — see where the show is (P1, MVP)

**Independent test**: with the show seed on cue 1 the HUD reads "Cue 1 of 5 · Opening", "Next: Build", a tempo line and the source; Next makes it "Cue 2 of 5 · Build", "Next: Drop".

- [X] UIX-013-T04 [US1] Implement `SceneHUDContent.make` (contract C1 texts and spoken values: current, next with SHOW-002 countdown and SHOW-003 queued text, tempo with Tap/Estimated/None, FR-042 source verbatim) in Apps/projectM-iOS/Views/SceneHUD.swift — Verified 2026-11-14: `SceneHUDAppTests` text tests (3) passed
- [X] UIX-013-T05 [US1] Implement `SceneHUDLayer` (ACC-008 overlay surface, max width 360 pt, Dynamic Type with two-line limit, C2 identifiers and labels, no announcements) in Apps/projectM-iOS/Views/SceneHUD.swift — Verified 2026-11-14: `SceneHUDUITests` (identifiers, labels, values) passed; type-check build shows no SceneHUD warning
- [X] UIX-013-T06 [US1] Show the layer first in `topStatus` while the setting is on, and pass the setting to Settings, in Apps/projectM-iOS/Views/VisualizerView.swift; add the "Show HUD" toggle (`sceneHUDToggle`) to `performanceSection` in Apps/projectM-iOS/Views/SettingsView.swift (R1, R2, R7, C3) — Verified 2026-11-14: `SceneHUDUITests.testHUDShowsTheShowAndStaysClearOfTheOutput` and `testSettingsSwitchTurnsTheHUDOff` passed
- [X] UIX-013-T07 [P] [US1] Unit tests for C1 texts and the C5 preference in Apps/projectM-iOS/Tests/SceneHUDAppTests.swift — Verified 2026-11-14: `SceneHUDAppTests` 4 text/preference tests passed
- [X] UIX-013-T08 [US1] UI test with `-uitestShowSeed`: four lines, cue step updates them, the HUD frame lies inside the safe area and does not contain the screen centre, the Settings toggle exists, in Apps/projectM-iOS/UITests/SceneHUDUITests.swift (S3, S4) — Verified 2026-11-14: `SceneHUDUITests.testHUDShowsTheShowAndStaysClearOfTheOutput` passed (13.7 s)

## Phase 4: User Story 2 — the audience never sees it (P1)

**Independent test**: the acceptance tests below pass.

- [X] UIX-013-T09 [US2] External output acceptance: an `ExternalDisplayViewController` window showing a solid visual through `ExternalDisplayCoordinator`, the real HUD in a device window; the external window has no hosting view or `sceneHUD` element, and its snapshot is byte-identical with the HUD on and off, in Apps/projectM-iOS/Tests/SceneHUDAppTests.swift (R8, S1) — Verified 2026-11-14: `SceneHUDAppTests.testExternalDisplayNeverShowsTheHUD` passed (external snapshot byte-identical, no hosting view, slot holds only the visual)
- [X] UIX-013-T10 [US2] Recording and saved-frame acceptance: a red Photo visual under the HUD plus a green probe; recorded frames have no probe pixel and match a HUD-off recording; a saved frame (`FrameCaptureSource`) is pixel-identical with HUD on and off, in Apps/projectM-iOS/Tests/SceneHUDAppTests.swift (R9, S2) — Verified 2026-11-14: `SceneHUDAppTests.testRecordingAndSavedFrameAreIdenticalWithTheHUDOn` passed (12 frames on/off, 0 differing, 0 probe pixels; 720x480 still identical)

## Phase 5: User Story 3 — readable for everyone (P2)

- [X] UIX-013-T11 [US3] UI test at AX5: the HUD's lines exist, carry their VoiceOver labels and the HUD stays inside the safe area, in Apps/projectM-iOS/UITests/SceneHUDUITests.swift (R10) — Verified 2026-11-14: `SceneHUDUITests.testLargestTextKeepsTheHUDOnScreen` passed (6.6 s)
- [ ] UIX-013-T12 {device} On D1 with Settings → Show HUD and the five-cue show: the four lines read correctly, a cue step updates them, and an external display or a recording shows no HUD (quickstart step 5)

## Phase 6: Polish

- [X] UIX-013-T13 Type-check budget build (no function body over 300 ms, no expression over 200 ms in the touched files), repo checks (`check_compliance`, `validate_docs`, `check_motion_policy`, `check_permission_catalog`, `check_status_events`, `test_scripts`), `check_privacy_manifest` and `check_network_symbols` on the Debug app, `LibraryBackupAppTests` — Verified 2026-11-14: all six repo checks OK, 174 script tests OK, check_privacy_manifest OK, check_network_symbols OK; no type-check warning in the new files
- [X] UIX-013-T14 Spec status, analyze notes, delete the simulator and derived data — Verified 2026-11-14: spec status updated; simulator and derived data deleted

## Dependencies

T01 → T02 → T04 → T05 → T06 → (T07, T08, T09, T10, T11); T03 any time after T02; T12 after T06; T13–T14 last.
US2 depends on US1's layer (it hosts the real HUD). Parallel: T03 with T04; T07 with T09/T10 authoring.

## Implementation strategy

MVP = US1 + US2 together (the roadmap acceptance is US2); US3 is a check on the same view.

## Analyze notes (speckit-analyze, 2026-11-14)

- I1 (fixed): the last-cue text read "End of show" / "end of show" in two places; normalised to "Next: End of show" (contract C1).
- I2 (fixed): research D2 compared recordings outside the spectrum disc only, while S2 asks for identical frames; D2 now compares whole decoded frames.
- C1 (accepted, LOW): OUT-012's rehearsal preview has no test of its own; it draws its grid card, never device overlays (research D1), and T09 covers the real external path.
- Coverage: R1-R11 and S1-S4 each map to at least one task (R1 T02/T06/T07, R2-R7 T04-T06/T08, R8 T09, R9 T10, R10 T05/T11, R11 T03/T13). No constitution conflict.
