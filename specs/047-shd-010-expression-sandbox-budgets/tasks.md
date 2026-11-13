# Tasks: SHD-010 Expression Sandbox Budgets

**Input**: Design documents from `specs/047-shd-010-expression-sandbox-budgets/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/expression-budgets.md,
quickstart.md

**Tests**: Requested by the spec (SHD-010-S1-S5) and owner rule 7 budgets: a unit test about 1-2 s
and at most 10 s, the package suite under 1 minute, no wall-clock assertions.

**Format**: `[ID] [P?] [Story] Description`. One `{device}` task (left open).

## Phase 1: Setup

No setup: the `ParameterExpression` target and its test target exist (SHD-009-T01).

## Phase 2: Foundational (blocks every story)

- [X] SHD-010-T01 Cost table: `ExpressionLimits.cost(of:)` returns 4 for `sin cos sqrt pow smoothstep bandMean`, else 1; add `ExpressionLimits.firstLooserField(than:)` returning the first field (order source bytes, tokens, nodes, nesting, bindings, operation cost) whose value is above the given limits, with its label for contract B2, in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLimits.swift`; update `ExpressionLimitTests.testDefaults` for the new weight in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionLimitTests.swift` — Verified 2026-11-13: ExpressionLimitTests.testDefaults (cost table with `bandMean` 4, `firstLooserField`) and ExpressionFrameBudgetTests.testLooserLimitsAreRefused
- [X] SHD-010-T02 `ExpressionCompileWork` (`lexerSteps`, `parserSteps`, `compilerSteps`, `total`) and the contract B4 bound helpers in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCompileWork.swift` — Verified 2026-11-13: ExpressionCompileWorkTests.testCeilingAtTheStandardLimits (3,858 ≤ 4,096) and the bound checks below

## Phase 3: User Story 1 - A pathological formula never reaches the frame loop (P1) MVP

**Goal**: refusal with exact messages, bounded compile work, source text kept out of the frame path.
**Independent test**: `ExpressionPathologicalTests`, `ExpressionCompileWorkTests`.

- [X] SHD-010-T03 [US1] Lexer: check the length with `source.utf8.count` before copying any byte; for an oversized source compute the error position from the first `maximumSourceBytes` bytes only; count steps per contract B4 (1 + bytes visited per scan) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLexer.swift` — Verified 2026-11-13: ExpressionPathologicalTests.testOversizedSourceIsRefusedWithoutReadingIt (1,000,001-byte source: 513 lexer steps, 0 parser/compiler steps); lexer bounds in ExpressionCompileWorkTests
- [X] SHD-010-T04 [US1] Parser: count grammar-rule entries and token advances in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionParser.swift` — Verified 2026-11-13: ExpressionCompileWorkTests (parser ≤ 6t + 6 on every fixture, 500 fuzz sources, 9 growing shapes)
- [X] SHD-010-T05 [US1] Compiler: count nodes resolved, bindings named, dependency visits, references followed, loop-report steps and instructions emitted; replace the linear `audioSources.contains` with a set lookup (order unchanged) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCompiler.swift` — Verified 2026-11-13: ExpressionCompileWorkTests (compiler ≤ 5t, incl. the binding ring and chain shapes); SHD-009 suites unchanged and passing (audio-source order kept)
- [X] SHD-010-T06 [US1] `CompiledExpression.measure(source:limits:)` returning `(Result<CompiledExpression, ExpressionError>, ExpressionCompileWork)`; `init(source:limits:)` uses the same pipeline in `Packages/ParameterGraph/Sources/ParameterExpression/CompiledExpression.swift` — Verified 2026-11-13: ExpressionCompileWorkTests.testCountsAreDeterministic (measure and init give identical bytes and errors); all 38 ParameterExpression tests pass
- [X] SHD-010-T07 [P] [US1] Pathological fixture table of contract B3 (exact messages, accepted doubling chain with cost 63 and value 2¹⁵ × onset, bandMean cost) and the cost-equals-work check of contract B5 over every SHD-009 valid fixture; copy the exact positions into contract B3 and assert the frame set is unchanged after each refusal, in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionPathologicalTests.swift` — Verified 2026-11-13: ExpressionPathologicalTests 5/5 (13 fixtures, exact messages copied into contract B3; cost = Σ instruction costs over every valid fixture)
- [X] SHD-010-T08 [P] [US1] Compile-work tests: every B3 fixture and SHD-009 valid and rejected fixture within B4's per-phase bounds and the 4,096 ceiling; a 500-source fixed-seed fuzz within the bounds; doubling each adversarial shape (nesting under raised limits, flat sums, binding chains, long names) at most doubles the work plus a constant; two runs give identical counts in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionCompileWorkTests.swift` — Verified 2026-11-13: ExpressionCompileWorkTests 5/5 run (bench skipped by design): every fixture, 500-source fuzz, 9 doubling shapes ≤ 2× + 16, deterministic counts

