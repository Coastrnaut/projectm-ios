# Research: SHD-010 Expression Sandbox Budgets

## SHD-010-D1 Scope of "expression graphs"

- **Decision**: the SHD-009 expression language (one formula's binding graph and the set of formulas
  evaluated per frame). SHD-002 generator graphs are recorded as already budgeted.
- **Rationale**: SHD-002 (ADR-0019) limits nodes (64), connections (128), chain (32), live values
  (16) and the rate; `GeneratorGraphLayer.init(document:)` validates and compiles before a layer
  exists, and `render` only draws the compiled plan with one fixed shader (≤ 64 instructions per
  pixel), covered by `GraphValidationTests.testNodeAndConnectionLimits`, `testDepthLimit`,
  `testLiveValueLimit`. That is already "rejected before it can block the render thread".
- **Alternatives**: a per-stack GPU instruction budget across graph layers — rejected for now: GPU
  time scales with pixels, needs a device measurement and has no consumer stacking graph layers yet.

## SHD-010-D2 Time limit as static cost

- **Decision**: no clock or step counter in the interpreter; time limits are static cost limits.
- **Rationale**: no jumps or loops (opcode table), so each instruction runs exactly once; cost
  counts weighted instructions. A clock on the frame path would make results depend on timing.
- **Alternatives**: watchdog thread (cannot stop a running interpreter safely; non-deterministic);
  per-instruction countdown (dead code in a loop-free program).

## SHD-010-D3 Budget numbers

- **Decision**: 32 formulas (= `AudioFeatureModulator.maximumBindings`), 2,048 cost units per frame,
  per-formula limits no looser than `ExpressionLimits.standard`.
- **Rationale**: 2,048 = 8 maximal formulas, a quarter of the unchecked worst case (32 × 256 =
  8,192). Host measurement (information only, quickstart step 4, Apple M5 Max, Release, 2026-11-13):
  a full-budget snapshot takes 0.8-1.7 µs per frame (0.39-0.85 ns per cost unit by instruction
  mix: add 0.75, sin 0.61, pow 0.85, band mean 0.39, mixed full budget 0.62), about 0.01% of a
  16.7 ms frame. D1's figure is the `{device}` task SHD-010-T13.
- **Alternatives**: 8,192 (never refuses); 1,024 (would refuse 32 formulas of modest cost 33+).

## SHD-010-D4 `audio.bandMean` weight

- **Decision**: 4, and the mean is summed at most once per evaluation (and once per frame in the
  snapshot), so a read is a load.
- **Rationale**: the first measurement contradicted the planned rationale ("about a `pow`"): with a
  sum over 128 bands on every read, band-mean formulas took 10.73 ns per cost unit against
  0.6-0.85 for every other instruction, so cost would not have tracked work (about 53 ns per read).
  Weighting a read about 75 would have allowed only three reads per formula. Instead the evaluator
  caches the mean (same value, bit-identical results), which brought band-mean formulas to 0.39 ns
  per unit; weight 4 is kept as a conservative per-read charge. The one remaining sum (about 50 ns on
  the host for 128 bands) is a fixed per-frame overhead of the snapshot, outside the cost budget; a
  formula evaluated alone, outside a snapshot, pays one sum per evaluation.
- **Alternatives**: 1 (understates it, ADR-0021 Consequences); 128 (overstates it: one read would be
  half a formula).

## SHD-010-D5 Compile work counting

- **Decision**: step counters per phase: lexer = bytes visited (plus one for the length check),
  parser = grammar-rule entries plus token advances, compiler = nodes resolved, dependency visits and
  references followed, instructions emitted, plus bindings named. Bounds are per phase and linear;
  a ceiling at the standard limits follows from them.
- **Rationale**: counts are deterministic and platform-independent (no wall clock, owner rule 7).
- **Audit fixes**: `Array(source.utf8)` copied the whole source before the length check (a 1 MB
  string was copied to be refused); the check now uses `utf8.count` (constant time for native
  strings) and copies only an accepted source. The compiler's `audioSources.contains` was a linear
  scan per audio read (≤ 131 distinct features × 128 nodes); it becomes a set lookup.

## SHD-010-D6 Render-thread separation

- **Decision**: `ExpressionFrameSet` (builder, off the frame loop) accepts only `CompiledExpression`
  values; `ExpressionFrameSnapshot` (immutable, `Sendable`) has only `evaluate(_:into:)`.
- **Rationale**: the type system keeps source text and compilation out of the frame path; a
  snapshot can be swapped into the render loop atomically by the wiring row.
- **Alternatives**: a runtime "am I on the render thread" check (needs Foundation/Dispatch, and
  only fails after the fact).
