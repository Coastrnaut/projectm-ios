# Tasks: UIX-010 Batch Parameter Reset

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/batch-reset.md](contracts/batch-reset.md)

## Phase 1: Foundational (reset core)

- [X] UIX-010-T01 Add `ParameterResetSelection` (toggle, setAll, allSelected "non-empty and all contained", clear, count, button title and accessibility label) and `ParameterBatchReset` (lock check, `endCoalescing`, catalog-order writes through `ParameterInspectorTargets.target` skipping values equal to the default, one `recordStep`, labels and messages per contract B1) in `Apps/projectM-iOS/Coordinators/ParameterBatchReset.swift` (R3-R7, R9, D1-D4, D7) — Verified 2026-11-15: `-only-testing:projectM-iOSTests/ParameterBatchResetTests` 7/7 pass (0.03 s) on the UIX10 iPhone 17 iOS 27.2 simulator

## Phase 2: User Story 1 — reset several in one step (P1, MVP)

- [X] UIX-010-T02 [US1] Acceptance tests in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift` with the real catalog, real AppSettings targets and a real `SceneHistoryCoordinator`: N = 4 and N = 2 changed parameters reset → all at default and exactly one new undo step ("Reset 4 Parameters"); one Undo restores every previous value; Redo resets again; unselected parameters and the bindings input unchanged; an earlier edit stays its own step; a selection with one value already at default counts only the changed ones in the label; with MOD-017 quantization on, a discrete reset is still written at once inside the one step (S1, S2; R3-R5, R9) — Verified 2026-11-15: testResetOfFourIsOneStepAndOneUndoRestoresAll, testPartlyDefaultSelectionCountsOnlyTheChangedOnes, testQueuedDiscreteChangeIsDroppedAndTheResetIsImmediate pass
- [X] UIX-010-T03 [US1] Selection mode in `Apps/projectM-iOS/Views/ParameterSearchView.swift` and `Apps/projectM-iOS/Views/ParameterResetSelectionViews.swift`: Select/Done (`parameterReset.select`), toggle rows (`parameterResetToggle.<id>`, toggle trait, "Selected"/"Not selected"), read-only rows disabled, a bottom bar with the counted reset button (`parameterReset.reset`) and status (`parameterReset.status`), Undo/Redo in the toolbar; announce on the `.parameter` lane; end selection mode after a reset or refusal (R1, R8, R10) — Verified 2026-11-15: ParameterBatchResetUITests passes (16.4 s): toggles with Selected/Not selected values, counted reset label, Undo in the list's toolbar labelled "Undo Reset 2 Parameters", selection mode ends after the reset
- [X] UIX-010-T04 [US1] Pass `history` and `announcer` from `Apps/projectM-iOS/Views/SettingsView.swift` into `ParameterSearchLinkSection` (one line) — Verified 2026-11-15: the UI test's Undo button and reset reach the history (build-for-testing succeeded)
- [X] UIX-010-T05 [US1] UI test `Apps/projectM-iOS/UITests/ParameterBatchResetUITests.swift`: launched with bars 16 and horizontal orientation, select Bars and Orientation, Reset, values read 64 and Vertical, Undo once, values read 16 and Horizontal; under 30 s (S4) — Verified 2026-11-15: `-only-testing:projectM-iOSUITests/ParameterBatchResetUITests` 1/1 pass (16.4 s)

## Phase 3: User Story 2 — select a whole group (P2)

- [X] UIX-010-T06 [US2] Group header "Select All"/"Deselect All" (`parameterResetSelectAll.<group id>`) over the resettable rows of a section; leaving selection mode clears the selection; unit tests of `ParameterResetSelection` in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift` (R2) — Verified 2026-11-15: testSelectionSelectAllAndLabels, testOnlyParametersWithAControlAreResettable pass; the UI test's hierarchy shows `parameterResetSelectAll.<group>` headers

## Phase 4: User Story 3 — nothing to do, or locked (P2)

- [X] UIX-010-T07 [US3] Tests in `Apps/projectM-iOS/Tests/ParameterBatchResetTests.swift`: already-default selection → `.alreadyAtDefaults`, "Already at defaults", zero new steps; locked scene → `.refused`, nothing written, zero steps, one lock refusal (S3; R6, R7) — Verified 2026-11-15: testAlreadyAtDefaultsAddsNoStep, testLockedSceneRefusesTheReset pass

## Phase 5: Polish

- [X] UIX-010-T08 Repo checks (compliance, docs, motion, permission catalog, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget on the new files, `ParameterInspectorTests`, `ParameterSearchAppTests` and the UIX-009 UI test still pass — Verified 2026-11-15: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events exit 0; test_scripts 186 tests OK; check_privacy_manifest and check_network_symbols OK on the Debug simulator app; no type-check warnings in the new or changed files (the one SettingsView warning, line 299 `inspectorReading`, 278 ms, predates this feature); ParameterBatchReset, ParameterQuantizerAcceptance, ParameterInspector, ParameterSearchApp, SceneHistoryCoordinator 33/33 pass; ParameterSearchUITests passes
- [X] UIX-010-T09 Mark the spec Implemented; final report — Verified 2026-11-15: spec Status set to Implemented; no ADR (no default overridden)
- [ ] UIX-010-T10 {device} On D1 with VoiceOver: each row reads as a toggle with its state, the reset button reads its count, and "Reset 2 parameters" is announced after a reset

## Dependencies

T01 → T02, T03 → T04 → T05; T06 and T07 after T01 (T06's view part after T03); T08 after all; T10 needs a device and a person. No new UserDefaults key (spec Assumptions), so no key lists change.

## Parallel opportunities

T02, T06's unit tests and T07 are one file written after T01; T03/T04 can proceed alongside them.

## speckit-analyze (2026-11-15)

Coverage: R1→T03/T05, R2→T06, R3→T02, R4→T02, R5→T02/T05, R6→T07, R7→T07, R8→T03/T10, R9→T01/T02, R10→T03/T05; S1→T02, S2→T02, S3→T07, S4→T05.
Findings applied: (1) MEDIUM: R9 (no quantization) had no test → added to T02. (2) MEDIUM: the edge case "some selected already at default" had no assertion → added to T02. (3) LOW: the edge case "rows hidden by a query stay selected" is covered by construction (the selection is a set of IDs independent of the visible rows); no separate test. No constitution conflict, no critical issue.
