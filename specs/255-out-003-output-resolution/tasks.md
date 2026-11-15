# Tasks: OUT-003 Independent Output Resolution

**Input**: Design documents from `specs/255-out-003-output-resolution/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/output-resolution.md, quickstart.md

Tests are part of the acceptance ("Configured scale changes output pixels but not scene
coordinates"), so test tasks are included. Budgets (owner rule 7): unit tests ≤ 10 s, package suite
< 1 min, UI test < 30 s; no wall-clock assertions.

## Phase 1: Setup

- [X] OUT-003-T01 Run `xcodegen generate` and confirm the worktree builds for testing on "OUT3 iPhone 17" (iOS 27.2) with `Build` linked (no file change). — Verified 2026-11-14: `xcodegen generate` and `build-for-testing` on OUT3 iPhone 17 (iOS 27.2), exit 0; presets submodules initialised.

## Phase 2: Foundational (blocking)

- [X] OUT-003-T02 Create `ExternalResolutionMode` (`native`, `1080p`, `720p`, `custom`), `ExternalOutputResolution` (mode, percent "clamped to 50…100; default 75"), `ExternalPixelBudget` (maxSide ≥ 2, maxPixels ≥ 4, `.unlimited`) and `ResolvedExternalOutput` with `resolve(width:height:nativeScale:budget:)` per contract C1 in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputResolution.swift`. — Verified 2026-11-14: OUT-003-T03 tests.
- [X] OUT-003-T03 [P] Tests for C1 (OUT-003-S1): 4K/1080p/720p screens × the four choices × compact and regular budgets (representative cases), portrait screen, never upscaled, shape within one pixel, clamp flag, invalid input, percent clamping, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputResolutionTests.swift`. — Verified 2026-11-14: `swift test --package-path Packages/PresentationLifecycle` 92 tests, 0 failures (9 new, 0.002 s).

## Phase 3: User Story 1 + 2 — safe output pixels, same scene (P1)

**Goal**: an external slot renders its visual at the resolved pixel size without changing scene space.
**Independent test**: `ExternalOutputResolutionAppTests` with a real Text visual on an external slot.

- [X] OUT-003-T04 [US1] `VisualSlotView`: `resolution`, `pixelBudget`, `resolvedOutput`; in `applyPlacement()` (external role) resolve the choice from the slot's bounds and its own display scale, then the budget against the visual's placed bounds (Fill's overflow counts), and set or remove `traitOverrides.displayScale` on each held view, then `setNeedsLayout()`; device role, `hold()` on a device slot and `removeVisuals()` remove the override (contract C2), in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift`. — Verified 2026-11-14: `ExternalOutputResolutionAppTests` (4 tests, 0 failures): the override sets 2.0 for 720p on a scale-3 slot, the slot keeps 3, the device slot and disconnect remove it.
- [X] OUT-003-T05 [US1] `ExternalDisplayCoordinator`: `resolution` and `pixelBudget` pushed with the correction in `pushCorrection()` (deferred while a recording holds the placement), set on new slots in `externalConnected`, `externalResolutionSummary` and a log line (contract C3), in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`. — Verified 2026-11-14: `testARecordingHoldDefersTheChangeAndTheDeviceSlotRemovesTheOverride` (deferred while held, applied when the hold ends) and the summary assertions in the acceptance test.
- [X] OUT-003-T06 [US2] Acceptance tests (OUT-003-S2): a real `TextVisualHost` on an external slot (640 × 360 pt, display scale 3) at Native then 720p: drawable and a captured frame change from 1920 × 1080 to 1280 × 720, while the view's bounds/centre/transform, the slot placement, the text spec, the normalised text canvas and the compositor's layer stack are equal, and the same host keeps compositing (no restart, OUT-003-R4); plus budget clamping (compact budget on a 4K slot), hold deferral, device return removes the override, in `Apps/projectM-iOS/Tests/ExternalOutputResolutionAppTests.swift`. — Verified 2026-11-14: `testTheResolutionChangesOutputPixelsButNotSceneCoordinates` (real Text visual, simulator GPU, 2.8 s cold / 0.4 s warm): drawable and capture 1920×1080 → 1280×720; bounds, centre, transform, placement, text spec, layer stack equal; normalised text box within 0.006; `isRunning` and `framesComposited` grew. `testTheDeviceBudgetClampsANative4KScreen`: 2560×1440, clamped=yes.

## Phase 4: User Story 3 — Settings (P2)

**Goal**: the choice is made in Settings, persists and applies live.
**Independent test**: persistence test and the fake-display UI test.

- [X] OUT-003-T07 [US3] `ExternalOutputSetting`: `resolutionMode`, `resolutionPercent` under `settings.externalDisplay.resolution` and `settings.externalDisplay.resolutionPercent` (absent or unknown reads the default; nothing stored until changed; `-uitestResetNotice` removes them), pushes to the coordinator; the coordinator's budget from `RecordingOutputCap.device` at launch (`AppCoordinator+ExternalDisplay.swift`); strings, in `Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift`. — Verified 2026-11-14: `testTheChoicePersistsAndReachesTheCoordinator` (nothing stored until changed, percent clamped to 50, relaunch restores, unknown reads Native, budget = `RecordingOutputCap.device`).
- [X] OUT-003-T08 [US3] Settings › External Display: `externalResolutionPicker` and, for Custom only, `externalResolutionPercent` slider 50…100 step 5 with `.accessibleParameter`; footer sentence, in `Apps/projectM-iOS/Views/ExternalDisplaySection.swift`; DEBUG `externalResolution` probe in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift`. — Verified 2026-11-14: `testTheResolutionSettingChangesTheExternalDrawable` picks 720p in the picker; build with type-check warnings (300/150 ms) shows none in the changed files.
- [X] OUT-003-T09 [US3] Keys in `ALLOWED_KEYS` (`scripts/run_device_tests.py`), `LibrarySettingsPolicy.excludedKeys` (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`) and, if needed, `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; persistence test in `ExternalOutputResolutionAppTests.swift`; UI test `testTheResolutionSettingChangesTheExternalDrawable` (720p on the fake 1920 × 1080 display → `drawable=1280x720`, < 30 s) in `Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift`. — Verified 2026-11-14: UI test passed in 28.8 s (probe `mode=720p scale=0.67 drawable=1280x720 clamped=no`); `LibraryBackupAppTests` 5/5 (keys added to `appKeys` and the excluded set); `LibraryErasePolicy.externalDisplayKeys` also lists them (LibraryBackup package 87/87).

## Phase 5: Polish & device

- [ ] OUT-003-T10 {device} D1 with a real 4K display (quickstart B): composition identical at Native, 1080p, 720p and Custom 50 %; log shows the drawable sizes.
- [X] OUT-003-T11 Regression (OUT-003-S4) and repo checks: `ExternalOutputCorrectionTests`, `ExternalDisplayCoordinatorTests`, `HotPlugAcceptanceTests`, `OutputBlackoutCoordinatorTests`, `ExternalRehearsalTests`, `LibraryBackupAppTests`; the six repo scripts; `check_privacy_manifest.py`; `PresentationLifecycle` stays Foundation-only so it builds on Linux (OUT-003-R9); type-check budget; spec status. — Verified 2026-11-14: ExternalOutputCorrection, ExternalDisplayCoordinator, HotPlugAcceptance, OutputBlackoutCoordinator, ExternalRehearsal, EmergencyBlackout 39/39; LibraryErase + Settings 12/12; ExternalDisplayUITests 3/3; PresentationLifecycle 92/92 (no Foundation import in the new file); the six repo scripts exit 0 (179 script tests); `check_privacy_manifest` OK; `check_network_symbols` OK.

## Dependencies

T01 → T02 → (T03 ∥ T04) → T05 → T06; T05 → T07 → T08 → T09; T11 last; T10 needs a person and a display.

## Parallel examples

- T03 (package tests) alongside T04 (slot code): different files.

## Implementation strategy

MVP = Phases 2–3 (the acceptance). Phase 4 adds the user control; T10 stays open for the device.
