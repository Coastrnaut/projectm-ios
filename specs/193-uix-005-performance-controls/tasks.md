# Tasks: UIX-005 Performance Control Layout

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/performance-pad.md](contracts/performance-pad.md)

Tests are short (owner rule 7): unit tests about 1 s, each UI test under 30 s.

## Phase 1: Foundational

- [ ] UIX-005-T01 Write `PerformanceLayout` (arrangement, target, spacing, margin, column width, reserved insets) in `Packages/ShowControl/Sources/ShowControl/PerformanceLayout.swift` (data-model; UIX-005-R3, R4)
- [ ] UIX-005-T02 Unit tests `Packages/ShowControl/Tests/ShowControlTests/PerformanceLayoutTests.swift`: iPhone portrait (bar, 60), iPhone landscape (columns, 60, insets), iPad regular (72), narrow width (grid), square area (bar) (UIX-005-S4)
- [ ] UIX-005-T03 Session state: `performanceLayout` in `AppCoordinator.swift`; `AppCoordinator+PerformanceLayout.swift` with toggle, cue and tap actions that do not show the controls, DEBUG `-uitestPerformanceLayout` (UIX-005-R1, R5, R6)

## Phase 2: User Story 1 + 2 (P1) — the pad in every orientation

- [ ] UIX-005-T04 [US1] `PerformancePadBlackout` state from `OutputBlackout.Phase` and its unit tests in `Apps/projectM-iOS/Tests/PerformancePadTests.swift` (UIX-005-R7, R8)
- [ ] UIX-005-T05 [US1] `Apps/projectM-iOS/Views/PerformancePad.swift`: layer, bar, grid, columns, targets, readouts, insets callback, safe-area probe (UIX-005-R2-R4, R9, R10)
- [ ] UIX-005-T06 [US1] "Performance layout"/"Standard layout" button in `ControlsOverlay.swift` (UIX-005-R1)
- [ ] UIX-005-T07 [US1] `VisualizerView.swift`: pad layer, status-stack insets, emergency button hidden while the pad shows; the pad's appearance is not animated, so Reduce Motion needs no case (UIX-005-R2, R4, R8, R11)
- [ ] UIX-005-T08 [US1] UI test portrait: toggle from the controls, geometry and safe area, pad survives the auto-hide, Next applies cue 2 (probe), Blackout toggles, Tap reads "Tap 1 of 4", "Standard layout" removes the pad and brings back the emergency button, in `Apps/projectM-iOS/UITests/PerformanceLayoutUITests.swift` (UIX-005-S1)
- [ ] UIX-005-T09 [US2] UI test landscape: geometry, safe area, side columns clear of the centre, Next and Blackout (UIX-005-S1)
- [ ] UIX-005-T10 [US2] UI test AX5 (portrait): geometry and safe area (UIX-005-S2)

## Phase 3: User Story 3 (P2) — accessibility

- [ ] UIX-005-T11 [US3] UI test: `performAccessibilityAudit` (element description, hit region, contrast, Dynamic Type, traits) on the performance layout, with documented per-element filters only; B blacks out via the pad (UIX-005-S3, R8)

## Phase 4: Polish

- [ ] UIX-005-T12 Regressions: ShowCueUITests, TapTempoUITests, EmergencyBlackoutUITests, OutputBlackoutUITests; repo checks; type-check budget; spec status (UIX-005-S5)
- [ ] UIX-005-T13 {device} A performer's pass on D1 (portrait and landscape) and D2 (72 pt targets): every target hit without looking

## Dependencies

T01 → T02; T03 → T05 → T06, T07 → T08-T11 → T12. T04 before T05.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 T03/T06; R2 T05/T07; R3 T01/T05; R4 T01/T05/T07; R5-R6 T03/T08; R7 T04/T08; R8 T04/T07/T11;
R9 T05/T10; R10 T05/T11; R11 T07/T12. S1 T08/T09; S2 T10; S3 T11; S4 T02; S5 T12. Fixes applied: the
Reduce Motion edge case (spec) had no task (now in T07: no animation); acceptance scenario US1-6
(Standard layout restores the emergency button) had no test (now in T08). No constitution conflicts.
