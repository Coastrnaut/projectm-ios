# Tasks: OUT-005 Safe-Area Guides

**Input**: Design documents from `specs/258-out-005-safe-area-guides/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/safe-area-guides.md, quickstart.md

Tests are part of the acceptance ("Guides are absent from recorded and external output by
default"). Budgets (owner rule 7): unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s; no
wall-clock assertions.

## Phase 1: Setup

- [ ] OUT-005-T01 Run `xcodegen generate` and confirm the worktree builds for testing on "OUT5 iPhone 17" (iOS 27.2) with `Build` linked (no file change).

## Phase 2: Foundational (blocking)

- [ ] OUT-005-T02 Create `SafeAreaGuideChoice`, `SafeAreaGuideRect`, `SafeAreaGuideGeometry` (`make`, `externalAspect`) per contract C1 in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/SafeAreaGuides.swift` (no Foundation import).
- [ ] OUT-005-T03 [P] Tests for C1 (OUT-005-S2): portrait, 16:9, 4:3, square output frames × 93/90 and 90/80; centred within 0.01 pt; fractions; clamping; title above action; cross arm; unusable inputs; external aspect with pixel aspect 1.2, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/SafeAreaGuidesTests.swift`.

## Phase 3: User Stories 1 + 2 — guides on the device only (P1)

**Goal**: the device shows the guides; no output path sees them.
**Independent test**: `SafeAreaGuidesAppTests` (external stand-in and recording pixel identity).

- [ ] OUT-005-T04 [US1] `SafeAreaGuideSetting` (C3) in `Apps/projectM-iOS/Coordinators/SafeAreaGuideSetting.swift`; `safeAreaGuides` lazy property in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`.
- [ ] OUT-005-T05 [US1] `SafeAreaGuidesLayer` and DEBUG probe (C2) in `Apps/projectM-iOS/Views/SafeAreaGuidesOverlay.swift`; added to `VisualizerView.backdrop` above the visual.
- [ ] OUT-005-T06 [US2] Acceptance tests (OUT-005-S1) in `Apps/projectM-iOS/Tests/SafeAreaGuidesAppTests.swift`: the real `SafeAreaGuidesLayer` (plus a green probe) over the device slot while a stand-in visual is on an external window built like the app's: snapshot byte-identical with guides on and off; a real Photo visual recorded and Save Frame captured with the guides on equal the guides-off run.

## Phase 4: User Story 3 — output shape (P2)

- [ ] OUT-005-T07 [US3] `ExternalDisplayCoordinator.externalScreenAspect` (C5) in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`, used by the layer; app test: a 320 × 180 external slot gives 16/9, and the layer's geometry is 16:9 inside a portrait device view.

## Phase 5: User Story 4 — Settings (P2)

- [ ] OUT-005-T08 [US4] `SafeAreaGuidesSection` (C4) in `Apps/projectM-iOS/Views/SafeAreaGuidesOverlay.swift`; `safeAreaGuides` argument in `SettingsView.swift` (performanceSection) and `VisualizerView.swift`.
- [ ] OUT-005-T09 [US4] Keys in `ALLOWED_KEYS` (`scripts/run_device_tests.py`), `LibrarySettingsPolicy.includedKeys` (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`) and `appKeys` in `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; persistence test (OUT-005-S3) in `SafeAreaGuidesAppTests.swift`.
- [ ] OUT-005-T10 [US4] UI test (OUT-005-S4) `SafeAreaGuidesUITests.testSettingsSwitchShowsTheGuides` in `Apps/projectM-iOS/UITests/SafeAreaGuidesUITests.swift`: no probe at launch, toggle on in Settings, probe "action=93 title=90" appears, < 30 s.

## Phase 6: Polish & device

- [ ] OUT-005-T11 Regression (OUT-005-S5) and repo checks: `SceneHUDAppTests`, `ExternalOutputCorrectionTests`, `ExternalOutputResolutionAppTests`, `LibraryBackupAppTests`; PresentationLifecycle and LibraryBackup packages; the six repo scripts; `check_privacy_manifest.py`; `check_network_symbols`; type-check budget; spec status.
- [ ] OUT-005-T12 {device} D1 with a real external display (quickstart B): the phone shows the display-shaped guides, the display and a 10 s recording show none.

## Dependencies

T01 → T02 → (T03 ∥ T04) → T05 → T06 → T07; T04 → T08 → T09 → T10; T11 last; T12 needs a person and a display.

## Implementation strategy

MVP = Phases 2–3 (the acceptance). Phases 4–5 add the output shape and the user control.
