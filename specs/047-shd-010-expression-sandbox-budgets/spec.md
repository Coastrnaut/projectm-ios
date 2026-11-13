# Feature Specification: SHD-010 Expression Sandbox Budgets

**Feature Branch**: `feature/shd-010` (spec directory `047-shd-010-expression-sandbox-budgets`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHD-010 (Expression sandbox budgets) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Enforce operation and evaluation
time limits for expression graphs." Acceptance, verbatim: "Pathological fixture is rejected before it
can block render thread." Depends on SHD-009 (integrated). Priority P0, size M."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-010-R1…`, success criteria `SHD-010-S1…`, tasks `SHD-010-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `b2d557d`)

The row's gap status is "Gap candidate". The audit maps the row onto what SHD-009 and SHD-002
already deliver; the gaps are what this row adds.

| Area | Today | Gap for this row |
|---|---|---|
| Per-formula operation limit | SHD-009: one value `ExpressionLimits.standard` (512 bytes, 256 tokens, 128 nodes, nesting 16, 16 bindings, static operation cost 256 with `sin cos sqrt pow smoothstep` weighted 4); a formula over a limit is refused at compile time with `line:column: reason`. | None for the limit itself. `audio.bandMean` costs 1 although it reads up to 128 bands (ADR-0021 Consequences flags it). Any caller can compile under arbitrarily loose limits (`ExpressionLimits(maximumOperationCost: 100_000)`) and nothing refuses that formula later. |
| Evaluation time of one formula | No loops, jumps, user functions or recursion; each instruction runs exactly once, so work = static cost (ADR-0021 Decision 5). | Stated, not tested as a bound; no worst-case figure. |
| Several formulas in one frame | Nothing: no type collects the formulas evaluated per frame (wiring mappings into `AudioFeatureModulator`, which allows 32 bindings, is a later row). | No per-frame budget: 32 maximal formulas would cost 8,192 units per frame unchecked. |
| Compile (parse) time on adversarial input | Hand-written lexer and recursive-descent parser; the parser checks nesting before each descent; the source is length-checked first. | Linear time is a code-review claim; no counter measures it and no adversarial fixture checks it. |
| Render thread | No app code uses `ParameterExpression` yet. `CompiledExpression.init(source:)` compiles; `evaluate` only interprets. | Nothing in the API separates "compile" (off the frame loop) from "evaluate" (on it). |
| SHD-002 generator graphs | `GeneratorGraphValidator`: ≤ 64 nodes, ≤ 128 connections, chain ≤ 32, ≤ 16 live values, and a compiled rate bound; validated and compiled when the layer is created; the render path draws only the compiled plan with one fixed interpreter (≤ 64 instructions per pixel; ADR-0019, tests `GraphValidationTests`). | None. Its budgets already are operation limits checked before rendering; recorded, not changed (Clarifications). |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which "expression graphs" does this row cover? → A: The SHD-009 expression language: one
  formula (its `let` bindings form a small dependency graph) and the set of formulas evaluated in
  one frame. SHD-002 generator graphs are not changed: they already have node, connection, chain and
  live-value limits plus a rate bound, are validated and compiled before a layer exists, and are drawn
  by one fixed GPU interpreter of at most 64 instructions per pixel (ADR-0019). Their per-frame cost
  is GPU work proportional to pixels, which a CPU operation count does not measure. Rejected: a new
  generator-graph budget in this row (it would duplicate ADR-0019's limits without new evidence).
- Q: What is a "time limit" when the interpreter has no clock? → A: A static one. The language has
  no loops, jumps, recursion or user functions, so each compiled instruction runs exactly once and a
  formula's evaluation work equals its static operation cost. Time limits are therefore enforced as
  operation-cost limits checked before evaluation: per formula (cost ≤ 256) and per frame (total ≤
  2,048). A wall-clock watchdog or a step counter inside the interpreter is rejected: the frame path
  must not branch on time (non-deterministic) and a counter cannot fire in a loop-free program. The
  worst-case evaluation time on the host is measured and recorded as information only; it is not a
  pass criterion (no wall-clock assertions).
- Q: What are the per-frame budget's numbers? → A: At most 32 formulas per frame (MOD-002's
  `AudioFeatureModulator.maximumBindings`) and a total static cost of at most 2,048 units, which is
  eight formulas at the per-formula maximum or 32 formulas averaging 64. Each admitted formula must
  have been compiled under limits no looser than `ExpressionLimits.standard` (every field ≤ the
  standard value). The budget is checked when a formula is added to a frame set, never while
  rendering; a formula that would exceed it is refused with a readable message stating the budget,
  the formula's cost and the cost already used. Removing a formula frees its cost. Rejected: a
  budget equal to 32 × 256 (it would never refuse anything) and per-frame dynamic skipping (a
  parameter would silently stop moving).
