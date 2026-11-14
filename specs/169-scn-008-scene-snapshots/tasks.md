# Tasks: SCN-008 Scene Snapshots

**Input**: [spec.md](spec.md), [plan.md](plan.md), [contracts/scene-snapshots.md](contracts/scene-snapshots.md)

## Phase 1: Model (US2)

- [ ] SCN-008-T01 SceneFormat: `SceneSnapshotEntry`, `SceneSnapshot`, limits, `read`, editing helpers, reserved action ID (SCN-008-R1, R3, R11)
- [ ] SCN-008-T02 SceneFormat: `snapshots` on the document, decode (count limit), encode only when set, live state and capture carry it (SCN-008-R2)
- [ ] SCN-008-T03 SceneFormat: `invalidSnapshot`, `unknownSnapshotParameter` codes, validation and SCN-012 classification (SCN-008-R4)
- [ ] SCN-008-T04 SceneFormat: `SceneSnapshotRecallPlan` (unknown, not settable, rejected, clamped; sorted) (SCN-008-R6, R7)
- [ ] SCN-008-T05 SceneFormat tests: byte-identical round trip, legacy bytes, unknown fields kept, invalid entries and limit, unknown parameter reported and skipped, editing limits and names (SCN-008-S2, S3, S4)

## Phase 2: App (US1, US3)

- [ ] SCN-008-T06 SCN-002 carry: `snapshots` restored and written back; `snapshotEntries`, `replaceSnapshots` commit at once (SCN-008-R10)
- [ ] SCN-008-T07 SCN-010: `SceneHistoryCoordinator.recordStep(label:)` (SCN-008-R6)
- [ ] SCN-008-T08 `SceneSnapshotCoordinator` (save, rename, delete, recall via the Settings write path, one undo step, skipped report, library-lane announcements) and AppCoordinator wiring (SCN-008-R5 to R8)
- [ ] SCN-008-T09 DEBUG `MediaLoadSpy` at photo, video, logo and host-creation points (SCN-008-R6)
- [ ] SCN-008-T10 Acceptance test: photo scene, S1 with intensity 0.2 / radius 0.05, change, recall exact, zero media loads, inputs unchanged, one undo step; limit; unknown parameter skipped; commit and restore keeps snapshots (SCN-008-S1, S4)
- [ ] SCN-008-T11 `SceneSnapshotsSection` in Settings: Save, rows, Recall, Rename, Delete (confirmed), VoiceOver actions, DEBUG probe (SCN-008-R9)
- [ ] SCN-008-T12 UI test under 30 s: save, change intensity, recall, value label restored, media probe unchanged (SCN-008-S5)

## Phase 3: Polish

- [ ] SCN-008-T13 Repo checks, type-check budget, privacy manifest and network symbols on the built app
- [ ] SCN-008-T14 Spec status, PosterBoard counts

## Dependencies

T01 → T02 → T03, T04 → T05. T02 → T06. T04, T06, T07 → T08 → T10, T11 → T12. T09 → T10, T12. All → T13 → T14.
