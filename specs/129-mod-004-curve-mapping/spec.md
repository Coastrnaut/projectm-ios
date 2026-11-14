# Feature Specification: MOD-004 Curve Mapping

**Feature Branch**: `feature/mod-004` (spec directory `129-mod-004-curve-mapping`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-004 (Curve mapping) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Add ease-in, ease-out, logarithmic and custom piecewise curves."
Acceptance, verbatim: "Monotonic curve fixtures remain bounded and deterministic." Priority P1, effort
M, depends on MOD-003 (integrated). Verification: unit graph tests + simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-004-R1…`, success criteria `MOD-004-S1…`, research decisions `MOD-004-D1…`,
tasks `MOD-004-T01…`. Other features are cited by their own IDs: MOD-002 (audio feature bindings),
MOD-003 (linear mapping), SHD-009 (expression mappings), ACC-012 (sensory safety clamp), MOD-013 and
SCN-012 (binding restore and scene validation), QA-004 (migration matrix meta-test), MIDI-003 and
MIDI-004 (MIDI learn; CC scaling with curve and inversion, the next row that reuses this one).

## Baseline: what exists today (audit of 2026-11-14, commit `3c373722`)

The row's gap status is "Gap candidate". The audit finds a full gap: every mapping is linear.

| Area | Today |
|---|---|
| Where mapping happens | `AudioFeatureModulator.advance` turns the feature into a 0…1 position with the binding's `LinearMapping.position(of:)` (MOD-003; non-finite → 0, clamped), smooths it with the attack/release envelope into the binding's signal, and `effective(_:manual:)` maps the signal into the output range with `LinearMapping.interpolate` (exact ends, bounded, monotonic), then mixes (replace, add, multiply) with the manual value and clamps to the parameter's range. |
| MOD-003 | `Packages/ParameterGraph/Sources/ParameterGraph/LinearMapping.swift`; its header already says "Curves (MOD-004) shape the position, then interpolate". |
| SHD-009 | `ExpressionMapping` limits a compiled formula's value to 0…1 with MOD-003's `clampedPosition` and interpolates with MOD-003; it is not yet wired into bindings ("a later row"). Its whitelist has `pow` and `smoothstep` but no curve opcode. |
| Safety | ACC-012's `SafetyClamp` caps the resolved glow intensity in `NativeSpectrumHost` after the binding is resolved, so a binding can never pass the cap. |
| Scenes | SCN-001 stores bindings as `source`, `target`, `input`, `output`, `mix`, `envelope`, optional `expression`; unknown fields are kept verbatim (`SceneBinding.extra`). MOD-013 restores each binding on its own with a report entry (restored, rewritten, dropped, orphaned, rejected); SCN-012 reports issues by stable code. |
| MIDI | MIDI-003 stores `cc:<channel>:<number>=<parameter ID>` lines and ignores `;`-separated options after the ID, left for MIDI-004. Its CC values are mapped linearly. |
| Binding UI | None for users. Bindings are created in code and restored from scenes; the only binding screen is the DEBUG `UITestModulationPanel` used by MOD-002's UI test. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Where in the binding pipeline does the curve apply: before the envelope (shaping the target) or after it (shaping the smoothed signal)? → A: After the envelope, immediately before MOD-003's interpolation: `interpolate(curve(signal))`. The envelope's attack and release times keep their meaning in the source's 0…1 units, the stored signal stays the linear one, and MIDI-004 (no envelope) shapes its normalized CC value the same way. Rejected: before the envelope (the envelope would smooth already-shaped values, so the same attack time would feel different per curve) (MOD-004-R6).
- Q: Do piecewise curves interpolate linearly or with a smooth monotone cubic (Fritsch–Carlson)? → A: Linear between points. It is exactly monotone under floating-point rounding (each segment is MOD-003's interpolation), simple to validate and to explain, and smooth shapes are covered by the built-in kinds. Rejected: monotone cubic (tangent limiting adds rounding paths that need their own monotonicity proof; can be added later as another kind without breaking stored data) (MOD-004-R1; research MOD-004-D2).
- Q: Do piecewise points include the ends, and how many are allowed? → A: Interior points only, at most 8, with x strictly inside (0, 1); the ends (0, 0) and (1, 1) are implicit. So f(0) = 0 and f(1) = 1 hold for every curve, and a floor or ceiling is expressed by the binding's output range, as today. An empty piecewise curve is linear. Rejected: user-set ends (would break the universal end guarantee and duplicate the output range) (MOD-004-R1, R5).
- Q: Are invalid curves repaired or rejected? → A: Rejected at every boundary: binding (a new refusal reason naming the curve) and scene restore (the binding is rejected and kept verbatim, MOD-013's existing outcome). Evaluation of an invalid curve that is used anyway is defensive (parameters limited to the allowed range, unusable points skipped) so it never traps and stays bounded and monotonic, but nothing silently rewrites a stored curve. Rejected: silent repair (a scene would play differently from what was authored without the author seeing why) (MOD-004-R5, R6, R9).
- Q: What does a non-finite input give? → A: 0, the same as MOD-003's position rule (NaN, −∞ and +∞ all read 0); negative inputs give 0 and inputs above 1 give 1 (MOD-004-R3).
- Q: How does an unknown curve kind from a newer version behave when a scene opens? → A: Its binding is not applied, is preserved verbatim for re-save (MOD-013 "rejected"), and SCN-012 reports a new warning code `unsupportedCurve` grouped with the other mapping problems in the repair report. Applying it as linear was rejected: a guessed shape could drive a parameter differently from the author's intent, and preserving the unknown curve on a live binding would need extra live state (MOD-004-R9).
- Q: Does SHD-009 get a curve opcode? → A: No new opcode. The expression language already has `pow` and `smoothstep`; extending its whitelist would change its contract. Instead `ExpressionMapping` accepts a curve applied to the formula's 0…1 position, the natural seam (MOD-004-R8).
- Q: Is a curve picker added to the UI? → A: No: there is no user-facing binding editor to host it (only the DEBUG modulation test panel). The model, scene persistence and the text form are complete so a future editor or MIDI-004 can add the picker; the row's simulator verification is the app's unit test host on the simulator (MOD-004-S5).
- Q: What text form will MIDI-004 append to its mapping lines? → A: `;curve=<form>` where the form is `linear`, `easeIn:<p>`, `easeOut:<p>`, `easeInOut:<p>`, `log:<k>`, `exp:<k>` or `piecewise:<x>,<y>/<x>,<y>…`, numbers in their shortest round-trip decimal text. The form never contains `;` or `=`. This row implements and tests the form on the curve type only; MIDI-004 adds it to the MIDI lines (MOD-004-R10).
- Q: What are the parameter ranges? → A: Exponent 1 < p ≤ 8 (ease-in, ease-out, ease-in-out); strength 0 < k ≤ 1000 (logarithmic, exponential). These span gentle to very steep shapes while keeping every value representable without overflow (MOD-004-R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A binding can follow a curve instead of a straight line (Priority: P1)

Whoever configures a binding (a scene today; MIDI-004 and a binding editor later) chooses how the
source's 0…1 position is shaped before it reaches the output range: linear (today), ease-in (slow
start), ease-out (fast start), ease-in-out, logarithmic (quiet sounds count more), exponential (the
inverse), or a custom piecewise curve of a few points. Whatever the choice, the lowest source still
gives the configured start and the highest the configured end.

**Why this priority**: It is the roadmap's observable behavior.

**Independent Test**: Map a few positions through each curve kind and through a binding that uses it;
compare with the curve's formula.

**Acceptance Scenarios**:

1. **Given** an ease-in curve with exponent 2, **When** position 0.5 is shaped, **Then** the result is 0.25; an ease-out curve with exponent 2 gives 0.75; a logarithmic curve with strength 9 gives log(5.5)/log(10).
2. **Given** a piecewise curve through (0.5, 0.8), **When** positions 0.25, 0.5 and 0.75 are shaped, **Then** the results are 0.4, 0.8 and 0.9 (straight lines between the implicit (0, 0), the point and the implicit (1, 1)).
3. **Given** a binding from the lowest band to the glow intensity with an ease-in curve (exponent 2), **When** the band level is 0.5, **Then** the glow intensity is 0.25; with the sensory-safety cap at 0.5 and the band at 1, the intensity is 0.5.

---

### User Story 2 - Every curve stays bounded, monotonic and deterministic (Priority: P1)

Whatever curve or parameter is chosen, and whatever arrives as input (out of range, infinite, not a
number), the shaped value stays within 0…1, never moves backwards as the input rises, starts at 0 and
ends at 1, and the same input always gives the same output.

**Why this priority**: It is the roadmap's acceptance ("Monotonic curve fixtures remain bounded and
deterministic"), and it keeps every curve inside MOD-003's guarantees and ACC-012's caps.

**Independent Test**: For fixtures of every curve kind with several parameters (the extremes of each
allowed range included), sweep a dense input grid plus edge values twice.

**Acceptance Scenarios**:

1. **Given** each fixture, **When** 1,001 evenly spaced inputs in 0…1, adjacent representable inputs near 0, 0.5 and 1, and the edge inputs −1, −0, 2, NaN, −∞, +∞ are shaped, **Then** every output is in 0…1, outputs are non-decreasing along the grid, input 0 gives exactly 0 and input 1 exactly 1, and a second run gives bit-identical outputs.
2. **Given** a non-finite input, **When** it is shaped, **Then** the output is 0 (as MOD-003 reads a non-finite position); a negative input gives 0 and an input above 1 gives 1.

---

### User Story 3 - Invalid custom curves never reach a parameter (Priority: P1)

A piecewise curve whose points are out of order, outside 0…1, repeated, decreasing, not numbers or
too many is refused when a binding is made and reported when a scene is opened; an unknown curve kind
from a newer version is reported and kept so a re-save does not lose it. Using an invalid curve
directly still never traps and stays bounded and monotonic.

**Why this priority**: Bindings refuse invalid input today (MOD-002 contract C2); curves must not open
a way around it.

**Independent Test**: Build invalid curves and bind them; open scenes with invalid and unknown curves
and read the restore report and the issues.

**Acceptance Scenarios**:

1. **Given** a piecewise curve with x values 0.6 then 0.4, **When** it is bound, **Then** the binding is refused with a reason naming the curve, and the previous bindings are unchanged.
2. **Given** a scene whose binding has the curve kind "bezier", **When** it is opened, **Then** the binding is reported (rejected, issue code `unsupportedCurve`), is not applied, and re-saving the scene writes the curve back unchanged.
3. **Given** a scene whose binding has a decreasing piecewise curve, **When** it is opened, **Then** the binding is rejected with an `invalidBinding` issue naming the curve.

---

### User Story 4 - Existing bindings and scenes behave exactly as before (Priority: P1)

A binding without a curve is linear and gives bit-identical values to today's pipeline; a scene
without curves is read and written byte for byte as before, with no format version change.

**Why this priority**: The row must not change app behavior or the scene format for existing users.

**Independent Test**: Compare the curved pipeline with the linear default over a dense grid; round-trip
existing scene fixtures; run QA-004's meta-test and MOD-002/MOD-003/MOD-013's suites unchanged.

**Acceptance Scenarios**:

1. **Given** the default (linear) curve, **When** a dense grid of signals is resolved through a binding, **Then** every value is bit-identical to MOD-003's interpolation of the same signal.
2. **Given** existing scene fixtures, **When** they are decoded and encoded, **Then** no `curve` field appears and the format version is unchanged.
3. **Given** a binding with each curve kind, **When** a scene holding it is saved and reopened, **Then** the curve is identical.

### Edge Cases

- Empty piecewise curve (no interior points): identical to linear.
- Piecewise points at x = 0 or x = 1: refused (the ends are implicit, so f(0) = 0 and f(1) = 1 hold for every curve).
- Flat segments (equal y values): allowed (non-decreasing).
- A vertical step is impossible (x strictly increasing).
- Extreme parameters (the largest exponent or strength): the curve is steep but still bounded and monotonic, with exact ends.
- −0 input: gives 0.
- Curve combined with an inverted output range: the binding falls as the input rises, following the curve's shape.
- Curve combined with an envelope: the envelope smooths the 0…1 signal; the curve shapes the smoothed signal.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-004-R1**: A mapping curve MUST be a value of one of these kinds: linear; ease-in (power p); ease-out (1 − (1 − x)^p); ease-in-out (power p on each half); logarithmic (log(1 + k·x) / log(1 + k)); exponential (its inverse, ((1 + k)^x − 1) / k); piecewise (up to 8 interior points joined by straight lines through the implicit ends (0, 0) and (1, 1)).
- **MOD-004-R2**: Shaping an input MUST return exactly 0 for input 0 and exactly 1 for input 1, a value in 0…1 for every input, and a result non-decreasing in the input, for every valid curve.
- **MOD-004-R3**: A non-finite input MUST give 0; inputs below 0 give 0 and above 1 give 1 (MOD-003's position rule).
- **MOD-004-R4**: Shaping MUST be pure and deterministic (no clock, randomness or state), allocation-free, and usable from any thread; the type MUST build and be tested on every CI host, Linux included.
- **MOD-004-R5**: A curve MUST report whether it is valid and why not: exponent finite with 1 < p ≤ 8; strength finite with 0 < k ≤ 1000; piecewise at most 8 points, each finite, x strictly increasing inside the open interval (0, 1), y in 0…1 and non-decreasing. An invalid curve used anyway MUST NOT trap and MUST still satisfy R2 and R3.
- **MOD-004-R6**: An audio feature binding MUST carry a curve, linear by default; the modulator MUST shape the binding's smoothed signal with it before MOD-003's interpolation into the output range. A binding with an invalid curve MUST be refused with a reason, leaving the bindings unchanged.
- **MOD-004-R7**: With the linear curve every resolved value MUST be bit-identical to the pipeline before this row.
- **MOD-004-R8**: SHD-009's expression mapping MUST accept a curve (linear by default) applied between the formula's 0…1 position and the interpolation.
- **MOD-004-R9**: Scenes MUST store a non-linear binding curve in an optional `curve` field of the binding and omit it for linear, with no format version change; a curve this version cannot read MUST keep its binding unapplied, preserved verbatim and reported (`unsupportedCurve`); a readable but invalid curve MUST reject its binding (`invalidBinding`).
- **MOD-004-R10**: A curve MUST have a compact one-line text form, documented for MIDI-004's `;curve=<form>` option, that reads back to the same curve; unreadable text reads as nothing.
- **MOD-004-R11**: Values resolved through a curved binding MUST still pass ACC-012's safety clamp before rendering.

### Key Entities

- **Mapping curve**: kind and its parameter (exponent, strength or points); validity; shaping 0…1 → 0…1; text form.
- **Curve point**: x and y in 0…1.
- **Audio feature binding** (MOD-002): gains a curve.
- **Scene binding** (SCN-001): gains an optional stored curve.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-004-S1**: For at least 20 curve fixtures (every kind, several parameters each, the allowed extremes included), over 1,001 grid inputs plus edge values: zero outputs outside 0…1, zero decreases, exact 0 and 1 at the ends, and two runs bit-identical.
- **MOD-004-S2**: Every invalid piecewise fixture (at least 7 kinds of fault) is refused by validation and by binding; each still shapes inputs bounded and monotonic.
- **MOD-004-S3**: Linear bindings are bit-identical to MOD-003's interpolation over the grid; existing ParameterGraph, SceneFormat (QA-004 meta-test included) and app binding tests pass unchanged.
- **MOD-004-S4**: Each curve kind survives a scene save and reopen and a text-form round trip; an unknown kind is reported and re-saved unchanged.
- **MOD-004-S5**: A curved binding drives the glow end to end in the app's test host on the simulator and is capped by the safety clamp.
- **MOD-004-S6**: Each new unit test takes about 1-2 s or less; each package suite stays under 1 minute (owner rule 7).

## Assumptions

- No user-facing binding editor exists, so no curve picker is added; the model, its persistence and its text form are ready for one (and for MIDI-004).
- The curve is applied after the envelope, so envelope times keep their meaning in the source's units.
- Simulator results are never device evidence (Constitution X); this row has no device task.
