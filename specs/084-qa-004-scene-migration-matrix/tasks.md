# Tasks: QA-004 Scene Migration Matrix

**Input**: Design documents from `specs/084-qa-004-scene-migration-matrix/` (spec, plan, research,
data-model, contracts/migration-matrix.md, contracts/scene-decode-errors.md, quickstart)

**Tests**: the feature is a test matrix; every runner is a test. Budgets (owner rule 7): each test
< 10 s, each package suite < 1 min. No UI test: no user-visible path changes.

A task is ticked `[X]` only when verified, with " — Verified <date>: <how>".

## Phase 1: Setup

- [X] QA-004-T01 Confirm the baseline in the worktree: `swift test` passes for Packages/SceneFormat, ShowControl, SceneArchive, RenderGoldens before changes; record counts — Verified 2026-11-13: `swift test` baseline on the host: SceneFormat 80/80 (2.8 s), ShowControl 30/30 (0.2 s), SceneArchive 25/25 (0.2 s), RenderGoldens 35/35 (2.8 s)

## Phase 2: Foundational (blocks every story)

- [X] QA-004-T02 Write Packages/SceneFormat/Tests/SceneFormatTests/Fixtures/legacy/matrix.json per contracts/migration-matrix.md: 6 containers, chains `standard`, `test-v0`, `test-gap` (test-only), rows QA-004-M01 to M17 with exact outcomes, `errors` (11 entries) and `migrationErrors` (5 entries) per contracts/scene-decode-errors.md; a not-applicable reason is non-empty — Verified 2026-11-13: matrix.json written (17 rows, 6 containers, 3 chains, 11 errors, 5 migration errors); SceneMigrationMatrixMetaTests.testMatrixAndErrorTableAreComplete passes
- [X] QA-004-T03 Write the SceneFormat matrix loader Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrix.swift: Decodable model, test-only chains by id, `bytes(row:base:)` (version, format, shape), expected cells per container, `refusal(sample:)` exhaustive sample switch — Verified 2026-11-13: SceneMigrationMatrixSupport.swift compiles and drives all six runners; byte-identical copies checked by testEveryContainerHasARunnerWithTheSharedSupportFile

## Phase 3: User Story 1 + 2 — every cell ends in its documented outcome (P1)

- [X] QA-004-T04 [P] [US1] [US2] decode and repairReport runners in Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrixTests.swift: every row through `SceneDocument.decode(_:migrator:)` and `SceneRepairReport.open(bytes:registry:migrator:)`; exact error value and message; exact log; canonical bytes vs expected; report entry code, group, severity, "if opened" vs `errors`; cell count equals the matrix — Verified 2026-11-13: SceneMigrationMatrixTests testDecodeContainer and testRepairReportContainer pass (host 0.03 s each, Linux shape); a mutated matrix (wrong message, wrong log line) makes both fail
- [X] QA-004-T05 [P] [US1] [US2] showStore runner in Packages/ShowControl/Tests/ShowControlTests/ShowStoreMigrationMatrixTests.swift: `ShowStore(directory:migrator:)` `.scene(_:)` (`.unreadable(e)`, migrated record) and `.load()` (`unreadableScenes`), file unchanged, no backup, in a temporary folder — Verified 2026-11-13: ShowStoreMigrationMatrixTests.testShowStoreContainer passes (0.04-0.06 s, host and Linux shape); ShowControl 31/31
- [X] QA-004-T06 [US1] [US2] Archive seam: `migrator: SceneMigrator = .standard` on `SceneArchiveReader.read` in Packages/SceneArchive/Sources/SceneArchive/SceneArchiveReader.swift; runner Packages/SceneArchive/Tests/SceneArchiveTests/SceneArchiveMigrationMatrixTests.swift (hand-built archives with fixture media for photo and video assets; `.sceneRefused(e)`) — Verified 2026-11-13: SceneArchiveMigrationMatrixTests (2) pass, all 11 fixtures packed with test media, default chain still refuses a v0 scene; SceneArchive 27/27 host and Linux shape
- [X] QA-004-T07 [P] [US1] [US2] golden runner in Packages/RenderGoldens/Tests/RenderGoldensTests/GoldenMigrationMatrixTests.swift: the 7 committed golden scenes through `GoldenSceneRenderer.document(from:)` on Metal hosts (`.sceneInvalid(e.message)`), `SceneDocument.decode` on Linux; test-chain rows not applicable — Verified 2026-11-13: GoldenMigrationMatrixTests (2) pass: harness path on the macOS host, decode path in the Linux shape; RenderGoldens 37/37 host, 25/25 Linux shape
- [X] QA-004-T08 [US1] [US2] autosave runner in Apps/projectM-iOS/Tests/SceneAutosaveMigrationMatrixTests.swift: `SceneAutosaveStore(directory:migrator:).load` events and source per contracts/scene-decode-errors.md; run on a dedicated simulator with `-only-testing` — Verified 2026-11-13: projectM-iOSTests SceneAutosaveMigrationMatrixTests 1/1 plus SceneAutosaveMigrationTests 7/7 on own simulator QA4 iPhone 17 (iOS 27.2), `-only-testing`, TEST SUCCEEDED; simulator deleted

## Phase 4: User Story 3 — the matrix cannot fall behind (P2)

- [X] QA-004-T09 [US3] Meta-test Packages/SceneFormat/Tests/SceneFormatTests/SceneMigrationMatrixMetaTests.swift: source scan of `SceneDecodeError` and `SceneMigrationError`; every case has an entry, a contract row and a sample whose report matches; version coverage (oldest…current, oldest−1, current+1, non-integer, missing); every standard step and manifest version has a row; runner files exist and name their container; each check fails on a broken in-memory copy — Verified 2026-11-13: SceneMigrationMatrixMetaTests 4/4 (host and Linux shape): source scan finds 11 + 5 cases, completeness passes, 14 broken copies each caught

## Phase 5: Polish

- [X] QA-004-T10 ADR-0028 QA-004 amendment in docs/adr/0028-scene-document-format.md: link the error table and matrix, "how to add a version" checklist; spec status — Verified 2026-11-13: ADR-0028 QA-004 amendment with the error-table link and the 5-step checklist; `python3 scripts/validate_docs.py` OK
- [X] QA-004-T11 Verify: touched package suites on the host and the Linux shape (timings), app runner on the simulator, `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`; PosterBoard count before and after — Verified 2026-11-13: SceneFormat 86/86 (host 3.4 s, Linux shape 5.8 s), ShowControl 31/31 (0.6 s / 0.5 s), SceneArchive 27/27 (0.2 s / 0.2 s), RenderGoldens 37/37 host (3.2 s) and 25/25 Linux shape (0.4 s); app runner 0.05 s; check_compliance OK, validate_docs OK; PosterBoard reports 32 before and after

## Dependencies

T01 → T02 → T03 → {T04, T05, T06, T07, T08} → T09 → T10 → T11. T04, T05, T07 touch different
packages and can run in parallel; T06 changes production code (one parameter) and its runner.

## Implementation Strategy

MVP = T02-T04 (matrix, decode and report cells). Then the other containers, then the meta-test,
then docs and verification.
