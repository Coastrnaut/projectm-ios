# Tasks: OUT-005 Safe-Area Guides

**Input**: Design documents from `specs/258-out-005-safe-area-guides/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/safe-area-guides.md, quickstart.md

Tests are part of the acceptance ("Guides are absent from recorded and external output by
default"). Budgets (owner rule 7): unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s; no
wall-clock assertions.

## Phase 1: Setup

- [X] OUT-005-T01 Run `xcodegen generate` and confirm the worktree builds for testing on "OUT5 iPhone 17" (iOS 27.2) with `Build` linked (no file change). — Verified 2026-11-14: `xcodegen generate` and `build-for-testing` on OUT5 iPhone 17 (iOS 27.2), TEST BUILD SUCCEEDED; preset submodules initialised.

## Phase 2: Foundational (blocking)

- [X] OUT-005-T02 Create `SafeAreaGuideChoice`, `SafeAreaGuideRect`, `SafeAreaGuideGeometry` (`make`, `externalAspect`) per contract C1 in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/SafeAreaGuides.swift` (no Foundation import). — Verified 2026-11-14: OUT-005-T03 tests; the file imports nothing (Linux-safe).
- [X] OUT-005-T03 [P] Tests for C1 (OUT-005-S2): portrait, 16:9, 4:3, square output frames × 93/90 and 90/80; centred within 0.01 pt; fractions; clamping; title above action; cross arm; unusable inputs; external aspect with pixel aspect 1.2, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/SafeAreaGuidesTests.swift`. — Verified 2026-11-14: `swift test --package-path Packages/PresentationLifecycle` 98 tests, 0 failures (6 new, 0.001 s).

## Phase 3: User Stories 1 + 2 — guides on the device only (P1)

**Goal**: the device shows the guides; no output path sees them.
**Independent test**: `SafeAreaGuidesAppTests` (external stand-in and recording pixel identity).

- [X] OUT-005-T04 [US1] `SafeAreaGuideSetting` (C3) in `Apps/projectM-iOS/Coordinators/SafeAreaGuideSetting.swift`; `safeAreaGuides` lazy property in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`. — Verified 2026-11-14: `SafeAreaGuidesAppTests.testPreferenceIsOffByDefaultStoredOnChangeAndRestored`; the app builds with the lazy property.
- [X] OUT-005-T05 [US1] `SafeAreaGuidesLayer` and DEBUG probe (C2) in `Apps/projectM-iOS/Views/SafeAreaGuidesOverlay.swift`; added to `VisualizerView.backdrop` above the visual. — Verified 2026-11-14: `testExternalDisplayNeverShowsTheGuidesAndTheyFollowItsShape` draws the real layer (cross pixel lit on the device) and the UI test finds the probe over the visualizer.
- [X] OUT-005-T06 [US2] Acceptance tests (OUT-005-S1) in `Apps/projectM-iOS/Tests/SafeAreaGuidesAppTests.swift`: the real `SafeAreaGuidesLayer` (plus a green probe) over the device slot while a stand-in visual is on an external window built like the app's: snapshot byte-identical with guides on and off; a real Photo visual recorded and Save Frame captured with the guides on equal the guides-off run. — Verified 2026-11-14: `testExternalDisplayNeverShowsTheGuidesAndTheyFollowItsShape` (external snapshot byte-identical, only the visual in the slot, no hosting view) and `testRecordingAndSavedFrameAreIdenticalWithTheGuidesOn` (Save Frame identical; 14 recorded frames, 0 differing from the guides-off run, no probe pixel), 1.8 s.

## Phase 4: User Story 3 — output shape (P2)

- [X] OUT-005-T07 [US3] `ExternalDisplayCoordinator.externalScreenAspect` (C5) in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`, used by the layer; app test: a 320 × 180 external slot gives 16/9, and the layer's geometry is 16:9 inside a portrait device view. — Verified 2026-11-14: the same external test: `externalScreenAspect` nil on the device, 16/9 on the 320 × 180 slot; geometry 240 × 135 in the 240 × 320 view.

## Phase 5: User Story 4 — Settings (P2)

- [X] OUT-005-T08 [US4] `SafeAreaGuidesSection` (C4) in `Apps/projectM-iOS/Views/SafeAreaGuidesOverlay.swift`; `safeAreaGuides` argument in `SettingsView.swift` (performanceSection) and `VisualizerView.swift`. — Verified 2026-11-14: `SafeAreaGuidesUITests` turns the toggle on and finds the `safeAreaActionPercent` adjustable element; build with type-check warnings (300/150 ms) shows none in the new or changed lines.
- [X] OUT-005-T09 [US4] Keys in `ALLOWED_KEYS` (`scripts/run_device_tests.py`), `LibrarySettingsPolicy.includedKeys` (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`) and `appKeys` in `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; persistence test (OUT-005-S3) in `SafeAreaGuidesAppTests.swift`. — Verified 2026-11-14: `LibraryBackupAppTests` 5/5 (`appKeys` includes `SafeAreaGuideSetting.allKeys`); LibraryBackup package 87/87; persistence test passes.
- [X] OUT-005-T10 [US4] UI test (OUT-005-S4) `SafeAreaGuidesUITests.testSettingsSwitchShowsTheGuides` in `Apps/projectM-iOS/UITests/SafeAreaGuidesUITests.swift`: no probe at launch, toggle on in Settings, probe "action=93 title=90" appears, < 30 s. — Verified 2026-11-14: `SafeAreaGuidesUITests.testSettingsSwitchShowsTheGuides` passed in 17.2 s (probe "action=93 title=90 cross=no frame=…").

## Phase 6: Polish & device

- [X] OUT-005-T11 Regression (OUT-005-S5) and repo checks (PresentationLifecycle stays free of Foundation and UIKit so it builds on Linux, OUT-005-R8): `SceneHUDAppTests`, `ExternalOutputCorrectionTests`, `ExternalOutputResolutionAppTests`, `LibraryBackupAppTests`; PresentationLifecycle and LibraryBackup packages; the six repo scripts; `check_privacy_manifest.py`; `check_network_symbols`; type-check budget; spec status. — Verified 2026-11-14: SafeAreaGuides, SceneHUD, ExternalOutputCorrection, ExternalOutputResolution, LibraryBackup app tests 26/26 (6.0 s); `SceneHUDUITests.testSettingsSwitchTurnsTheHUDOff` passed; PresentationLifecycle 98/98; LibraryBackup 87/87; the six repo scripts exit 0 (179 script tests); `check_privacy_manifest` OK; `check_network_symbols` OK.
- [ ] OUT-005-T12 {device} D1 with a real external display (quickstart B): the phone shows the display-shaped guides, the display and a 10 s recording show none.

## Dependencies

T01 → T02 → (T03 ∥ T04) → T05 → T06 → T07; T04 → T08 → T09 → T10; T11 last; T12 needs a person and a display.

## Implementation strategy

MVP = Phases 2–3 (the acceptance). Phases 4–5 add the output shape and the user control.
