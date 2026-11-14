# Tasks: OUT-012 External Display Rehearsal

**Input**: Design documents from `specs/184-out-012-display-rehearsal/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/rehearsal.md, quickstart.md

Tests are part of this feature (the row's acceptance is a mapping test). Budgets (owner rule 7):
unit tests ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Foundational (blocking)

- [X] OUT-012-T01 [P] `RehearsalProfile`, `ExternalOutputRehearsal`, `RehearsalPreviewTransform` (contract C1; sizes "clamped 160…7680", PAR "sanitised 0.5…2") in `Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputRehearsal.swift` — Verified 2026-11-14: swift test --package-path Packages/PresentationLifecycle, 70 pass (4 new) in 0.15 s
- [X] OUT-012-T02 [P] Package tests in `Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputRehearsalTests.swift`: placement equals OUT-004's for the profile; grid points map inside the preview frame; circles round in the preview for Fit and Fill (0.5 %), ellipse for Stretch; spoken description and probe; clamping — Verified 2026-11-14: ExternalOutputRehearsalTests 4 pass on the host: placement equals OUT-004's, preview circles round within 0.5 % for 4 Fit/Fill cases, Stretch at PAR 1.2 reads 1.2, description, probe, clamping
- [X] OUT-012-T03 `standInPixelAspect` in `Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift` (C2) — Verified 2026-11-14: ExternalRehearsalTests (fake display slots use the stand-in PAR); ExternalOutputCorrectionTests 8 pass

## Phase 2: User Story 1 - Preview the output (P1) MVP

- [X] OUT-012-T04 [US1] `RehearsalPreviewView` (stage, outline, real external `VisualSlotView` scaled by the preview transform) and `RehearsalCardView` in `Apps/projectM-iOS/ExternalDisplay/RehearsalPreviewView.swift` — Verified 2026-11-14: ExternalRehearsalTests 6 pass (iOS 27.2 simulator OUT12): the preview slot's placement equals the real slot's
- [X] OUT-012-T05 [US1] Acceptance tests in `Apps/projectM-iOS/Tests/ExternalRehearsalTests.swift`: four profile × correction cases, grid centres and edges through the preview and a real coordinator-placed external slot of that profile agree within 0.5 pt after scaling; rendered circle physical axis ratio equal within 2 % (OUT-012-S1, S2) — Verified 2026-11-14: testGridPointsMapTheSameThroughThePreviewAndTheRealSlot (4 profiles: 1920×1080 Fit/Device, 1024×768 PAR 1.2 Fill/Device, 2560×1080 Fit/Display with 0.9 override, 720×480 PAR 0.9 Fit/Device; 45 points each within 0.5 pt) and testRenderedCirclesHaveTheSamePhysicalAxisRatioInThePreviewAndTheRealSlot (within 2 %, and round within 3 %) pass in 0.13 s
- [X] OUT-012-T06 [US1] `ExternalRehearsalView` (profile, custom size, display PAR, Fit/Shape bound to the OUT-004 setting, device shape from the coordinator else the window, preview with spoken description, DEBUG probe, Done) in `Apps/projectM-iOS/Views/ExternalRehearsalView.swift`; "Rehearse output…" row and cover in `Apps/projectM-iOS/Views/ExternalDisplaySection.swift`; strings in `ExternalOutputSetting.swift` (C4, OUT-012-R1, R2, R7) — Verified 2026-11-14: build-for-testing (iOS 27.2) with no type-check warnings in new code; ExternalRehearsalUITests drives the row, Shape picker, label and Done

## Phase 3: User Story 2 - Test grid (P2)

- [X] OUT-012-T07 [US2] Grid layer (circles, centre circle, crosshair) toggled on `RehearsalCardView`; covered by T05's bitmap (grid on) (OUT-012-R5) — Verified 2026-11-14: testTheCardGridTogglesAndSizesFromItsBounds

## Phase 4: User Story 3 - Exit and takeover (P2)

- [X] OUT-012-T08 [US3] `isRehearsing`, `hasExternalDisplay`, `beginRehearsal()`, `endRehearsal()` in `Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift`; tests in `ExternalRehearsalTests.swift`: a settled connect ends rehearsal, an unsettled bounce does not, begin refused while connected; the visual stays in the device slot throughout (OUT-012-S3, R8) — Verified 2026-11-14: testASettledRealDisplayEndsTheRehearsalAndTheVisualStaysOnTheDevice, testABounceThatNeverSettlesDoesNotEndTheRehearsal; ExternalDisplayCoordinatorTests 9, HotPlugAcceptanceTests 7, OutputBlackoutCoordinatorTests 7 pass
- [X] OUT-012-T09 [US3] UI test `Apps/projectM-iOS/UITests/ExternalRehearsalUITests.swift`: open the rehearsal, choose Shape Device, probe reads `profile=1920x1080` and `bars=pillarbox`, preview label, Done closes (OUT-012-S4) — Verified 2026-11-14: ExternalRehearsalUITests.testTheRehearsalPreviewReadsTheProfileAndBars passes in 19.4 s (probe profile=1920x1080 par=1.00 fit=fit shape=device … bars=pillarbox; label "Previewing 16 by 9 display, fit, pillarbox")

## Phase 5: Polish

- [X] OUT-012-T10 Regression: ExternalOutputCorrectionTests, ExternalDisplayCoordinatorTests, HotPlugAcceptanceTests, ExternalDisplayUITests; PresentationLifecycle package; repo checks; privacy manifest and network symbols; type-check budget (OUT-012-S5, R9) — Verified 2026-11-14: ExternalDisplayUITests 2 and HotPlugUITests 1 pass; unit regressions above; PresentationLifecycle 70 on the host; compliance, docs, motion, permission and status-event checks OK; script tests 159 OK; privacy manifest and network symbols OK; PosterBoard reports 25 before and after. The Xcode 26 / iOS SDK 26.5 compile and Linux runs are pending CI
- [ ] OUT-012-T11 {device} Quickstart C on D1 with an HDMI projector

## Analysis (speckit-analyze, 2026-11-14)

No critical issues; no constitution conflicts. Fixed: R8 (live visual untouched) had no test, now
asserted in T08; the device-shape fallback (spec Edge Cases) is named in T06. Coverage: R1 → T06; R2
→ T01, T06; R3 → T01, T03, T04, T05; R4 → T01, T04, T05; R5 → T07; R6 → T06, T08; R7 → T01, T06,
T09; R8 → T08; R9 → T01, T02, T10. S1, S2 → T05; S3 → T08; S4 → T09; S5 → T10. 11 tasks, 100 %
of requirements covered.

## Dependencies

T01 → T02, T04 · T03 → T04 → T05, T06, T07 · T08 → T06, T09 · all → T10.

## Parallel

T01/T02 with T03; T07 with T08.

## Implementation strategy

MVP = T01-T05 (the row's acceptance). Then the screen, grid, exit and UI test, then regression.