## Phase 4: User Story 2 - The formulas of one frame fit a budget (P1)

**Goal**: per-frame count and cost budget checked at admission.
**Independent test**: `ExpressionFrameBudgetTests`.

- [X] SHD-010-T09 [US2] `ExpressionFrameBudget` (`maximumExpressions` 32, `maximumOperationCost` 2048, `expressionLimits` `.standard`), `ExpressionFrameSet` (admit: loosened limits, then count, then cost; set unchanged on refusal; handles from 1, never reused; remove frees cost), `ExpressionFrameSnapshot` (`evaluate(_:into:)` in admission order, `min(count, buffer)` results, no allocation (code review, as SHD-009-R9), no clock) and `ExpressionBudgetError` with contract B2 messages in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionFrameBudget.swift` — Verified 2026-11-13: ExpressionFrameBudgetTests 6/6; snapshot evaluation reviewed: no allocation, no clock, band mean summed once per call
- [X] SHD-010-T10 [US2] Accounting tests: fill the cost budget (8 × cost-256 formulas), the 9th refused with the exact message; fill the count budget (32 cheap formulas), the 33rd refused; removing one admits it again; stale or unknown handle removes nothing; looser-limit refusal names the first loosened field; tighter limits admitted; snapshot results equal individual evaluation in admission order; short buffer; empty snapshot; snapshot unchanged by later admissions in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionFrameBudgetTests.swift` — Verified 2026-11-13: ExpressionFrameBudgetTests 6/6 (cost, count, looser limits, admission order bit-identical to single evaluation, short buffer, empty snapshot)

## Phase 5: User Story 3 - The bound is documented and reproducible (P2)

- [X] SHD-010-T11 [US3] Informational host measurement `testInformationalHostCost` (skipped unless `PARAMETER_EXPRESSION_BENCH=1`; prints ns per cost unit for a full-budget snapshot and per opcode class, including `bandMean` over 128 bands; no assertion on time) in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionCompileWorkTests.swift`; record the figures in `research.md` SHD-010-D3/D4 — Verified 2026-11-13: `PARAMETER_EXPRESSION_BENCH=1 swift test -c release --filter ExpressionCompileWorkTests/testInformationalHostCost` on the M5 Max: full budget 0.8-1.7 µs per frame; it exposed the per-read band sum (10.73 ns/unit), fixed by summing once (0.39 ns/unit); figures in research SHD-010-D3/D4
- [X] SHD-010-T12 [US3] Amend ADR-0021 (Decision 5 cost table with `bandMean` 4; new Decision 9: frame budget, frame set and snapshot, compile-work bounds, SHD-002 out of scope; Consequences updated) in `docs/adr/0021-expression-mapping-language.md` — Verified 2026-11-13: ADR-0021 amended (Amended line, Decision 5 cost table, Decision 9, Consequences); validate_docs OK
- [ ] SHD-010-T13 {device} Measure per-frame expression cost on D1 (a full-budget snapshot, Release build) and record it in `docs/test-reports/performance.md` — open: needs the device

## Phase 6: Polish

- [X] SHD-010-T14 Run quickstart steps 1-3 (host tests, Linux shape, `check_compliance.py`, `validate_docs.py`) and `swift test --package-path Packages/VisualGenerators`; record counts and durations; mark the spec Implemented in `specs/047-shd-010-expression-sandbox-budgets/spec.md` — Verified 2026-11-13: `swift test --package-path Packages/ParameterGraph` 104 tests (66 + 38, 1 skipped) host and Linux shape (`-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), suite about 2 s; VisualGenerators 103 host and 81 Linux shape; check_compliance and validate_docs OK

## Dependencies

- T01, T02 → T03-T06 → T07, T08 (parallel).
- T01 → T09 → T10. US2 is independent of T03-T08.
- T11 after T09; T12 after T07-T10; T14 last. T13 needs D1.

## Parallel example

T07 and T08 are separate test files and can be written together once T06 builds; T09-T10 can
proceed alongside US1.

## Implementation Strategy

MVP = US1 (the acceptance criterion). US2 adds the per-frame budget; US3 documents it.
