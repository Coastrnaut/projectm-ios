# Tasks: SCN-008 Scene Snapshots

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/scene-snapshots.md](contracts/scene-snapshots.md)

## Phase 1: Model (US2)

- [X] SCN-008-T01 SceneFormat: `SceneSnapshotEntry`, `SceneSnapshot`, limits, `read`, editing helpers, reserved action ID (SCN-008-R1, R3, R11) — Verified 2026-11-14: SceneFormat `SceneSnapshotTests.testLimitsAndEditing`, `testSnapshotsRoundTripByteIdenticallyAndReadExactly`
- [X] SCN-008-T02 SceneFormat: `snapshots` on the document, decode (count limit), encode only when set, live state and capture carry it (SCN-008-R2) — Verified 2026-11-14: `SceneSnapshotTests` (byte-identical round trip, legacy bytes, live state and capture carry the list, 65 entries → `tooMany`)
- [X] SCN-008-T03 SceneFormat: `invalidSnapshot`, `unknownSnapshotParameter` codes, validation and SCN-012 classification (SCN-008-R4) — Verified 2026-11-14: `SceneSnapshotTests.testUnusableEntriesAndUnknownParametersAreReportedAndKept` (codes, paths, warnings only, repair report entries)
- [X] SCN-008-T04 SceneFormat: `SceneSnapshotRecallPlan` (unknown, not settable, rejected, clamped; sorted) (SCN-008-R6, R7) — Verified 2026-11-14: `SceneSnapshotTests.testRecallPlanSkipsUnsettableAndRejectedValuesAndClamps` and the unknown-parameter case
- [X] SCN-008-T05 SceneFormat tests: byte-identical round trip, legacy bytes, unknown fields kept, invalid entries and limit, unknown parameter reported and skipped, editing limits and names (SCN-008-S2, S3, S4) — Verified 2026-11-14: `swift test` in Packages/SceneFormat: 156 tests, 0 failures after adding `SceneSnapshots.swift` to `SceneSourceSafetyTests` (13.8 s)

## Phase 2: App (US1, US3)

- [X] SCN-008-T06 SCN-002 carry: `snapshots` restored and written back; `snapshotEntries`, `replaceSnapshots` commit at once (SCN-008-R10) — Verified 2026-11-14: app `SceneSnapshotAcceptanceTests.testSnapshotsSurviveCommitAndRestore` on SCN8 (commit at once, restore by a new coordinator, byte-identical)
- [X] SCN-008-T07 SCN-010: `SceneHistoryCoordinator.recordStep(label:)` (SCN-008-R6) — Verified 2026-11-14: `SceneSnapshotAcceptanceTests.testRecallRestoresMappedValuesWithoutReloadingMedia` (undo label "Recall S1", one undo restores both values, the earlier edit stays its own step); `SceneHistoryCoordinatorTests` pass
- [X] SCN-008-T08 `SceneSnapshotCoordinator` (save, rename, delete, recall via the Settings write path, one undo step, skipped report, library-lane announcements) and AppCoordinator wiring (SCN-008-R5 to R8) — Verified 2026-11-14: `SceneSnapshotAcceptanceTests` 3 tests on SCN8 (0.04 s) through the app's own `connect`; 117 tests in 20 related app suites pass
- [X] SCN-008-T09 DEBUG `MediaLoadSpy` at photo, video, logo and host-creation points (SCN-008-R6) — Verified 2026-11-14: build-for-testing on SCN8; `SceneSnapshotUITests` reads the probe before and after a recall with a stored photo (equal)
- [X] SCN-008-T10 Acceptance test: photo scene, S1 with intensity 0.2 / radius 0.05, change, recall exact, zero media loads, inputs unchanged, one undo step; limit; unknown parameter skipped; commit and restore keeps snapshots (SCN-008-S1, S4) — Verified 2026-11-14: `SceneSnapshotAcceptanceTests` (exact 0.2 / 0.05, spy counts unchanged, media inputs identical, one undo step, limit, unknown parameter skipped and announced)
- [X] SCN-008-T11 `SceneSnapshotRows` in Settings › Visual: Save, rows, Recall, Rename, Delete (confirmed), VoiceOver actions, DEBUG probe (SCN-008-R9) — Verified 2026-11-14: `SceneSnapshotUITests` on SCN8; AX audit `AccessibilityScreensUITests.testSettingsAndShowEditorAreLabelledAndPassTheAudit` and `DynamicTypeInspectorUITests.testSettingsAX5`, `testLinearSpectrumRowsAX5` pass
- [X] SCN-008-T12 UI test under 30 s: save, change intensity, recall, value label restored, media probe unchanged (SCN-008-S5) — Verified 2026-11-14: `SceneSnapshotUITests.testSaveChangeRecallRestoresTheValueWithoutReloadingMedia` 24.5 s, 18.3 s, 17.6 s on SCN8

## Phase 3: Polish

- [X] SCN-008-T13 Repo checks, type-check budget, privacy manifest and network symbols on the built app — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest OK and check_network_symbols OK on the Debug simulator app; no type-check warnings in touched files (SettingsView.swift:251 `inspectorReading`, untouched, measured 192-205 ms on a loaded Mac)
- [X] SCN-008-T14 Spec status, PosterBoard counts — Verified 2026-11-14: spec Status updated; PosterBoard reports 25 before, 25 after

## Dependencies

T01 → T02 → T03, T04 → T05. T02 → T06. T04, T06, T07 → T08 → T10, T11 → T12. T09 → T10, T12. All → T13 → T14.
