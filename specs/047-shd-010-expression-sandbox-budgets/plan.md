# Implementation Plan: SHD-010 Expression Sandbox Budgets

**Branch**: `feature/shd-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/047-shd-010-expression-sandbox-budgets/spec.md`

## Summary

Extend the SHD-009 `ParameterExpression` target (no new target, no new import):

1. **Cost table**: `audio.bandMean` costs 4 (SHD-010-R1). A test proves cost = work: the sum of
   every compiled instruction's cost equals `operationCost`, and the instruction set has no jumps.
2. **Frame budget** (`ExpressionFrameBudget`, `.standard` = 32 formulas, cost 2,048, per-formula
   limits `ExpressionLimits.standard`), a mutable **frame set** (`ExpressionFrameSet`: `admit`
   returns a never-reused `Handle` or throws `ExpressionBudgetError`; `remove`) and an immutable,
   `Sendable` **frame snapshot** (`ExpressionFrameSnapshot.evaluate(_:into:)` writes results into a
   caller buffer in admission order; no allocation, no clock). Neither type accepts source text
   (SHD-010-R2 to R4, R8).
3. **Compile work counters** (`ExpressionCompileWork`: lexer, parser, compiler steps) threaded
   through the three phases; `CompiledExpression.measure(source:limits:)` returns the outcome and the
   work; `init(source:limits:)` runs the same path. Two linear-time fixes found by the audit: the
   length check uses `source.utf8.count` before copying any byte, and the error position for an
   oversized source scans only the first `maximumSourceBytes` bytes; the compiler's audio-source
   de-duplication uses a set instead of a linear `contains` (SHD-010-R5).
4. **Pathological fixtures** table with exact messages, budget accounting tests, counter-bound tests
   (fixtures, a 500-source seeded fuzz, doubling growth), determinism, and an informational host
   measurement run only on request (SHD-010-R6, R7, R10).
5. **ADR-0021 amended** (Decision 5 cost table, new Decision 9 budgets); SHD-002 generator graphs
   unchanged (Clarifications).

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI).

**Primary Dependencies**: `ParameterGraph` target; the C math library. Nothing new.

**Storage**: N/A.

**Testing**: XCTest, `swift test --package-path Packages/ParameterGraph` (host) and the Linux shape
(`swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL -Xswiftc
-DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`, which builds ParameterGraph; the
ParameterGraph tests have no platform conditionals and CI runs them on Linux).

**Target Platform**: iOS/iPadOS 26+, macOS 15 host, Linux.

**Project Type**: Swift package library target.

**Performance Goals**: per frame at most 2,048 cost units of formula evaluation (host time per unit
recorded as information); compile work ≤ the documented linear bound.

**Constraints**: no Foundation in the module; explicit closure types (CI's Xcode 26); no C stdio
globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; unit tests ≤ 10 s.

**Scale/Scope**: about 300 lines of source and 400 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Standard library only | Pass |
| VI. Modular boundaries | Changes stay in `ParameterExpression`; no dependant changes | Pass |
| VII. Real-time audio safety | Never in an audio callback; the snapshot's evaluation allocates nothing, takes no lock and reads no clock | Pass |
| VIII. Upstream fidelity | projectM untouched | Pass |
| X. Evidence | Unit tests on host and Linux shape; device cost task `{device}` left open | Pass |
| Security (untrusted input) | Bounded compile work, bounded per-frame work, refusal before evaluation; source text never reaches the frame path | Pass |
| Privacy / FR-068 | No data, no networking | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/047-shd-010-expression-sandbox-budgets/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/expression-budgets.md
└── checklists/requirements.md
docs/adr/0021-expression-mapping-language.md   (amended: Decision 5 cost table, Decision 9)
```

### Source Code (repository root)

```text
Packages/ParameterGraph/Sources/ParameterExpression/
├── ExpressionLimits.swift          # bandMean weight 4; isWithin(_:) / first loosened field
├── ExpressionCompileWork.swift     # NEW: step counters and documented bounds
├── ExpressionFrameBudget.swift     # NEW: budget, frame set, handle, snapshot, budget error
├── ExpressionLexer.swift           # length check before copying; step counting
├── ExpressionParser.swift          # step counting
├── ExpressionCompiler.swift        # step counting; set-based audio de-duplication
└── CompiledExpression.swift        # shared measured pipeline; measure(source:limits:)
Packages/ParameterGraph/Tests/ParameterExpressionTests/
├── ExpressionPathologicalTests.swift   # NEW: fixture table, cost = work
├── ExpressionFrameBudgetTests.swift    # NEW: accounting, refusals, snapshot evaluation
├── ExpressionCompileWorkTests.swift    # NEW: bounds, fuzz, doubling, determinism, bench (on request)
└── ExpressionLimitTests.swift          # updated cost table assertion
```

**Structure Decision**: everything stays in the SHD-009 target: budgets need only compiled formulas
and the cost table, and keeping them there keeps the source-scan test covering them.

## Complexity Tracking

None.
