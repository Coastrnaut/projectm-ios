# Tasks: SHD-009 Expression Mapping DSL

**Input**: Design documents from `specs/045-shd-009-expression-mapping-dsl/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/expression-language.md,
quickstart.md

**Tests**: Requested by the spec (SHD-009-S1-S7) and owner rule 7 budgets: a unit test about 1-2 s
and at most 10 s, the package suite under 1 minute, no wall-clock assertions.

**Format**: `[ID] [P?] [Story] Description`. No device or owner tasks in this row.

## Phase 1: Setup

- [X] SHD-009-T01 Add the `ParameterExpression` target (dependency `ParameterGraph`), the `ParameterExpressionTests` test target (dependencies `ParameterExpression`, `ParameterGraph`) and the `ParameterExpression` library product to `Packages/ParameterGraph/Package.swift`, with one header-comment paragraph; the existing target and product are unchanged — Verified 2026-11-13: `swift build`/`swift test --package-path Packages/ParameterGraph` resolve and build the new target and test target

## Phase 2: Foundational (blocks every story)

- [X] SHD-009-T02 [P] `ExpressionLimits` (`maximumSourceBytes` 512, `maximumTokens` 256, `maximumNodes` 128, `maximumNesting` 16, `maximumBindings` 16, `maximumOperationCost` 256; `standard`; `cost(of:)` 4 for `sin cos sqrt pow smoothstep`, else 1) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLimits.swift` — Verified 2026-11-13: ExpressionLimitTests.testDefaults and the limit tests (defaults and custom limits)
- [X] SHD-009-T03 [P] `SourcePosition` (1-based line, byte column; `"line:column"`) and `ExpressionError` with `Reason` covering every row of contract E7 with its exact message, `description` = `"line:column: reason"` in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionError.swift` — Verified 2026-11-13: ExpressionRejectionTests.testRejectionTable (48 sources, exact `line:column: reason`) and testErrorCarriesPositionAndReason
- [X] SHD-009-T04 [P] `ExpressionCatalog`: identifier resolution (`AudioFeatureSource(id:)` for `audio.*`, `time`, constants `pi tau e`), the function table (name, arity, opcode per contract E4) and the reserved binding names (`let time pi tau e audio` and every function) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift` — Verified 2026-11-13: ExpressionEvaluationTests.testValidTableEvaluatesExactly (every identifier, constant and function)
- [X] SHD-009-T05 [P] `ExpressionMath`: C math import (`Darwin`/`Glibc`/`Musl`), `finite(_:)` (NaN → 0, ±∞ → ±`greatestFiniteMagnitude`), the function bodies of contract E4 and `x / 0 → 0` in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionMath.swift` — Verified 2026-11-13: ExpressionNumericSafetyTests 2/2; ExpressionEvaluationTests function rows

## Phase 3: User Story 1 - Shape audio with a small formula (P1) MVP

**Goal**: a valid formula compiles and evaluates to its arithmetic value; a mapping adapter feeds MOD-003.
**Independent test**: `ExpressionEvaluationTests`.

- [X] SHD-009-T06 [US1] Lexer per contract E1 (length check first, whitespace and lines, names with `.` segments, `let` keyword, numbers with malformed and out-of-range detection, punctuation, unexpected character or byte, token limit) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionLexer.swift` — Verified 2026-11-13: ExpressionEvaluationTests; lexical rows of ExpressionRejectionTests (T12)
- [X] SHD-009-T07 [US1] Recursive-descent parser per contract E2 (bindings, precedence, left associativity, nesting counter checked before descending, node and binding limits at the offending token, `expected …, found …` messages) producing the internal tree in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionParser.swift` — Verified 2026-11-13: ExpressionEvaluationTests (precedence, associativity, unary); syntax rows of T12 and T13
- [X] SHD-009-T08 [US1] Compiler: name phase (binding names, identifiers, functions, call forms, argument counts in source order), recursion phase (depth-first over bindings in source order, path `a → b → a` at the closing reference), dependency-ordered slots, code generation with running cost (error at the node crossing the limit), maximum stack depth, audio sources in first-use order, `readsTime` in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCompiler.swift` — Verified 2026-11-13: ExpressionEvaluationTests (bindings in any order, audio sources, readsTime); recursion rows of T12; cost rows of T13
- [X] SHD-009-T09 [US1] `ExpressionOpcode` (permanent values of data-model.md), `ExpressionInstruction` (bit-pattern equality), `CompiledExpression` (`init(source:limits:) throws(ExpressionError)`, `bytes` as in data-model.md, `evaluate(_:)` over `withUnsafeTemporaryAllocation`, every result made finite), `ExpressionInputs` in `Packages/ParameterGraph/Sources/ParameterExpression/CompiledExpression.swift` — Verified 2026-11-13: ExpressionEvaluationTests (exact bit patterns); ExpressionDeterminismTests (T15, pinned bytes); evaluator reviewed: one withUnsafeTemporaryAllocation buffer of slotCount + maximumStackDepth doubles, no other allocation
- [X] SHD-009-T10 [P] [US1] `ExpressionMapping` (`isValid`, `position`, `map` per contract E8) in `Packages/ParameterGraph/Sources/ParameterExpression/ExpressionMapping.swift` — Verified 2026-11-13: ExpressionEvaluationTests.testMappingAdapterUsesTheLinearOutputRange
- [X] SHD-009-T11 [US1] Evaluation tests: a table of valid formulas with fixed bands, onset, beat confidence and time and their exact results (precedence, associativity, unary minus, every identifier and constant, every function, bindings in any order equal to the inline form, unused binding); audio sources and `readsTime`; the mapping adapter (clamping to 0…1, inverted output range, exact ends) and test helpers in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionEvaluationTests.swift` and `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionTestSupport.swift` — Verified 2026-11-13: `swift test --package-path Packages/ParameterGraph --filter ParameterExpressionTests`: ExpressionEvaluationTests 5/5 (0.002 s)

## Phase 4: User Story 2 - Unknown names, recursion and complexity are rejected (P1)

**Goal**: every rejection gives its exact message and position.
**Independent test**: `ExpressionRejectionTests`, `ExpressionLimitTests`.

- [X] SHD-009-T12 [P] [US2] Rejection table: source → exact `description` for unknown identifier (`audio.bass`, `audio.band.128`, `audio.band.07`, `Time`), unknown function, not a function, function without call, wrong argument counts (singular and plural), self and mutual recursion (`x → x`, `a → b → a`, a three-binding loop reported from the first binding), invalid, reserved and duplicate binding names, malformed numbers (`1.`, `1e`, `1.2.3`, `0x1F`), out-of-range number, unexpected character and byte, empty source, unbalanced parentheses, trailing input, multi-line positions, and phase order (a lexical error after a syntax error wins) in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionRejectionTests.swift` — Verified 2026-11-13: ExpressionRejectionTests 2/2 (48-row table incl. self, two- and three-binding loops and the rotated loop)
- [X] SHD-009-T13 [P] [US2] Limit tests: each limit accepted at its bound and rejected one over with its message and position (512/513 bytes, 256/257 tokens, 128/129 nodes, 16/17 nesting by parentheses, calls and unary operators, 16/17 bindings, cost 256/257 including cost-4 functions); a flat 60-term sum stays at nesting 0; custom tighter limits apply in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionLimitTests.swift` — Verified 2026-11-13: ExpressionLimitTests 7/7 (every limit at and one over its bound; token 257 is at column 259)

## Phase 5: User Story 3 - Evaluation is safe and deterministic (P1)

**Goal**: finite, documented results; identical bytes and bits.
**Independent test**: `ExpressionNumericSafetyTests`, `ExpressionDeterminismTests`, `ExpressionFuzzTests`.

- [X] SHD-009-T14 [P] [US3] Numeric safety: `1/0`, `0/0`, `-1/0` → 0; `sqrt(-4)` → 0; `pow(-8, 0.5)` → 0; `pow(10, 400)` and `1e308 * 10` → largest finite; `-1e308 * 10` → most negative; `smoothstep(1, 1, x)`; `clamp` with crossed bounds; NaN/∞ band, onset, beat confidence and time inputs read 0; missing bands read 0 in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionNumericSafetyTests.swift` — Verified 2026-11-13: ExpressionNumericSafetyTests 2/2 (23 documented results bit-exact, 4 finite-only cases, non-finite and missing inputs)
- [X] SHD-009-T15 [P] [US3] Determinism: every valid-table formula compiled twice gives equal instructions and bytes; a pinned byte form for one small formula (header, opcodes, literal bits); 1,000 evaluations with the same inputs bit-identical in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionDeterminismTests.swift` — Verified 2026-11-13: ExpressionDeterminismTests 3/3 (44 fixtures compiled twice, pinned bytes of `1 + time`, dependency order of slots, 1,000 bit-identical evaluations each)
- [X] SHD-009-T16 [P] [US3] Fuzz (fixed-seed SplitMix64): 1,000 random byte strings (0-600 bytes, biased to the language's characters) and 1,000 mutations of valid formulas (insert, delete, replace, duplicate spans); each either throws an `ExpressionError` with a position inside the source (or one past its end) or compiles with cost ≤ 256 and evaluates finite on extreme inputs (bands ±1e300, NaN, time 1e12); under 1 s in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionFuzzTests.swift` — Verified 2026-11-13: ExpressionFuzzTests 1/1 (seed 0x5D09, 2,000 sources: 94 compiled and finite on 4 extreme inputs, 1,906 rejected with in-source positions; 0.12 s)

