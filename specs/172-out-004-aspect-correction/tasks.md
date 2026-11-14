# Tasks: OUT-004 Aspect Correction

**Input**: Design documents from `specs/172-out-004-aspect-correction/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/output-correction.md, quickstart.md

Tests are part of this feature (the row's acceptance is a geometry test). Budgets (owner rule 7):
unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (blocking)

- [ ] OUT-004-T01 [P] Add `ExternalOutputFit`, `ExternalOutputShape`, `ExternalPixelAspect`, `ExternalOutputCorrection` and `ExternalOutputPlacement` (contract C1) in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputPlacement.swift`
- [ ] OUT-004-T02 [P] Acceptance tests in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputPlacementTests.swift`: screens 16:9, 4:3, 21:9 × source 9:19.5 and display shape × PAR 1.0, 0.9, 1.2: Fit and Fill keep circles within 0.5 % and Fit shows all / Fill covers; Stretch is an ellipse; invalid input; PAR sanitising (OUT-004-S1)

## Phase 2: User Story 1 - Circles stay round (P1) MVP

- [ ] OUT-004-T03 [US1] Apply the placement in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift` (external role: bounds, centre, transform; PAR from the screen mode; mode-change re-layout; device role identity; device size hook) (C2)
- [ ] OUT-004-T04 [US1] `correction`, device shape and recording-hold deferral in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`; `externalPlacementSummary` (C3)
- [ ] OUT-004-T05 [US1] Snapshot and coordinator tests in `Apps/projectM-iOS/Tests/ExternalOutputCorrectionTests.swift`: a circle-grid view rendered through an external slot measures an axis ratio within 2 % (PAR 1.0 and 1.2, Fit and Fill, device shape), black bars in Fit, identity back on the device, the OUT-010 cover spans the bars, deferral while held (OUT-004-S2)

## Phase 3: User Story 2 and 3 - Device shape, Settings and blackout (P2)

- [ ] OUT-004-T06 [US2] `ExternalOutputSetting` in `Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift` and wiring in `AppCoordinator+ExternalDisplay.swift`; keys in `scripts/run_device_tests.py`, `LibrarySettingsPolicy.excludedKeys`, UI-test reset (C4, OUT-004-R8)
- [ ] OUT-004-T07 [US3] Settings › External Display section (`Apps/projectM-iOS/Views/ExternalDisplaySection.swift`, one row in `SettingsView.tailSections`, one argument from `VisualizerView`) (OUT-004-R9)
- [ ] OUT-004-T08 [US3] Placement probe in `Apps/projectM-iOS/Debug/UITestExternalDisplay.swift` and UI test in `Apps/projectM-iOS/UITests/ExternalDisplayUITests.swift`: choose Fit + Device, connect the fake display, read pillarbox bars; Fill reads none; blackout black (OUT-004-S3)

## Phase 4: Polish

- [ ] OUT-004-T09 Regression: ExternalDisplayCoordinatorTests, HotPlugAcceptanceTests, OutputBlackoutCoordinatorTests, LibraryBackup policy tests, ExternalDisplayUITests, HotPlugUITests; repo checks; privacy manifest and network symbols; type-check budget (OUT-004-S4, R10)
- [ ] OUT-004-T10 {device} Quickstart B on D1/D2 with an HDMI adapter and, if available, a composite adapter (non-square pixels)

## Analysis (speckit-analyze, 2026-11-14)

No critical issues. Fixed: T05 now also checks that the OUT-010 cover spans the bars (R6 was only in
the UI test); R9's accessibility is met by standard pickers (no custom controls). Coverage: R1 → T01,
T02; R2 → T03, T04, T05; R3 → T03, T05; R4 → T01-T03; R5 → T03, T05; R6 → T05, T08; R7 → T04, T05;
R8 → T06; R9 → T07; R10 → T02, T09. S1 → T02; S2 → T05; S3 → T08; S4 → T09. 10 tasks, 100 % of
requirements covered.

## Dependencies

T01 → T02, T03 · T03 → T04 → T05 · T04 → T06 → T07, T08 · all → T09.

## Implementation strategy

MVP = T01-T05 (the row's acceptance). Then the setting, UI and probe, then the regression pass.
