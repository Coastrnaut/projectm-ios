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

- [ ] SHD-010-T01 Cost table: `ExpressionLimits.cost(of:)` returns 4 for `sin cos sqrt pow smoothstep bandMean`, else 1; add `ExpressionLimits.firstLooserField(than:)` returning the first field (order source bytes, tokens, nodes, nesting, bindings, operation cost) whose value is above the given limits, with its label for contract B2, in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLimits.swift`; update `ExpressionLimitTests.testDefaults` for the new weight in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionLimitTests.swift`
- [ ] SHD-010-T02 `ExpressionCompileWork` (`lexerSteps`, `parserSteps`, `compilerSteps`, `total`) and the contract B4 bound helpers in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCompileWork.swift`

## Phase 3: User Story 1 - A pathological formula never reaches the frame loop (P1) MVP

**Goal**: refusal with exact messages, bounded compile work, source text kept out of the frame path.
**Independent test**: `ExpressionPathologicalTests`, `ExpressionCompileWorkTests`.

- [ ] SHD-010-T03 [US1] Lexer: check the length with `source.utf8.count` before copying any byte; for an oversized source compute the error position from the first `maximumSourceBytes` bytes only; count steps per contract B4 (1 + bytes visited per scan) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLexer.swift`
- [ ] SHD-010-T04 [US1] Parser: count grammar-rule entries and token advances in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionParser.swift`
- [ ] SHD-010-T05 [US1] Compiler: count nodes resolved, bindings named, dependency visits, references followed, loop-report steps and instructions emitted; replace the linear `audioSources.contains` with a set lookup (order unchanged) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCompiler.swift`
- [ ] SHD-010-T06 [US1] `CompiledExpression.measure(source:limits:)` returning `(Result<CompiledExpression, ExpressionError>, ExpressionCompileWork)`; `init(source:limits:)` uses the same pipeline in `Packages/ParameterGraph/Sources/ParameterExpression/CompiledExpression.swift`
- [ ] SHD-010-T07 [P] [US1] Pathological fixture table of contract B3 (exact messages, accepted doubling chain with cost 63 and value 2¹⁵ × onset, bandMean cost) and the cost-equals-work check of contract B5 over every SHD-009 valid fixture in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionPathologicalTests.swift`
- [ ] SHD-010-T08 [P] [US1] Compile-work tests: every B3 fixture and SHD-009 valid and rejected fixture within B4's per-phase bounds and the 4,096 ceiling; a 500-source fixed-seed fuzz within the bounds; doubling each adversarial shape (nesting under raised limits, flat sums, binding chains, long names) at most doubles the work plus a constant; two runs give identical counts in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionCompileWorkTests.swift`

## Phase 4: User Story 2 - The formulas of one frame fit a budget (P1)

**Goal**: per-frame count and cost budget checked at admission.
**Independent test**: `ExpressionFrameBudgetTests`.

- [ ] SHD-010-T09 [US2] `ExpressionFrameBudget` (`maximumExpressions` 32, `maximumOperationCost` 2048, `expressionLimits` `.standard`), `ExpressionFrameSet` (admit: loosened limits, then count, then cost; set unchanged on refusal; handles from 1, never reused; remove frees cost), `ExpressionFrameSnapshot` (`evaluate(_:into:)` in admission order, `min(count, buffer)` results, no allocation, no clock) and `ExpressionBudgetError` with contract B2 messages in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionFrameBudget.swift`
- [ ] SHD-010-T10 [US2] Accounting tests: fill the cost budget (8 × cost-256 formulas), the 9th refused with the exact message; fill the count budget (32 cheap formulas), the 33rd refused; removing one admits it again; stale or unknown handle removes nothing; looser-limit refusal names the first loosened field; tighter limits admitted; snapshot results equal individual evaluation in admission order; short buffer; empty snapshot; snapshot unchanged by later admissions in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionFrameBudgetTests.swift`

## Phase 5: User Story 3 - The bound is documented and reproducible (P2)

- [ ] SHD-010-T11 [US3] Informational host measurement `testInformationalHostCost` (skipped unless `PARAMETER_EXPRESSION_BENCH=1`; prints ns per cost unit for a full-budget snapshot and per opcode class, including `bandMean` over 128 bands; no assertion on time) in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionCompileWorkTests.swift`; record the figures in `research.md` SHD-010-D3/D4
- [ ] SHD-010-T12 [US3] Amend ADR-0021 (Decision 5 cost table with `bandMean` 4; new Decision 9: frame budget, frame set and snapshot, compile-work bounds, SHD-002 out of scope; Consequences updated) in `docs/adr/0021-expression-mapping-language.md`
- [ ] SHD-010-T13 {device} Measure per-frame expression cost on D1 (a full-budget snapshot, Release build) and record it in `docs/test-reports/performance.md` — open: needs the device

## Phase 6: Polish

- [ ] SHD-010-T14 Run quickstart steps 1-3 (host tests, Linux shape, `check_compliance.py`, `validate_docs.py`) and `swift test --package-path Packages/VisualGenerators`; record counts and durations; mark the spec Implemented in `specs/047-shd-010-expression-sandbox-budgets/spec.md`

## Dependencies

- T01, T02 → T03-T06 → T07, T08 (parallel).
- T01 → T09 → T10. US2 is independent of T03-T08.
- T11 after T09; T12 after T07-T10; T14 last. T13 needs D1.

## Parallel example

T07 and T08 are separate test files and can be written together once T06 builds; T09-T10 can
proceed alongside US1.

## Implementation Strategy

MVP = US1 (the acceptance criterion). US2 adds the per-frame budget; US3 documents it.
