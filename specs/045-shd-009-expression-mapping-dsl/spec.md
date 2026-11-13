# Feature Specification: SHD-009 Expression Mapping DSL

**Feature Branch**: `feature/shd-009` (spec directory `045-shd-009-expression-mapping-dsl`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHD-009 (Expression mapping DSL) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Evaluate a restricted numeric
expression over known audio parameters." Acceptance, verbatim: "Parser rejects unknown identifiers,
recursion and excessive complexity." Depends on MOD-001 (integrated). SHD-010 (expression sandbox
budgets, effective P0) and SHD-011 (user-authored shader policy) build on it. The expression is
data, never code (ADR-0018, ADR-0019)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-009-R1…`, success criteria `SHD-009-S1…`, tasks `SHD-009-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `ef9318d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Audio-to-parameter mapping | MOD-002 binds one normalized audio feature (`audio.band.<i>`, `audio.bandMean`, `audio.onset`, `audio.beatConfidence`) to one parameter; MOD-003 maps it linearly into the output range. | A mapping can only be one feature scaled linearly; nothing combines features or shapes them with a formula. |
| Expressions | None. ProjectM presets carry their own equation language, but it runs inside the engine, not in the app's parameter system. | No restricted, checked expression language in the app. |
| Safety | ADR-0018 and ADR-0019: content is data; no shader source from content; closed sets of operations. | Nothing states how a typed formula is checked, bounded and evaluated without becoming code. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

(Recorded by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shape audio with a small formula (Priority: P1)

A later feature (a preset, the modulation editor, an imported scene) describes how audio drives a
parameter with one short formula over the known audio features and the time, for example
`clamp(audio.onset * 2 - 0.5, 0, 1)` or `mix(audio.band.0, audio.band.3, 0.5 + 0.5 * sin(time))`.
The app checks the formula once and then evaluates it every frame to a finite number that reaches
the parameter only through the existing range clamping.

**Why this priority**: It is the row's observable behavior ("evaluate a restricted numeric
expression over known audio parameters").

**Independent Test**: A table of valid formulas with fixed inputs: each evaluates to its exact
expected value.

**Acceptance Scenarios**:

1. **Given** a valid formula and a frame of audio features, **When** it is evaluated, **Then** the
   result equals the arithmetic value of the formula for those features.
2. **Given** a formula with named intermediate values (`let` bindings), **When** it is evaluated,
   **Then** each binding is computed once and the result equals the same formula written inline.
3. **Given** a compiled formula used as a mapping, **When** it is evaluated, **Then** its result is
   limited to the 0…1 position and mapped into the output range exactly as a linear mapping does.

---

### User Story 2 - Unknown names, recursion and complexity are rejected (Priority: P1)

A formula that names something that does not exist, refers to itself (directly or through other
bindings) or is too large or too deeply nested is refused before it is ever evaluated, with one
readable message that names the position (line and column) and the reason.

**Why this priority**: It is the row's acceptance criterion, and the safety basis for SHD-010
(budgets) and SHD-011 (imported content).

**Independent Test**: A table of rejected formulas, each with its exact message and position.

**Acceptance Scenarios**:

1. **Given** a formula naming an unknown identifier (`audio.bass`) or function (`tan`), **When** it
   is compiled, **Then** it is rejected with "unknown identifier" or "unknown function" at the name's
   position.
2. **Given** a binding that refers to itself, or bindings that refer to each other in a loop,
   **When** the formula is compiled, **Then** it is rejected as recursive and the message lists the
   loop's names in order (`a → b → a`).
3. **Given** a formula over a limit (length, tokens, nodes, nesting depth, bindings, operations),
   **When** it is compiled, **Then** it is rejected with a message stating the limit.
4. **Given** malformed input (bad numbers, stray characters, wrong number of arguments, trailing
   input), **When** it is compiled, **Then** it is rejected with a message naming the problem.

---

### User Story 3 - Evaluation is safe and deterministic (Priority: P1)

Whatever the inputs, evaluating a compiled formula never crashes, never yields a non-finite number
and always gives the same result for the same inputs, so presets and previews are reproducible and
a formula can run on the render path.

**Why this priority**: A formula runs every frame; a trap or a NaN would break the visualizer, and
non-determinism would break SHD-012's reproducible previews.

**Independent Test**: Numeric edge cases (division by zero, square root of a negative, power
overflow, extreme inputs) give their documented results; compiling twice gives identical compiled
forms; a fixed-seed fuzz of random and mutated sources never crashes.

**Acceptance Scenarios**:

1. **Given** a formula dividing by zero, taking the square root of a negative number or overflowing
   a power, **When** it is evaluated, **Then** the result is the documented finite value.
2. **Given** the same source compiled twice, **When** the compiled forms are compared, **Then** they
   are byte-identical; **and given** the same inputs twice, the results are bit-identical.
3. **Given** a fixed-seed set of random byte strings and mutated valid formulas, **When** each is
   compiled and (if accepted) evaluated with extreme inputs, **Then** none crashes and every result
   is finite.

---

### User Story 4 - A formula can never become code (Priority: P1)

The owner and reviewers can see that a formula is data only: it is read by a hand-written parser
into a small closed instruction set and evaluated by a fixed interpreter; nothing in it reaches a
system expression evaluator, a script engine, dynamic loading or shader compilation.

**Why this priority**: Constitution I and ADR-0018; SHD-011 will accept formulas from imported files.

**Independent Test**: A source scan of the module finds none of the forbidden facilities.

**Acceptance Scenarios**:

1. **Given** the expression module's source, **When** it is scanned, **Then** it imports no system
   framework beyond the C math library and uses no expression evaluator, script engine, dynamic
   loader or shader compiler.

### Edge Cases

- Empty or whitespace-only source: rejected ("expected an expression").
- Non-ASCII bytes, control characters, tabs and line breaks: tabs and line breaks are whitespace
  (positions count lines); any other control or non-ASCII byte is rejected at its position.
- `audio.band.128`, `audio.band.07`, `audio.band.-1`: unknown identifiers (MOD-002 names only).
- A function name used without a call (`sin + 1`) or a value called as a function (`time(1)`):
  rejected with a message saying which.
- A binding that shadows a known name (`let time = 1`) or is defined twice: rejected.
- An unused binding: allowed; it is still compiled and counted.
- A huge literal (`1e400`): rejected as out of range; `1e308 * 10` evaluates to the largest finite
  number.
- No audio (silent frame) or a non-finite time: every audio feature reads 0; a non-finite time reads 0.
- `smoothstep` with equal edges, `clamp` with a lower bound above the upper bound: documented results.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-009-R1**: A formula MUST be a short text: optional `let name = expression;` bindings followed
  by one expression. Expressions use decimal numbers, the known identifiers, the operators `+ - * /`
  (and unary `+ -`), parentheses and calls of whitelisted functions; nothing else.
- **SHD-009-R2**: Identifiers MUST come from a closed set: the MOD-002 audio features
  (`audio.band.<0…127>`, `audio.bandMean`, `audio.onset`, `audio.beatConfidence`), `time` (seconds)
  and the constants `pi`, `tau` and `e`, plus the formula's own bindings. Any other name MUST be
  rejected as unknown.
- **SHD-009-R3**: Functions MUST come from a closed whitelist with fixed argument counts:
  `min max clamp abs sin cos floor fract mix smoothstep step sqrt pow`. Any other function MUST be
  rejected; a wrong argument count MUST be rejected with the expected and found counts.
- **SHD-009-R4**: Bindings MUST NOT be recursive: a binding that refers to itself or a loop of
  bindings MUST be rejected with the loop as a readable path. Duplicate binding names and names that
  shadow identifiers, constants, functions or the keyword MUST be rejected. There are no loops,
  user-defined functions or assignments.
- **SHD-009-R5**: Complexity MUST be limited (defaults): source ≤ 512 bytes, ≤ 256 tokens, ≤ 128
  expression nodes, nesting ≤ 16 levels, ≤ 16 bindings and a static operation cost ≤ 256. A formula
  over any limit MUST be rejected with a message stating the limit, never truncated.
- **SHD-009-R6**: Every rejection MUST carry the line and column (1-based) where the problem was
  found and a readable reason; the message form is `line:column: reason`. Only the first problem
  is reported, in a documented phase order.
- **SHD-009-R7**: Evaluation MUST never trap and MUST always produce a finite result, with
  documented results for division by zero, square roots of negatives, invalid powers, overflow and
  non-finite inputs.
- **SHD-009-R8**: Compilation and evaluation MUST be deterministic: the same source gives a
  byte-identical compiled form, and the same compiled form with the same inputs gives a
  bit-identical result.
- **SHD-009-R9**: After compilation, evaluation MUST NOT allocate memory and MUST do work bounded
  by the static operation cost (no loops in the language).
- **SHD-009-R10**: A compiled formula MUST be usable as an audio mapping: its result, limited to the
  0…1 position, feeds a MOD-003 linear output range, so values reach parameters only through the
  existing MOD-001/MOD-002 clamping. The formula MUST report which audio features it reads.
- **SHD-009-R11**: The formula is data, never code: a hand-written parser and a fixed interpreter;
  no system expression evaluator, script engine, dynamic loading, process launching or shader
  compilation. A test MUST scan the module for this.
- **SHD-009-R12**: The language, parser and interpreter MUST build and be tested on Linux.
- **SHD-009-R13**: The design MUST leave room for SHD-010 (per-graph operation and time budgets)
  and SHD-011 (import policy): limits are a value type with documented defaults, and every compiled
  formula exposes its static operation cost.

### Key Entities

- **Expression source**: the formula text as written.
- **Expression error**: position (line, column) and reason of the first problem.
- **Expression limits**: the complexity limits applied while compiling.
- **Compiled expression**: the closed instruction list, its static operation cost, stack and slot
  sizes, the audio features it reads and its byte form.
- **Expression inputs**: one frame of audio features and the time in seconds.
- **Expression mapping**: a compiled expression with an output range, usable where a linear mapping
  is.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-009-S1**: 100% of the valid-formula table evaluates to its exact expected value.
- **SHD-009-S2**: 100% of the rejected-formula table is rejected with exactly its documented message
  and position, covering unknown identifiers, unknown functions, wrong argument counts, recursion
  (self and loop), every limit, malformed numbers, stray characters and trailing input.
- **SHD-009-S3**: 100% of the numeric-safety cases give their documented finite results.
- **SHD-009-S4**: A fixed-seed fuzz of at least 2,000 sources completes with 0 crashes; every
  accepted source evaluates to finite results on extreme inputs.
- **SHD-009-S5**: Compiling every table formula twice gives byte-identical compiled forms (100%).
- **SHD-009-S6**: The source scan finds 0 uses of forbidden facilities in the module.
- **SHD-009-S7**: The module's tests pass on the macOS host and in the Linux build shape, each test
  within the owner's budget (about 1-2 s, at most 10 s).

## Assumptions

- This row delivers the language, its checks and its evaluator, plus an adapter that turns a
  compiled formula into a mapping. Wiring formulas into the modulator's bindings and saving them in
  presets belongs to later rows (SHD-010 adds budgets per expression graph; SHD-011 the import
  policy).
- Positions count bytes; only ASCII is accepted, so a byte is a character.
- Results are deterministic on one platform; bit-identical results across different CPU
  architectures are not required (the platform math library computes `sin`, `cos`, `pow`).
