# Tasks: OUT-012 External Display Rehearsal

**Input**: Design documents from `specs/184-out-012-display-rehearsal/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/rehearsal.md, quickstart.md

Tests are part of this feature (the row's acceptance is a mapping test). Budgets (owner rule 7):
unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (blocking)

- [ ] OUT-012-T01 [P] `RehearsalProfile`, `ExternalOutputRehearsal`, `RehearsalPreviewTransform` (contract C1; sizes "clamped 160…7680", PAR "sanitised 0.5…2") in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputRehearsal.swift`
- [ ] OUT-012-T02 [P] Package tests in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputRehearsalTests.swift`: placement equals OUT-004's for the profile; grid points map inside the preview frame; circles round in the preview for Fit and Fill (0.5 %), ellipse for Stretch; spoken description and probe; clamping
- [ ] OUT-012-T03 `standInPixelAspect` in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift` (C2)

## Phase 2: User Story 1 - Preview the output (P1) MVP

- [ ] OUT-012-T04 [US1] `RehearsalPreviewView` (stage, outline, real external `VisualSlotView` scaled by the preview transform) and `RehearsalCardView` in `Apps/projectM-iOS/ExternalDisplay/RehearsalPreviewView.swift`
- [ ] OUT-012-T05 [US1] Acceptance tests in `Apps/projectM-iOS/Tests/ExternalRehearsalTests.swift`: four profile × correction cases, grid centres and edges through the preview and a real coordinator-placed external slot of that profile agree within 0.5 pt after scaling; rendered circle physical axis ratio equal within 2 % (OUT-012-S1, S2)
- [ ] OUT-012-T06 [US1] `ExternalRehearsalView` (profile, custom size, display PAR, Fit/Shape bound to the OUT-004 setting, preview with spoken description, DEBUG probe, Done) in `Apps/projectM-iOS/Views/ExternalRehearsalView.swift`; "Rehearse output…" row and cover in `Apps/projectM-iOS/Views/ExternalDisplaySection.swift`; strings in `ExternalOutputSetting.swift` (C4, OUT-012-R1, R2, R7)

## Phase 3: User Story 2 - Test grid (P2)

- [ ] OUT-012-T07 [US2] Grid layer (circles, centre circle, crosshair) toggled on `RehearsalCardView`; covered by T05's bitmap (grid on) (OUT-012-R5)

## Phase 4: User Story 3 - Exit and takeover (P2)

- [ ] OUT-012-T08 [US3] `isRehearsing`, `hasExternalDisplay`, `beginRehearsal()`, `endRehearsal()` in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`; tests in `ExternalRehearsalTests.swift`: a settled connect ends rehearsal, an unsettled bounce does not, begin refused while connected (OUT-012-S3)
- [ ] OUT-012-T09 [US3] UI test `Apps/projectM-iOS/UITests/ExternalRehearsalUITests.swift`: open the rehearsal, choose Shape Device, probe reads `profile=1920x1080` and `bars=pillarbox`, preview label, Done closes (OUT-012-S4)

## Phase 5: Polish

- [ ] OUT-012-T10 Regression: ExternalOutputCorrectionTests, ExternalDisplayCoordinatorTests, HotPlugAcceptanceTests, ExternalDisplayUITests; PresentationLifecycle package; repo checks; privacy manifest and network symbols; type-check budget (OUT-012-S5, R9)
- [ ] OUT-012-T11 {device} Quickstart C on D1 with an HDMI projector

## Dependencies

T01 → T02, T04 · T03 → T04 → T05, T06, T07 · T08 → T06, T09 · all → T10.

## Parallel

T01/T02 with T03; T07 with T08.

## Implementation strategy

MVP = T01-T05 (the row's acceptance). Then the screen, grid, exit and UI test, then regression.