- Q: Does `audio.bandMean` get a higher weight? → A: Yes, 4, like the other instructions that do
  more than one arithmetic step: it sums up to 128 bands (MOD-002). This changes SHD-009's cost
  table (ADR-0021 Decision 5 amended); formulas using `audio.bandMean` near the 256 limit may now be
  refused. Rejected: a weight of 128 (it would make a single read cost half a formula; the host
  measurement shows a band mean takes about the time of a `pow`).
- Q: How is "before it can block the render thread" guaranteed? → A: By the API shape and by
  measured compile-work bounds. (1) The only way to put a formula into the per-frame set is a
  compiled formula: the frame set never accepts source text, so parsing and compiling cannot run in
  the frame path. The frame set is split into a mutable builder (admission, removal, off the frame
  loop) and an immutable, sendable snapshot whose only operation is evaluation. (2) Compilation of
  any source does a number of steps bounded by a linear function of its size, measured by step
  counters in the lexer, parser and compiler (not by a clock); pathological fixtures (deep nesting,
  token floods, long binding chains, maximal cost, oversized source, binding fan-out) are each
  refused with their exact message or compiled within the documented step bound.
- Q: What do the frame set's refusal messages say? → A: They have no `line:column` (the formula
  itself is valid) and state the numbers, checked in this order: loosened limits first ("the
  formula was compiled with an operation cost limit of 100000; the standard limit is 256", naming the
  first loosened field in the order source bytes, tokens, nodes, nesting, bindings, operation cost),
  then the count ("the frame already evaluates 32 formulas; at most 32 are allowed"), then the cost
  ("a formula of cost 256 would bring the frame to 2100; at most 2048 is allowed (1844 used)").
  Rejected: reusing `ExpressionError` (it requires a source position).
- Q: How does the frame loop get the results? → A: The snapshot evaluates every admitted formula in
  admission order into a caller-provided buffer of at least as many values, so the frame path makes
  no allocation; a buffer that is too small evaluates only as many formulas as fit (never a trap).
  Rejected: returning an array (allocates every frame).
- Q: How are admitted formulas identified? → A: By a handle issued on admission, increasing and
  never reused within one frame set, so a stale handle can never remove a later formula. The handle
  also gives the formula's position in the snapshot's results.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A pathological formula never reaches the frame loop (Priority: P1)

A formula from a preset, the modulation editor or an imported file may be hostile or simply badly
written: deeply nested, as long as allowed, maximally expensive, recursive or built to make the
parser work hard. The app refuses it while checking it, with one readable message, before it is ever
added to the formulas evaluated per frame; checking it takes a bounded amount of work.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: A table of pathological fixtures: each is refused with its exact message (or,
for the fixtures the language allows, compiled), and each is checked within the documented step bound;
none is ever evaluated.

**Acceptance Scenarios**:

1. **Given** a pathological fixture (nesting at the byte limit, a token flood, 17 bindings, a
   formula of cost 257, an oversized source, a recursive binding loop), **When** it is checked,
   **Then** it is refused with its exact `line:column: reason` message and nothing is evaluated.
2. **Given** any source up to the byte limit, **When** it is checked, **Then** the work done
   (counted lexer, parser and compiler steps) stays within the documented linear bound.
3. **Given** a formula compiled under limits looser than the standard ones, **When** it is offered
   to the per-frame set, **Then** it is refused with a message naming the loosened limit.

---

### User Story 2 - The formulas of one frame fit a budget (Priority: P1)

All the formulas evaluated in one frame together stay within a fixed operation budget and count, so
adding modulation can never make a frame miss its deadline because of formula evaluation. Adding a
formula that would exceed the budget is refused with a message saying how much is used and allowed;
removing one frees its share.

**Why this priority**: It is the row's observable behavior ("enforce operation and evaluation time
limits for expression graphs").

**Independent Test**: Add formulas until the budget is reached; the next is refused with its exact
message; removing one lets it in.

**Acceptance Scenarios**:

1. **Given** a frame set whose used cost plus a new formula's cost exceeds 2,048, **When** the
   formula is added, **Then** it is refused with the budget, the formula's cost and the used cost,
   and the set is unchanged.
2. **Given** a frame set with 32 formulas, **When** a 33rd is added, **Then** it is refused.
3. **Given** a full frame set, **When** a formula is removed, **Then** its cost is freed and a
   formula of that cost is admitted.
4. **Given** a frame set, **When** its snapshot is evaluated, **Then** each formula's result equals
   evaluating it alone, in admission order, and the work equals the set's used cost.

---

### User Story 3 - The bound is documented and reproducible (Priority: P2)

Reviewers can read the worst case: the per-frame budget, the per-formula maximum, the cost table,
the compile-work bound and a host measurement of time per cost unit (information only).

**Why this priority**: Constitution X (evidence) and SHD-011 (imported content) rely on it.

