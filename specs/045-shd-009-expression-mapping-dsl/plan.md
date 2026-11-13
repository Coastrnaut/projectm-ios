# Implementation Plan: SHD-009 Expression Mapping DSL

**Branch**: `feature/shd-009` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/045-shd-009-expression-mapping-dsl/spec.md`

## Summary

Add a `ParameterExpression` target (and library product) to `Packages/ParameterGraph`. It depends
only on the `ParameterGraph` target (for MOD-002's `AudioFeatureSource` names and frames and
MOD-003's `LinearMapping`) and the platform C math library; it does not import Foundation, so the
system expression evaluator (`NSExpression`), script engines and dynamic loading are not even in
scope. A hand-written lexer and recursive-descent parser turn a formula (optional declarative
`let` bindings, then one expression over `+ - * /`, unary `+ -`, parentheses, numbers, the closed
identifier set and 13 whitelisted functions) into a small tree; the compiler resolves names,
checks argument counts, rejects recursive bindings with a readable path, orders bindings by
dependency and emits a closed stack-machine instruction list with its static operation cost,
stack size and byte form. `CompiledExpression.evaluate` runs the instructions over a stack-allocated
scratch buffer (no heap allocation), making every intermediate result finite. `ExpressionMapping`
adapts a compiled formula to MOD-003's output range. Every limit (length, tokens, nodes, nesting,
bindings, operation cost) is enforced with a `line:column: reason` error. Tests: valid table,
rejection table with exact messages, limits at and over the bound, numeric safety, determinism,
a seeded fuzz and a source scan, on the host and in the Linux build shape. A new ADR records the
language's safety design for SHD-010 and SHD-011.

## Technical Context

**Language/Version**: Swift 6 (tools 6.0; Xcode 27.2 on the build Mac, Xcode 26 in CI).

**Primary Dependencies**: `ParameterGraph` target (MOD-002 `AudioFeatureSource`,
`AudioFeatureFrame`; MOD-003 `LinearMapping`); the C math library (`Darwin`/`Glibc`/`Musl`) for
`sin`, `cos`, `pow`. Tests add Foundation (source scan only).

**Storage**: N/A (a formula is a string value; saving it is a later row).

**Testing**: XCTest via `swift test --package-path Packages/ParameterGraph` on the Mac host; the
Linux shape through `swift test --package-path Packages/VisualGenerators -Xswiftc -DVISUAL_NO_METAL
-Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape` (which builds ParameterGraph as
a dependency) plus the ParameterGraph tests, which have no platform conditionals; CI runs
ParameterGraph's tests on Linux.

**Target Platform**: iOS/iPadOS 26+, macOS 15 host for tests, Linux.

**Project Type**: Swift package library target.

**Performance Goals**: Compile once (microseconds for a 512-byte formula); evaluation runs at most
the static operation cost (≤ 256 weighted instructions) with no heap allocation, suitable for the
render thread (SHD-010 adds time budgets per expression graph).

**Constraints**: No Foundation in the module; no `NSExpression`, JavaScriptCore, `dlopen`/`dlsym`,
`Process`, Metal or shader compilation; deterministic compile and evaluation; tests within owner
rule 7 (unit ≤ 10 s, suite < 1 min); explicit closure types for CI's Xcode 26 type checker; no C
stdio globals.

**Scale/Scope**: about 900 lines of source and 700 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I. Public Apple APIs only | Swift standard library and the C math library only; no `dlopen`/`dlsym`, no private API | Pass |
| VI. Modular boundaries | New target depends on `ParameterGraph` only; `ParameterGraph` itself and its consumers (VisualGenerators, Compositor, PerformanceControl) are unchanged | Pass |
| VII. Real-time audio safety | Never runs in an audio callback; evaluation allocates nothing and is bounded, so it is safe on the render path | Pass |
| VIII. Upstream fidelity | projectM untouched; preset equations stay the engine's | Pass |
| X. Evidence | Host and Linux-shape unit tests; no device claims | Pass |
| Security (untrusted input) | A formula is data: closed identifiers and functions, bounded size and work, no recursion, no code path from text to code (SHD-009-R11), source scan test; designed for SHD-011 imports | Pass |
| Privacy | No data stored or sent | Pass |
| FR-068 (no networking) | No networking API (scan) | Pass |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/045-shd-009-expression-mapping-dsl/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/expression-language.md
└── checklists/requirements.md
docs/adr/00NN-expression-mapping-language.md   (next free number, checked across branches at commit)
```

### Source Code (repository root)

```text
Packages/ParameterGraph/
├── Package.swift                                  # + ParameterExpression target, tests, product
├── Sources/ParameterExpression/
│   ├── ExpressionLimits.swift                     # limits value, defaults, operation costs
│   ├── ExpressionError.swift                      # position, reason, messages
│   ├── ExpressionLexer.swift                      # bytes → tokens (numbers, names, punctuation)
│   ├── ExpressionParser.swift                     # tokens → bindings + tree (nesting, node limits)
│   ├── ExpressionCatalog.swift                    # identifiers, constants, functions, arity
│   ├── ExpressionCompiler.swift                   # names, recursion, order, code, cost
│   ├── CompiledExpression.swift                   # opcodes, instructions, bytes, evaluation
│   ├── ExpressionMath.swift                       # C math import, finite helpers, function bodies
│   └── ExpressionMapping.swift                    # adapter to MOD-003 output range
└── Tests/ParameterExpressionTests/
    ├── ExpressionEvaluationTests.swift            # valid table, bindings, mapping adapter
    ├── ExpressionRejectionTests.swift             # rejection table with exact messages
    ├── ExpressionLimitTests.swift                 # each limit at and over its bound
    ├── ExpressionNumericSafetyTests.swift         # division, sqrt, pow, overflow, inputs
    ├── ExpressionDeterminismTests.swift           # bytes, bit-identical results
    ├── ExpressionFuzzTests.swift                  # fixed-seed random and mutated sources
    ├── ExpressionSourceSafetyTests.swift          # static scan of the module
    └── ExpressionTestSupport.swift                # frame helpers
```

**Structure Decision**: a separate target in the ParameterGraph package: it needs MOD-002's names
and MOD-003's interpolation, and being its own module lets the compiler prove the absence of
Foundation (hence `NSExpression`). `ParameterGraph`'s existing target and its dependants are not
touched; CI already tests the package on Linux, macOS and simulators, so no workflow change is
needed (`swift test` and `-scheme ParameterGraph-Package` pick up the new targets; checked in
SHD-009-T19).

## Complexity Tracking

None: no constitution violations.