## Phase 6: User Story 4 - A formula can never become code (P1)

**Goal**: data only, enforced by a scan.
**Independent test**: `ExpressionSourceSafetyTests`.

- [X] SHD-009-T17 [P] [US4] Source scan of `Packages/ParameterGraph/Sources/ParameterExpression/*.swift`: the only imports are `ParameterGraph` and the C math library (`Darwin`, `Glibc`, `Musl`, each in `ExpressionMath.swift`); no `NSExpression`, `NSPredicate`, `JavaScriptCore`, `JSContext`, `dlopen`, `dlsym`, `Process`, `makeLibrary`, `MTLCompileOptions`, `import Metal`, `URL(`, `FileManager`, `Bundle`, `NSClassFromString`; at least 9 files scanned in `Packages/ParameterGraph/Tests/ParameterExpressionTests/ExpressionSourceSafetyTests.swift` — Verified 2026-11-13: ExpressionSourceSafetyTests 1/1 (9 files; imports only ParameterGraph and Darwin/Glibc/Musl in ExpressionMath.swift; 23 forbidden words absent)

## Phase 7: Polish

- [X] SHD-009-T18 ADR at the next free number (checked across branches and worktrees at commit): the language's safety design (data only, closed sets, declarative bindings without recursion, static limits and cost, finite arithmetic), the adapter-only integration and what SHD-010 and SHD-011 build on; row in `docs/adr/README.md` — Verified 2026-11-13: docs/adr/0021-expression-mapping-language.md and its README row; 0020 is taken by MED-001 (commit 456b24f), 0021 free across all branches and worktrees; validate_docs OK
- [ ] SHD-009-T19 Verification: `swift test --package-path Packages/ParameterGraph` (suite < 1 min, record counts and durations); the VisualGenerators host suite and its Linux shape (`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE --scratch-path .build/linuxshape`); confirm `.github/workflows/ios-ci.yml` runs ParameterGraph's tests (new targets need no workflow change); `check_compliance.py` and `validate_docs.py` pass; spec status updated

## Dependencies

T01 → T02-T05 (parallel) → T06 → T07 → T08 → T09 → T10 → T11 → T12-T17 (parallel; each a separate
test file) → T18 → T19.

## Parallel examples

- After T01: T02, T03, T04, T05 (four files).
- After T11: T12, T13, T14, T15, T16, T17 (six test files).

## Implementation Strategy

MVP = Phase 3 (a formula compiles, evaluates and maps). The rejection, limit, safety, determinism,
fuzz and scan tests then prove the acceptance. One writer; commits after each complete change.