**Independent Test**: Determinism: the same sources give the same counts, costs and messages on
every run; the informational measurement runs only on request.

**Acceptance Scenarios**:

1. **Given** the same sources, **When** they are checked twice, **Then** step counts, costs and
   messages are identical.

### Edge Cases

- A formula with cost exactly 2,048 − used: admitted (the budget is inclusive).
- Admitting the same compiled formula twice: allowed; each admission is a separate entry with its
  own handle and its own cost.
- Removing an unknown or already removed handle: reports that nothing was removed; the set is
  unchanged.
- An empty frame set: its snapshot evaluates nothing and costs 0.
- A result buffer smaller than the formula count: only the formulas that fit are evaluated.
- Several limits loosened at once: the message names the first in the documented order.
- A long `let` chain where each binding doubles the previous one (`let a1 = a0 + a0; …`): accepted
  with linear cost, because each binding is evaluated once (no exponential blow-up).
- A formula compiled under tighter limits than the standard: admitted (tighter is always allowed).

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-010-R1**: Each instruction's static cost MUST follow one table: 4 for `sin`, `cos`, `sqrt`,
  `pow`, `smoothstep` and `audio.bandMean`; 1 for every other instruction. A formula's static cost
  MUST equal the work its evaluation does (each instruction runs exactly once).
- **SHD-010-R2**: A per-frame budget MUST limit the formulas evaluated in one frame to at most 32
  formulas and a total static cost of at most 2,048 (defaults, one value).
- **SHD-010-R3**: Adding a formula to the per-frame set MUST be refused, with a readable message and
  the set unchanged, when it would exceed the formula count or the total cost, or when the formula
  was compiled under limits looser than the standard per-formula limits. Removing a formula MUST
  free its cost and count. Refusals are checked in the order loosened limits, count, cost, with the
  messages given in the Clarifications. Admission returns a handle that is never reused.
- **SHD-010-R4**: The per-frame set MUST accept only compiled formulas, never source text, and the
  part handed to the frame loop MUST be an immutable value whose only operation is evaluation; so
  parsing and compiling cannot run in the frame path.
- **SHD-010-R5**: Checking a source MUST do a number of steps bounded by a documented linear
  function of its size (lexer steps per byte, parser steps per token, compiler steps per node and
  binding), counted by step counters; at the standard limits the total MUST NOT exceed a documented
  ceiling.
- **SHD-010-R6**: A table of pathological fixtures MUST be refused with exact messages before any
  evaluation (or, for fixtures the language allows, compiled within the step bound and the cost
  limit).
- **SHD-010-R7**: Budgets, costs, step counts and messages MUST be deterministic.
- **SHD-010-R8**: Evaluating the per-frame snapshot MUST write each result, in admission order, into
  a caller-provided buffer, MUST NOT allocate heap memory and MUST NOT read a clock (work bounded by
  the used cost alone).
- **SHD-010-R9**: The module MUST stay pure: no new imports, Linux-buildable, tests within the
  owner's budget (unit test about 1-2 s, at most 10 s; suite under 1 minute; no wall-clock
  assertions).
- **SHD-010-R10**: The worst-case evaluation time per frame on the host MUST be measured and
  recorded as information (not a pass criterion); the device figure on D1 is a separate `{device}`
  task.

### Key Entities

- **Cost table**: the static cost per instruction.
- **Frame budget**: the maximum formula count and total static cost per frame, and the per-formula
  limits a formula must have been compiled under.
- **Frame set (builder)**: the admitted formulas with their handles and the used cost; admission and
  removal happen here, off the frame loop.
- **Frame snapshot**: an immutable copy of the admitted formulas that the frame loop evaluates.
- **Budget error**: why a formula was refused by the frame set.
- **Compile work**: the lexer, parser and compiler step counts of one check.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-010-S1**: 100% of the pathological fixture table gives its documented outcome (exact
  refusal message, or acceptance with its documented cost), with 0 evaluations of a refused fixture.
- **SHD-010-S2**: Budget accounting: the formula that would cross the cost budget or the count
  budget is refused with its exact message in 100% of the accounting tests; removal frees exactly
  the removed cost.
- **SHD-010-S3**: For every fixture and a fixed-seed set of at least 500 random sources, the counted
  compile work is within the documented linear bound and the ceiling (0 exceptions).
- **SHD-010-S4**: Doubling an adversarial input's size at most doubles its compile work plus a
  constant (linear growth) for each adversarial shape.
- **SHD-010-S5**: The module's tests pass on the macOS host and in the Linux build shape, each test
  within the owner's budget.

## Assumptions

- Formulas are not yet wired into the modulator or the render loop (a later row); this row delivers
  the budget types the wiring must use, and the wiring row adds them to the app.
- The host's time per cost unit is informational; device figures need D1 and are left open.
- SHD-002 generator graph budgets stay as ADR-0019 defines them.
