# Feature Specification: MOD-003 Linear Mapping

**Feature Branch**: `feature/mod-003` (spec directory `034-mod-003-linear-mapping`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MOD-003 (Linear mapping) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Scale source values into a
bounded destination range." Acceptance, verbatim: "Zero and one map to configured endpoints
exactly." Priority P0, effort S, depends on MOD-002 (integrated). Verification: unit graph tests +
simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-003-R1…`, success criteria `MOD-003-S1…`, research decisions
`MOD-003-D1…`, tasks `MOD-003-T01…`. Requirements of other features are cited by their own IDs:
MOD-002-R4, R5 (binding ranges and the mapped value), MOD-002-R9, R10 (determinism, no allocation),
MOD-004 (curves, the next row that composes with this one).

## Baseline: what exists today (audit of 2026-11-13, commit `006678f`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit finds the behavior
**partly present** and the reusable piece **missing**:

| Area | Today (MOD-002) | Gap for this row |
|---|---|---|
| Input scaling | `AudioFeatureModulator.advance` computes the feature's position in the binding's input range inline, clamped to 0…1, non-finite → 0. | Not reusable: any later source (LFO MOD-007, macro MOD-010, MIDI) would copy it. |
| Output mapping | `effective(_:manual:)` computes `(1 − s)·start + s·end` inline. Exact at s = 0 and s = 1 (tested by `testEndpointsAreExactAndInputIsClamped`, one inverted fixture). | Not reusable, and **not bounded**: for equal endpoints (a constant mapping, e.g. 0.1…0.1) interior signals give values one rounding step above or below the endpoint (an audit sweep found 4,725 of 100,001 positions outside the range), and for arbitrary same-sign endpoints the formula is **not monotonic** at the last digit (an audit walk over random ranges found 20,763 reversals in 1,000,000 adjacent positions). |
| Acceptance coverage | Exactness is tested for one range (0.9…0.1 inverted, plus 0…1, −0.2…0.2, 0.5…1, 0…10). | No test of negative, tiny, huge or constant ranges, of monotonicity, or of boundedness. |

So the row is not fully covered: it needs a named, documented, pure linear mapping that is exact at
both ends, bounded and monotonic for every finite range, used by the modulator, with acceptance
tests over representative ranges, and a regression proof that existing bindings behave the same.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: Is MOD-003 already covered by MOD-002, so that only tests are needed? → A: No. MOD-002 is exact at both ends but its mapping is inline, unbounded for constant ranges and not monotonic at the last digit (see Baseline). MOD-003 extracts it into a first-class, reusable linear mapping that guarantees exactness, boundedness and monotonicity, and the modulator uses it. Rejected: tests only (the gaps above would remain and MOD-004 would have nothing to compose with) (MOD-003-R1, R3, R4).
- Q: Which interpolation formula? → A: The two-branch "precise" interpolation known from C++20 `std::lerp` (paper P0811): when the endpoints have opposite signs (or one is zero), `s·end + (1 − s)·start` (bit-identical to MOD-002's formula); otherwise `start + s·(end − start)`, returning `end` exactly at s = 1 and never passing `end`. It is exact at both ends, bounded and monotonic for every finite pair of endpoints. Rejected: MOD-002's formula plus a clamp (bounded but still not monotonic), MOD-002's formula unchanged (neither) (MOD-003-R3, R4; research MOD-003-D1).
- Q: Must results stay bit-identical to MOD-002? → A: Endpoints and every binding whose output ends have opposite signs or include zero (all ranges in MOD-002's fixtures and every full-range binding of the app's catalog, whose minimums are 0 or negative) are bit-identical. For same-sign endpoints, interior values may differ from MOD-002 in the last digit only (at most 2 units in the last place in the regression sweep); this is the fix for monotonicity and is not visible. No app behavior changes (MOD-003-R7, S4).
- Q: What happens to input outside the input range, and is clamping optional? → A: Always clamped: below the minimum maps to the start, above the maximum to the end, and a non-finite input or position maps to the start (as in MOD-002). The roadmap asks for a bounded destination; an unclamped "extrapolate" option is not offered (a later row can add a policy without breaking this one) (MOD-003-R2, R5).
- Q: How is inversion expressed? → A: By the order of the output ends: an end below the start inverts the mapping (louder → lower), as in MOD-002. The input range must be increasing (minimum below maximum); a separate "invert" flag is not added, since it would duplicate the swapped ends (MOD-003-R1).
- Q: Which number types? → A: Double, the modulator's type. Float sources (band levels) are widened to Double without rounding, so Float-exact inputs stay exact. A generic Float version is not added until a Float consumer exists (MOD-003-R6).
- Q: Is any app or UI change in scope? → A: No. The row is a model change in the parameter package; the app's existing tests run unchanged, so no simulator run is needed unless app code changes (it does not). The roadmap's "simulator" verification is satisfied by MOD-002's binding UI test path, which exercises this mapping through the modulator; this row runs the app's package tests on the host and Linux instead (MOD-003-R7, S5).
- Q (clarify session): What does an invalid mapping (input range empty or reversed, a non-finite bound or end) return when it is used anyway? → A: It never traps and stays deterministic: it reports itself invalid, positions are still clamped to 0…1 with a non-finite position read as 0, and interpolation of non-finite ends returns whatever the formula gives without crashing. Bindings keep refusing invalid ranges before use (MOD-002 contract C2), so the app never evaluates one. Rejected: a failable initializer (it would break the binding's existing stored-field API and its value semantics for later editors that hold a mapping while it is being edited) (MOD-003-R1, R8).
- Q (clarify session): Should the mapping be persistable (encodable) in this row? → A: No. Persistence of graph connections is MOD-013, which will choose its own format and migration rules; adding an encoding now would freeze a format early. The mapping is `Sendable` and `Hashable` only (MOD-003-R6).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero and one land exactly on the configured ends (Priority: P1)

Whoever configures a mapping (a binding today; a macro, LFO or curve later) sets a start and an end
value. At the low end of the source the parameter is exactly the start; at the high end, exactly the
end, whatever the range: increasing or inverted, negative, tiny or huge, or both ends equal.

**Why this priority**: It is the roadmap's acceptance ("Zero and one map to configured endpoints
exactly").

**Independent Test**: For each representative output range, map positions 0 and 1 (and source
values at and beyond the input range ends) and compare with `==` to the configured ends.

**Acceptance Scenarios**:

1. **Given** output ranges 0…1, 0.2…0.9, 0.9…0.1, −3…7, 7…−3, −5…−1, 1e−9…2e−9, −1e300…1e300, 1e300…1.5e300, 0.1…0.1, **When** positions 0 and 1 are mapped, **Then** the results equal the start and the end exactly.
2. **Given** input range 0.25…0.75, **When** inputs 0.25 and below (and −∞, NaN) or 0.75 and above are mapped, **Then** the result is exactly the start, or exactly the end (non-finite → the start).

---

### User Story 2 - Values in between stay in range and move one way (Priority: P1)

Between the ends, the mapped value never leaves the configured range and never moves backwards as
the source rises, so a parameter fed by a rising source rises smoothly (or falls, when inverted),
and later rows (curves, macros) can rely on it.

**Why this priority**: The roadmap asks for a *bounded* destination range; curves (MOD-004) are
specified as monotonic and bounded and inherit these properties.

**Independent Test**: Sweep positions over each representative range and walk adjacent
representable positions at a few points; every result lies within the ends and is ordered.

**Acceptance Scenarios**:

1. **Given** each representative range, **When** 1,001 evenly spaced positions and 1,000 adjacent representable positions around five points are mapped, **Then** every result lies within the ends and results are non-decreasing for increasing ranges (non-increasing for inverted ones).
2. **Given** a constant range (start = end), **When** any position is mapped, **Then** the result equals the end exactly.

---

### User Story 3 - Existing bindings behave the same (Priority: P1)

Bindings from MOD-002 keep their behavior: the same endpoints, the same values for every fixture,
the same app catalog results; only invisible last-digit differences may appear for same-sign
ranges.

**Why this priority**: The row must not change app behavior.

**Independent Test**: MOD-002's test suites pass unchanged; a regression sweep compares the new
mapping with MOD-002's formula.

**Acceptance Scenarios**:

1. **Given** MOD-002's tests (ParameterGraph and VisualGenerators), **When** they run after the change, **Then** they pass unchanged.
2. **Given** ranges whose ends have opposite signs or include zero, **When** 1,001 positions are mapped, **Then** results are bit-identical to MOD-002's formula; for same-sign ranges they differ by at most 2 units in the last place.

### Edge Cases

- Equal output ends: a constant mapping; every input maps to that value exactly.
- Inverted output ends: the mapping falls as the input rises.
- Input range not increasing or not finite, output ends not finite: the mapping reports itself invalid and never traps when used (MOD-003-R8); bindings keep refusing them (MOD-002 contract C2).
- Non-finite input or position: the start.
- Spans near the limit of Double (−1e300…1e300): no overflow (the opposite-sign branch never subtracts the ends).
- Signed zero: −0 and +0 compare equal; the result at position 0 is the start as configured.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-003-R1**: A linear mapping MUST be a value with an input range (minimum, maximum) and an output range (start, end). It is valid when all four are finite and the input minimum is below the maximum. An end below the start inverts it. The default input range is 0…1.
- **MOD-003-R2**: Its position for an input MUST be the input's place in the input range, clamped to 0…1; a non-finite result MUST be 0.
- **MOD-003-R3**: Interpolating a position MUST return exactly the start at 0 and exactly the end at 1 for every finite pair of ends (equal, increasing or inverted).
- **MOD-003-R4**: For positions in 0…1 the result MUST lie within the two ends and MUST be monotonic (non-decreasing in the position for increasing ends, non-increasing for inverted). Positions outside 0…1 or non-finite are clamped first (non-finite → 0).
- **MOD-003-R5**: Mapping an input MUST equal interpolating its position (input clamping then interpolation).
- **MOD-003-R6**: The mapping MUST be pure (no state, no clock), deterministic, allocation-free, `Sendable` and `Hashable`, dependency-free and built and tested on every CI host, Linux included (MOD-002-R9, R10).
- **MOD-003-R7**: The audio feature modulator MUST compute its signal position and its mapped value with this mapping; a binding MUST expose its mapping. Results MUST be bit-identical to MOD-002 at the ends and for output ends of opposite sign or including zero, and differ by at most 2 units in the last place otherwise; validation and the app are unchanged.
- **MOD-003-R8**: Using an invalid mapping MUST NOT trap: positions stay clamped to 0…1 (non-finite → 0) and the result is deterministic; callers (bindings) refuse invalid mappings before use.

### Key Entities

- **Linear mapping**: input range (minimum, maximum), output range (start, end); position, interpolation and mapping; validity and inversion.
- **Audio feature binding** (MOD-002): exposes its input and output ranges as a linear mapping.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-003-S1**: For 10 representative output ranges (increasing, inverted, negative, tiny, huge, constant), positions 0 and 1 map to the configured ends exactly in 100 % of cases.
- **MOD-003-S2**: Over those ranges, every swept and adjacent-position result lies within the ends and is ordered: zero violations.
- **MOD-003-S3**: Out-of-range and non-finite inputs map to the start or end exactly: zero violations.
- **MOD-003-S4**: MOD-002's existing tests pass unchanged; the regression sweep is bit-identical for opposite-sign and zero-including ranges and within 2 units in the last place otherwise.
- **MOD-003-S5**: Each new unit test takes about 1-2 s or less; the ParameterGraph suite stays under 1 minute (owner rule 7); ParameterGraph and VisualGenerators pass on the host and in the Linux build shape.

## Assumptions

- The binding API keeps its stored fields (input minimum/maximum, output start/end) for source compatibility; the mapping is exposed as a computed view.
- Curves (MOD-004) will apply a shaping function to the position before interpolation; nothing here blocks that.
- No device step and no app change; simulator results are never device evidence (Constitution X).
