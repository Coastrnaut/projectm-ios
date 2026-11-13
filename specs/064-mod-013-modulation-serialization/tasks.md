# Tasks: MOD-013 Modulation Serialization

**Input**: `specs/064-mod-013-modulation-serialization/` (spec, plan, research, data-model, contract)

Budgets (owner rule 7): each unit test about 1-2 s (≤ 10 s), each package suite < 1 minute. No
simulator or device task (no app code changes).

## Phase 1: Migration table (US3) — ParameterGraph

- [ ] MOD-013-T01 [US3] `ModulationIDMigrations` (rules, version, structural checks incl. loop path, `resolve`) in `Packages/ParameterGraph/Sources/ParameterGraph/ModulationIDMigrations.swift` (MOD-013-R2, R3; contract M1)
- [ ] MOD-013-T02 [US3] Registry carries the table: catalog checks (three new problems in `ParameterValidation.swift`), `resolveParameter`, `resolveAudioFeature` in `ParameterRegistry.swift` (MOD-013-R4; contract M2)
- [ ] MOD-013-T03 [US3] `ModulationIDMigrationTests`: chaining, idempotence, retire-after-rename, loop/self/duplicate/cross-kind/version refusals, catalog checks (MOD-013-S4)
- [ ] MOD-013-T04 [US3] `VisualParameterCatalog.migrations` (empty) passed to the registry in `Packages/VisualGenerators/Sources/VisualParameters/VisualParameterCatalog.swift`

## Phase 2: Document model (US2) — SceneFormat

- [ ] MOD-013-T05 [US2] `SceneBinding.sourceID`, `SceneNodeRef`, `SceneConnection`, `SceneModulation.connections` in `SceneDocument.swift`; decode keeps unknown audio IDs, encode writes them (MOD-013-R1, R11; research MOD-013-D5)
- [ ] MOD-013-T06 [US2] Update SCN-001 tests for the model change (decode error table: unknown audio source is no longer an error; fixtures, property generator)

## Phase 3: Per-edge restore (US1, US2, US4) — SceneFormat

- [ ] MOD-013-T07 [US1] `SceneModulationRestore.swift`: outcomes, report, preserved edges, issues, greedy loop rejection (MOD-013-R5, R7, R8; research MOD-013-D2, D3)
- [ ] MOD-013-T08 [US4] New issue codes and severities in `SceneIssue.swift`; `validate` uses the restore (contract M4)
- [ ] MOD-013-T09 [US1] `SceneLiveState`: applied edges, `preserved`, `modulationReport`, `apply(to:)`, `validatedGraph(registry:)`; capture order (MOD-013-R6, R9, R10; contract M5, M6)
- [ ] MOD-013-T10 [US4] Update SCN-001 validation/live tests for per-edge severities and paths

## Phase 4: Acceptance and properties

- [ ] MOD-013-T11 [US1] Acceptance: one document with every category → report outcomes and paths exact; scene opens; orphans and rejected preserved on re-save; dropped not (MOD-013-S1)
- [ ] MOD-013-T12 [US1] Restored edges evaluate like the original: 64 frames, fixed clock, bit-identical (MOD-013-S2)
- [ ] MOD-013-T13 [US3] Migration through a scene: twice-renamed target rewritten, re-saved with the new ID; retired-after-rename dropped
- [ ] MOD-013-T14 Seeded property test: 200 documents, fixed point after one capture, preserved edges survive, < 1 s (MOD-013-S3)

## Phase 5: Verification and docs

- [ ] MOD-013-T15 Mac host: `swift test` for ParameterGraph, SceneFormat, VisualGenerators; record counts and durations
- [ ] MOD-013-T16 Linux shape for the same three packages (MOD-013-R12)
- [ ] MOD-013-T17 Amend ADR-0028 (per-edge restore, severities, preserved edges) and ADR-0012 (migration table); spec status; `validate_docs.py`, `check_compliance.py`

## Dependencies

T01 → T02 → T03, T04; T05 → T06; T02 + T05 → T07 → T08 → T09 → T10 → T11-T14 → T15-T17.
