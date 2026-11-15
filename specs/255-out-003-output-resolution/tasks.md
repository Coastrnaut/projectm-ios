# Tasks: OUT-003 Independent Output Resolution

**Input**: Design documents from `specs/255-out-003-output-resolution/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/output-resolution.md, quickstart.md

Tests are part of the acceptance ("Configured scale changes output pixels but not scene
coordinates"), so test tasks are included. Budgets (owner rule 7): unit tests ≤ 10 s, package suite
< 1 min, UI test < 30 s; no wall-clock assertions.

## Phase 1: Setup

- [ ] OUT-003-T01 Run `xcodegen generate` and confirm the worktree builds for testing on "OUT3 iPhone 17" (iOS 27.2) with `Build` linked (no file change).

## Phase 2: Foundational (blocking)

- [ ] OUT-003-T02 Create `ExternalResolutionMode` (`native`, `1080p`, `720p`, `custom`), `ExternalOutputResolution` (mode, percent "clamped to 50…100; default 75"), `ExternalPixelBudget` (maxSide ≥ 2, maxPixels ≥ 4, `.unlimited`) and `ResolvedExternalOutput` with `resolve(width:height:nativeScale:budget:)` per contract C1 in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputResolution.swift`.
- [ ] OUT-003-T03 [P] Tests for C1 (OUT-003-S1): 4K/1080p/720p screens × the four choices × compact and regular budgets (representative cases), portrait screen, never upscaled, shape within one pixel, clamp flag, invalid input, percent clamping, in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputResolutionTests.swift`.

## Phase 3: User Story 1 + 2 — safe output pixels, same scene (P1)

**Goal**: an external slot renders its visual at the resolved pixel size without changing scene space.
**Independent test**: `ExternalOutputResolutionAppTests` with a real Text visual on an external slot.

- [ ] OUT-003-T04 [US1] `VisualSlotView`: `resolution`, `pixelBudget`, `resolvedOutput`; in `applyPlacement()` (external role) resolve from bounds and the slot's own display scale and set or remove `traitOverrides.displayScale` on each held view, then `setNeedsLayout()`; device role, `hold()` on a device slot and `removeVisuals()` remove the override (contract C2), in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift`.
- [ ] OUT-003-T05 [US1] `ExternalDisplayCoordinator`: `resolution` and `pixelBudget` pushed with the correction in `pushCorrection()` (deferred while a recording holds the placement), set on new slots in `externalConnected`, `externalResolutionSummary` and a log line (contract C3), in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`.
- [ ] OUT-003-T06 [US2] Acceptance tests (OUT-003-S2): a real `TextVisualHost` on an external slot (640 × 360 pt, display scale 3) at Native then 720p: drawable and a captured frame change from 1920 × 1080 to 1280 × 720, while the view's bounds/centre/transform, the slot placement, the text spec, the normalised text canvas and the compositor's layer stack are equal, and the same host keeps compositing (no restart, OUT-003-R4); plus budget clamping (compact budget on a 4K slot), hold deferral, device return removes the override, in `Apps/projectM-iOS/Tests/ExternalOutputResolutionAppTests.swift`.

## Phase 4: User Story 3 — Settings (P2)

**Goal**: the choice is made in Settings, persists and applies live.
**Independent test**: persistence test and the fake-display UI test.

- [ ] OUT-003-T07 [US3] `ExternalOutputSetting`: `resolutionMode`, `resolutionPercent` under `settings.externalDisplay.resolution` and `settings.externalDisplay.resolutionPercent` (absent or unknown reads the default; nothing stored until changed; `-uitestResetNotice` removes them), pushes to the coordinator; the coordinator's budget from `RecordingOutputCap.device` at launch (`AppCoordinator+ExternalDisplay.swift`); strings, in `Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift`.
- [ ] OUT-003-T08 [US3] Settings › External Display: `externalResolutionPicker` and, for Custom only, `externalResolutionPercent` slider 50…100 step 5 with `.accessibleParameter`; footer sentence, in `Apps/projectM-iOS/Views/ExternalDisplaySection.swift`; DEBUG `externalResolution` probe in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift`.
- [ ] OUT-003-T09 [US3] Keys in `ALLOWED_KEYS` (`scripts/run_device_tests.py`), `LibrarySettingsPolicy.excludedKeys` (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`) and, if needed, `Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift`; persistence test in `ExternalOutputResolutionAppTests.swift`; UI test `testTheResolutionSettingChangesTheExternalDrawable` (720p on the fake 1920 × 1080 display → `drawable=1280x720`, < 30 s) in `Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift`.

## Phase 5: Polish & device

- [ ] OUT-003-T10 {device} D1 with a real 4K display (quickstart B): composition identical at Native, 1080p, 720p and Custom 50 %; log shows the drawable sizes.
- [ ] OUT-003-T11 Regression (OUT-003-S4) and repo checks: `ExternalOutputCorrectionTests`, `ExternalDisplayCoordinatorTests`, `HotPlugAcceptanceTests`, `OutputBlackoutCoordinatorTests`, `ExternalRehearsalTests`, `LibraryBackupAppTests`; the six repo scripts; `check_privacy_manifest.py`; `PresentationLifecycle` stays Foundation-only so it builds on Linux (OUT-003-R9); type-check budget; spec status.

## Dependencies

T01 → T02 → (T03 ∥ T04) → T05 → T06; T05 → T07 → T08 → T09; T11 last; T10 needs a person and a display.

## Parallel examples

- T03 (package tests) alongside T04 (slot code): different files.

## Implementation strategy

MVP = Phases 2–3 (the acceptance). Phase 4 adds the user control; T10 stays open for the device.
