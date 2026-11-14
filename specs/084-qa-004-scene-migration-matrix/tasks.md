# Tasks: QA-004 Scene Migration Matrix

**Input**: Design documents from `specs/084-qa-004-scene-migration-matrix/` (spec, plan, research,
data-model, contracts/migration-matrix.md, contracts/scene-decode-errors.md, quickstart)

**Tests**: the feature is a test matrix; every runner is a test. Budgets (owner rule 7): each test
< 10 s, each package suite < 1 min. No UI test: no user-visible path changes.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [ ] QA-004-T01 Confirm the baseline in the worktree: `swift test` passes for Packages/SceneFormat, ShowControl, SceneArchive, RenderGoldens before changes; record counts

## Phase 2: Foundational (blocks every story)

- [ ] QA-004-T02 Write Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json per contracts/migration-matrix.md: 6 containers, chains `standard`, `test-v0`, `test-gap` (test-only), rows QA-004-M01 to M17 with exact outcomes, `errors` (11 entries) and `migrationErrors` (5 entries) per contracts/scene-decode-errors.md; a not-applicable reason is non-empty
- [ ] QA-004-T03 Write the SceneFormat matrix loader Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrix.swift: Decodable model, test-only chains by id, `bytes(row:base:)` (version, format, shape), expected cells per container, `refusal(sample:)` exhaustive sample switch

## Phase 3: User Story 1 + 2 — every cell ends in its documented outcome (P1)

- [ ] QA-004-T04 [P] [US1] [US2] decode and repairReport runners in Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrixTests.swift: every row through `SceneDocument.decode(_:migrator:)` and `SceneRepairReport.open(bytes:registry:migrator:)`; exact error value and message; exact log; canonical bytes vs expected; report entry code, group, severity, "if opened" vs `errors`; cell count equals the matrix
- [ ] QA-004-T05 [P] [US1] [US2] showStore runner in Packages/ShowControl/Tests/ShowControlTests/ShowStoreMigrationMatrixTests.swift: `ShowStore(directory:migrator:)` `.scene(_:)` (`.unreadable(e)`, migrated record) and `.load()` (`unreadableScenes`), file unchanged, no backup, in a temporary folder
- [ ] QA-004-T06 [US1] [US2] Archive seam: `migrator: SceneMigrator = .standard` on `SceneArchiveReader.read` in Packages/SceneArchive/Sources/SceneArchive/SceneArchiveReader.swift; runner Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveMigrationMatrixTests.swift (hand-built archives with fixture media for photo and video assets; `.sceneRefused(e)`)
- [ ] QA-004-T07 [P] [US1] [US2] golden runner in Packages/RenderGoldens/Tests/RenderGoldensTests/GoldenMigrationMatrixTests.swift: the 7 committed golden scenes through `GoldenSceneRenderer.document(from:)` on Metal hosts (`.sceneInvalid(e.message)`), `SceneDocument.decode` on Linux; test-chain rows not applicable
- [ ] QA-004-T08 [US1] [US2] autosave runner in Apps/projectM-iOS/Tests/SceneAutosaveMigrationMatrixTests.swift: `SceneAutosaveStore(directory:migrator:).load` events and source per contracts/scene-decode-errors.md; run on a dedicated simulator with `-only-testing`

## Phase 4: User Story 3 — the matrix cannot fall behind (P2)

- [ ] QA-004-T09 [US3] Meta-test Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrixMetaTests.swift: source scan of `SceneDecodeError` and `SceneMigrationError`; every case has an entry, a contract row and a sample whose report matches; version coverage (oldest…current, oldest−1, current+1, non-integer, missing); every standard step and manifest version has a row; runner files exist and name their container; each check fails on a broken in-memory copy

## Phase 5: Polish

- [ ] QA-004-T10 ADR-0028 QA-004 amendment in docs/adr/0028-scene-document-format.md: link the error table and matrix, "how to add a version" checklist; spec status
- [ ] QA-004-T11 Verify: touched package suites on the host and the Linux shape (timings), app runner on the simulator, `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`; PosterBoard count before and after

## Dependencies

T01 → T02 → T03 → {T04, T05, T06, T07, T08} → T09 → T10 → T11. T04, T05, T07 touch different
packages and can run in parallel; T06 changes production code (one parameter) and its runner.

## Implementation Strategy

MVP = T02-T04 (matrix, decode and report cells). Then the other containers, then the meta-test,
then docs and verification.
