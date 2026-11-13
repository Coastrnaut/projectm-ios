# Tasks: SCN-013 Scene Migration

**Input**: Design documents from `specs/081-scn-013-scene-migration/` (spec, plan, research,
data-model, contracts/scene-migration.md, quickstart)

**Tests**: requested by the spec (SCN-013-S1 to S5). Budgets (owner rule 7): unit ≤ 10 s, suite
< 1 min. No UI test: no user-visible path changes.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] SCN-013-T01 Confirm the worktree baseline: `swift test --package-path Packages/SceneFormat` passes before changes; count PosterBoard reports before any simulator run — Verified 2026-11-13: baseline `swift test --package-path Packages/SceneFormat` 67/67 on the host (1.9 s); PosterBoard reports 32 before

## Phase 2: Foundational (the chain, blocks every story)

- [X] SCN-013-T02 Implement `SceneMigrationChange`, `SceneMigrationLogEntry`, `SceneMigrationRecorder`, `SceneMigrationStep`, `SceneMigrator` (`standard`, `migrate`), `SceneMigrationRecord`, `SceneMigrationError` in Packages/SceneFormat/Sources/SceneFormat/SceneMigration.swift, Foundation-free (contract M2, M3); add the file to SceneSourceSafetyTests — Verified 2026-11-13: SceneMigrationTests 9/9 and SceneSourceSafetyTests (SceneMigration.swift listed, no Foundation) pass on the host and the Linux shape
- [X] SCN-013-T03 Run the migrator inside `SceneDocument.decode` (new `decode(_:migrator:)`), add `migration` to `SceneDecodeResult` and `SceneDecodeError.migrationFailed` with its message and SCN-012 refusal name in Packages/SceneFormat/Sources/SceneFormat/SceneDecoding.swift, SceneIssue.swift, SceneRepair.swift (contract M1) — Verified 2026-11-13: testDecodeMapsMigrationRefusalsToDecodeErrors, testFullDecodeMigratesAndRecords pass; SceneFormat 80/80 host (4.3 s) and Linux shape (2.8 s)

## Phase 3: User Story 1 + 3 + 4 — chain, log and refusals (P1, P2), pure

- [X] SCN-013-T04 [P] [US3] [US4] Synthetic chain tests in Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationTests.swift (steps labelled test-only): v1→v2→v3 rename/add/transform with ordered log, unknown fields kept, version written by the migrator, newer refused, gap refused, failing step refused with step and path, version 0 invalid with the production chain, a v0→v1 test chain through the full `decode(_:migrator:)`, `SceneMigrator.standard` has no steps and targets `currentVersion` (S3, R4, R6) — Verified 2026-11-13: SceneMigrationTests (chain order and log, mid-chain start, unchanged current, refusals, full decode v0→v1 test chain, standard chain empty) pass, 0.003 s total
- [X] SCN-013-T05 [US3] SCN-012 note: `Group.formatUpdated` and the `migration.updated` note entry in `SceneRepairReport.open` for a migrated document; test that it is a note and `needsReview` stays false (R11) — Verified 2026-11-13: testReportOfAMigratedSceneHasOneNoteThatNeedsNoReview, testMigrationFailureIsACannotOpenUnsupportedVersionEntry pass
- [X] SCN-013-T06 [US1] Golden legacy fixtures under Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/ (manifest, v1 inputs from the real writers, expected canonical documents) and SceneLegacyFixtureTests: exact expected bytes, leaf-by-leaf no data loss against the log, coverage tags complete, each row's source names a real writer (S1, R12, R13) — Verified 2026-11-13: SceneLegacyFixtureTests 4/4 (0.039 s): 11 version-1 fixtures (7 QA-002 scenes copied verbatim, all-kinds, unknown audio feature, empty, hand-written) decode to their expected bytes; 10 canonical inputs are byte-identical to their expected files (`cmp`), the hand-written expected file was reviewed by hand; no leaf lost; coverage complete; the checker catches an unlogged loss

## Phase 4: User Story 2 — backups (P1)

- [ ] SCN-013-T07 [US2] ShowStore: back up a migrated stored scene once before `saveScene` replaces it; refuse the save if the backup fails; remove backups with unreferenced scenes, in Packages/ShowControl/Sources/ShowStorage/ShowStore.swift; tests in Packages/ShowControl/Tests/ShowControlTests/ShowStoreMigrationBackupTests.swift with a test-only migrator seam (R8, R9, R15)
- [ ] SCN-013-T08 [US2] [US3] SceneAutosaveStore: remember migrated originals at load, write `<name>.v<N>.backup` before the save that replaces or removes them, `keepOriginal` step on failure, `migrated` and `keptOriginal` events without content, in Apps/projectM-iOS/Coordinators/SceneAutosaveStore.swift; app unit tests in Apps/projectM-iOS/Tests/SceneAutosaveMigrationTests.swift (temporary folder; load alone writes no file) (R7-R10, S2, S4)

## Phase 5: Polish

- [ ] SCN-013-T09 Run SceneFormat tests on the host and the Linux shape, ShowControl tests, the app unit tests on an own simulator; check suite durations (S5); PosterBoard count after
- [ ] SCN-013-T10 Amend docs/adr/0028-scene-document-format.md (migration chain, backups, audit log, the procedure for a new version); spec status; `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`

## Dependencies

T01 → T02 → T03 → (T04, T05, T06 in parallel) → T07, T08 → T09 → T10. T07 and T08 need T03's
decode record.

## Implementation strategy

The pure chain and the fixtures first (the row's acceptance); then the two stores' backups.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: R1-R3 T02; R4 T04; R5 T03 (every reader goes through `decode`: SceneAutosaveStore,
ShowStore, SceneArchiveReader, SceneRepairReport.open, GoldenSceneRenderer); R6 T04; R7 T07/T08;
R8-R10 T07/T08; R11 T05; R12-R13 T06; R14 T02; R15 T07. S1 T06, S2 T07/T08, S3 T04, S4 T08, S5 T09.
Fixes applied: R6 and R7 had no explicit test (added to T04 and T08). No constitution conflict;
no ambiguity left (six clarifications). Archives need no backup (read-only sources, spec edge case).
