# Tasks: MOD-013 Modulation Serialization

**Input**: `specs/064-mod-013-modulation-serialization/` (spec, plan, research, data-model, contract)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each package suite < 1 minute. No
simulator or device task (no app code changes).

## Phase 1: Migration table (US3) — ParameterGraph

- [X] MOD-013-T01 [US3] `ModulationIDMigrations` (rules, version, structural checks incl. loop path, `resolve`) in `Packages/ParameterGraph/Sources/ParameterGraph/ModulationIDMigrations.swift` (MOD-013-R2, R3; contract M1) — Verified 2026-11-13: `swift test --package-path Packages/ParameterGraph` (71 + 38 tests pass; ModulationIDMigrationTests 5)
- [X] MOD-013-T02 [US3] Registry carries the table: catalog checks (three new problems in `ParameterValidation.swift`), `resolveParameter`, `resolveAudioFeature` in `ParameterRegistry.swift` (MOD-013-R4; contract M2) — Verified 2026-11-13: ModulationIDMigrationTests.testRegistryAppliesTheTableAndTheRetiredSet, testRegistryRefusesTablesThatContradictTheCatalog
- [X] MOD-013-T03 [US3] `ModulationIDMigrationTests`: chaining, idempotence, retire-after-rename, loop/self/duplicate/cross-kind/version refusals, catalog checks (MOD-013-S4) — Verified 2026-11-13: 5 tests pass in 0.003 s on the Mac host
- [X] MOD-013-T04 [US3] `VisualParameterCatalog.migrations` (empty) passed to the registry in `Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift` — Verified 2026-11-13: `swift test --package-path Packages/VisualGenerators` (103 tests pass, catalog builds with the table)

## Phase 2: Document model (US2) — SceneFormat

- [X] MOD-013-T05 [US2] `SceneBinding.sourceID`, `SceneNodeRef`, `SceneConnection`, `SceneModulation.connections` in `SceneDocument.swift`; decode keeps unknown audio IDs, encode writes them (MOD-013-R1, R11; research MOD-013-D5) — Verified 2026-11-13: `swift test --package-path Packages/SceneFormat` (31 tests pass; round-trip and property tests unchanged)
- [X] MOD-013-T06 [US2] Update SCN-001 tests for the model change (decode error table: unknown audio source is no longer an error; fixtures, property generator) — Verified 2026-11-13: SceneDecodeErrorTests, SceneFixtures, ScenePropertyTests, SceneSourceSafetyTests updated; 31 tests pass

## Phase 3: Per-edge restore (US1, US2, US4) — SceneFormat

- [X] MOD-013-T07 [US1] `SceneModulationRestore.swift`: outcomes, report, preserved edges, issues, greedy loop rejection (MOD-013-R5, R7, R8; research MOD-013-D2, D3) — Verified 2026-11-13: SceneModulationRestoreTests.testEveryCategoryIsReportedWithItsPath, testMalformedIDsAreRejectedNeverOrphaned
- [X] MOD-013-T08 [US4] New issue codes and severities in `SceneIssue.swift`; `validate` uses the restore (contract M4) — Verified 2026-11-13: SceneValidationTests.testBindingExpressionAndModulationIssues (severity per code, cycle at its connection path, generator duplicate still an error)
- [X] MOD-013-T09 [US1] `SceneLiveState`: applied edges, `preserved`, `modulationReport`, `apply(to:)`, `validatedGraph(registry:)`; capture order (MOD-013-R6, R9, R10; contract M5, M6) — Verified 2026-11-13: SceneModulationRestoreTests (apply(to:), validatedGraph(registry:), capture order and fixed point)
- [X] MOD-013-T10 [US4] Update SCN-001 validation/live tests for per-edge severities and paths — Verified 2026-11-13: SceneValidationTests and SceneLiveAdapterTests pass with per-edge severities (31 tests)

## Phase 4: Acceptance and properties

- [X] MOD-013-T11 [US1] Acceptance: one document with every category → report outcomes and paths exact; scene opens; orphans and rejected preserved on re-save; dropped not (MOD-013-S1) — Verified 2026-11-13: SceneModulationRestoreTests.testEveryCategoryIsReportedWithItsPath and testReSavingKeepsOrphansWritesMigratedIDsAndReachesAFixedPoint
- [X] MOD-013-T12 [US1] Restored edges evaluate like the original: 64 frames, fixed clock, bit-identical (MOD-013-S2) — Verified 2026-11-13: SceneModulationRestoreTests.testRestoredEdgesEvaluateLikeTheOriginal (64 frames, 256 bit-identical values)
- [X] MOD-013-T13 [US3] Migration through a scene: twice-renamed target rewritten, re-saved with the new ID; retired-after-rename dropped — Verified 2026-11-13: SceneModulationRestoreTests.testMigrationThroughAScene
- [X] MOD-013-T14 Seeded property test: 200 documents, fixed point after one capture, preserved edges survive, < 1 s (MOD-013-S3) — Verified 2026-11-13: SceneModulationPropertyTests (200 seeded documents, 0.12 s, every outcome > 10 times)

## Phase 5: Verification and docs

- [X] MOD-013-T15 Mac host: `swift test` for ParameterGraph, SceneFormat, VisualGenerators; record counts and durations — Verified 2026-11-13: Mac host: ParameterGraph 71 + 38 tests (3.4 s wall), SceneFormat 37 tests (0.70 s, 2.7 s wall), VisualGenerators 103 tests (14.8 s)
- [X] MOD-013-T16 Linux shape for the same three packages (MOD-013-R12) — Verified 2026-11-13: Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`, `.build/linuxshape`): ParameterGraph 71 + 38, SceneFormat 37, VisualGenerators 81, all pass
- [X] MOD-013-T17 Amend ADR-0028 (per-edge restore, severities, preserved edges) and ADR-0012 (migration table); spec status; `validate_docs.py`, `check_compliance.py` — Verified 2026-11-13: ADR-0028 and ADR-0012 amended; `validate_docs.py` OK, `check_compliance.py` OK

## Dependencies

T01 → T02 → T03, T04; T05 → T06; T02 + T05 → T07 → T08 → T09 → T10 → T11-T14 → T15-T17.

## Analysis (speckit-analyze, 2026-11-13)

Coverage: MOD-013-R1 T05; R2-R3 T01, T03; R4 T02, T03; R5 T07, T11; R6 T09, T12; R7 T07, T11; R8 T07,
T11; R9 T09, T11; R10 T09, T14; R11 T05, T11; R12 T16. S1 T11; S2 T12; S3 T14; S4 T03, T15, T16.
Fixed: a vague capture-order clause in Clarifications (now "recorded in ADR-0028") and S1's
category count (now "all 7 cases", with the generator-declaration exception stated). No conflict with
the constitution; SCN-001-R11 is narrowed for modulation edges by the recorded clarification and the
ADR-0028 amendment (T17).
