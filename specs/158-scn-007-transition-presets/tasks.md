# Tasks: SCN-007 Scene Transition Presets

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/show-cue-transition.md](contracts/show-cue-transition.md)

## Phase 1: Model (US1, US2)

- [X] SCN-007-T01 Compositor: `SceneTransitionSpec.curve` and `SceneTransitionClock.curve` (MappingCurve), Codable only when set, `invalidCurve` error; Compositor target depends on ParameterGraph (SCN-007-R7) — Verified 2026-11-14: Compositor `SceneTransitionCurveTests` 4 tests; full Compositor suites pass (`swift test`, 0 failures); Linux shape builds
- [X] SCN-007-T02 Compositor tests: curve shapes eased progress on an injected frame clock; nil curve keeps CMP-014 encoding; invalid curve refused (SCN-007-S5) — Verified 2026-11-14: `SceneTransitionCurveTests` (eased progress = curve at 8 injected frames; legacy JSON bytes; invalid curve refused)
- [X] SCN-007-T03 Bus test: a curve spec drives `clock.easedProgress` and the mix at every frame (SCN-007-S5) — Verified 2026-11-14: `SceneTransitionBusTests.testACurveShapesTheBusTransition` (GPU, 0.05 s)
- [X] SCN-007-T04 ShowControl: `ShowTransitionType`, `ShowCueTransition` (validation), `ShowCue.transition`, `setTransition`, insert with transition; ShowControl depends on ParameterGraph (SCN-007-R1, R8) — Verified 2026-11-14: ShowControl `ShowTransitionDocumentTests.testModelBoundsAndValidation`, `testEditingNeverMovesThePositionAndDuplicateCopiesTheTransition`
- [X] SCN-007-T05 ShowControl: `show.json` per-cue `transition` encode/lenient decode, warnings (SCN-007-R2, R4) — Verified 2026-11-14: ShowControl `ShowTransitionDocumentTests` 7 tests; ShowControl 74 tests pass
- [X] SCN-007-T06 ShowControl tests: round trip bit-identical, legacy bytes, unknown type kept, invalid dropped, bounds (SCN-007-S2, S3) — Verified 2026-11-14: `ShowTransitionDocumentTests` (bit-identical round trip, legacy bytes, `wipeLeft` kept, 11 invalid values dropped, store reload)
- [X] SCN-007-T07 LibraryBackup test: backup round trip keeps transitions and bytes (SCN-007-R10, S4) — Verified 2026-11-14: `LibraryBackupTransitionTests` (exact restore: equal transitions, bit-identical duration, same show bytes); LibraryBackup 69 tests pass

## Phase 2: App (US1, US3)

- [X] SCN-007-T08 `CueTransitionResolver` and `CueTransitionDriving`; ShowCoordinator drives on apply, `setTransition`, Duplicate copies (SCN-007-R5, R6, R8) — Verified 2026-11-14: app `CueTransitionAcceptanceTests` 3 tests on SCN7 (spy order, unknown type → cut, duplicate copies, safety resolution)
- [X] SCN-007-T09 AppCoordinator wiring: safety state and a recording driver (DEBUG probe) (SCN-007-R5) — Verified 2026-11-14: build-for-testing on SCN7 (exit 0); `ShowCoordinatorTests`, `SceneRepairCoordinatorTests` and 7 other show suites, 50 tests pass
- [X] SCN-007-T10 Acceptance test: distinct transitions, save, reload with a new coordinator, exact equality, driver spy gets exact specs; safety resolution tests (SCN-007-S1) — Verified 2026-11-14: `CueTransitionAcceptanceTests.testReopeningTheShowRestoresTransitionsExactlyAndApplyDrivesThem` on SCN7
- [X] SCN-007-T11 `CueTransitionView` sheet and ShowEditorView row line and actions (SCN-007-R9) — Verified 2026-11-14: `CueTransitionUITests` on SCN7; regressions `SceneDuplicateUITests`, `ShowCueUITests` (2), `DynamicTypeInspectorUITests.testShowEditorAX5` pass
- [X] SCN-007-T12 UI test under 30 s: set a cue's transition, relaunch, values persist (SCN-007-S6) — Verified 2026-11-14: `CueTransitionUITests.testACueTransitionPersistsAcrossARelaunch` 29.6 s and 27.6 s on SCN7

## Phase 3: Polish

- [X] SCN-007-T13 Repo checks, type-check budget, privacy manifest and network symbols on the built app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK; check_privacy_manifest OK; check_network_symbols OK; no new type-check warnings in touched files
- [X] SCN-007-T14 Spec status, PosterBoard counts — Verified 2026-11-14: spec Status updated; PosterBoard reports 25 before, 25 after

## Dependencies

T01 → T02, T03, T08. T04 → T05 → T06, T07, T08. T08 → T09, T10, T11 → T12. All → T13 → T14.
