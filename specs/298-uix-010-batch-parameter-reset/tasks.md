# Tasks: UIX-010 Batch Parameter Reset

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/batch-reset.md](contracts/batch-reset.md)

## Phase 1: Foundational (reset core)

- [ ] UIX-010-T01 Add `ParameterResetSelection` (toggle, setAll, allSelected "non-empty and all contained", clear, count, button title and accessibility label) and `ParameterBatchReset` (lock check, `endCoalescing`, catalog-order writes through `ParameterInspectorTargets.target` skipping values equal to the default, one `recordStep`, labels and messages per contract B1) in `Apps/projectM-iOS/Coordinators/ParameterBatchReset.swift` (R3-R7, R9, D1-D4, D7)

## Phase 2: User Story 1 — reset several in one step (P1, MVP)

- [ ] UIX-010-T02 [US1] Acceptance tests in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift` with the real catalog, real AppSettings targets and a real `SceneHistoryCoordinator`: N = 4 and N = 2 changed parameters reset → all at default and exactly one new undo step ("Reset 4 Parameters"); one Undo restores every previous value; Redo resets again; unselected parameters and the bindings input unchanged; an earlier edit stays its own step (S1, S2; R3-R5)
- [ ] UIX-010-T03 [US1] Selection mode in `Apps/projectM-iOS/Views/ParameterSearchView.swift` and `Apps/projectM-iOS/Views/ParameterResetSelectionViews.swift`: Select/Done (`parameterReset.select`), toggle rows (`parameterResetToggle.<id>`, toggle trait, "Selected"/"Not selected"), read-only rows disabled, a bottom bar with the counted reset button (`parameterReset.reset`) and status (`parameterReset.status`), Undo/Redo in the toolbar; announce on the `.parameter` lane; end selection mode after a reset or refusal (R1, R8, R10)
- [ ] UIX-010-T04 [US1] Pass `history` and `announcer` from `Apps/projectM-iOS/Views/SettingsView.swift` into `ParameterSearchLinkSection` (one line)
- [ ] UIX-010-T05 [US1] UI test `Apps/projectM-iOS/UITests/ParameterBatchResetUITests.swift`: launched with bars 16 and horizontal orientation, select Bars and Orientation, Reset, values read 64 and Vertical, Undo once, values read 16 and Horizontal; under 30 s (S4)

## Phase 3: User Story 2 — select a whole group (P2)

- [ ] UIX-010-T06 [US2] Group header "Select All"/"Deselect All" (`parameterResetSelectAll.<group id>`) over the resettable rows of a section; leaving selection mode clears the selection; unit tests of `ParameterResetSelection` in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift` (R2)

## Phase 4: User Story 3 — nothing to do, or locked (P2)

- [ ] UIX-010-T07 [US3] Tests in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift`: already-default selection → `.alreadyAtDefaults`, "Already at defaults", zero new steps; locked scene → `.refused`, nothing written, zero steps, one lock refusal (S3; R6, R7)

## Phase 5: Polish

- [ ] UIX-010-T08 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget on the new files, `ParameterInspectorTests`, `ParameterSearchAppTests` and the UIX-009 UI test still pass
- [ ] UIX-010-T09 Mark the spec Implemented; final report
- [ ] UIX-010-T10 {device} On D1 with VoiceOver: each row reads as a toggle with its state, the reset button reads its count, and "Reset 2 parameters" is announced after a reset

## Dependencies

T01 → T02, T03 → T04 → T05; T06 and T07 after T01 (T06's view part after T03); T08 after all; T10 needs a device and a person. No new UserDefaults key (spec Assumptions), so no key lists change.

## Parallel opportunities

T02, T06's unit tests and T07 are one file written after T01; T03/T04 can proceed alongside them.
