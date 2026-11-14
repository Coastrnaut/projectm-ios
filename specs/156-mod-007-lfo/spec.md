# Feature Specification: MOD-007 LFO Sine and Triangle

**Feature Branch**: `feature/mod-007` (spec directory `156-mod-007-lfo`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-007 (LFO sine and triangle) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Create clocked low-frequency oscillators with phase and amplitude." Acceptance,
verbatim: "Known time samples match mathematical waveforms." Priority P1, effort M, depends on MOD-001
(integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-007-R1…`, success criteria
`MOD-007-S1…`, research decisions `MOD-007-D1…`, tasks `MOD-007-T01…`. Other features are cited by their
own IDs: MOD-001 (parameter registry), MOD-002 (audio feature bindings and sources), MOD-003 (range
mapping), MOD-004 (curves), MOD-005 (envelopes, injected clock), MOD-006 (threshold triggers), MOD-008
(square and sample-and-hold LFOs), MOD-009 (tempo-synced LFO), MOD-014 (modulation graph), SHD-009
(expressions), ACC-012 (sensory safety profile), FR-072 (Reduce flashing), SCN-001 / SCN-012 (scene
document and its issue report), QA-004 (scene migration matrix meta-test).

## Baseline: what exists today (audit of 2026-11-14, commit `a32611cd`)

| Question | Today |
|---|---|
| Modulation sources | MOD-002's `AudioFeatureSource` reads eight normalized (0…1) audio features per frame; a binding maps one through range (MOD-003), curve (MOD-004) and envelope (MOD-005) onto a parameter. |
| Time-based sources | None. SHD-009 expressions have a `time` value and `sin`, but only inside an expression; no binding can follow a clocked oscillator. |
| Clock | Bindings and triggers use the frame's display time passed in (`timeNanoseconds`); no wall clock. |
| Graph | MOD-014's graph already names LFOs as future generator nodes (`lfo.one`), with no implementation. |
| Tempo | SHOW-011 tap tempo and the tempo estimate exist; MOD-009 is the roadmap row for tempo-synced LFOs. |
| Safety | FR-072 Reduce flashing and the ACC-012 safety clamp limit the glow and flash envelope after modulation. |
| Scenes | Bindings, modulation, groups, effects and (MOD-006) triggers are stored; no oscillator field. |
| UI | No binding editor (MOD-004 to MOD-006 had none either). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

(Recorded by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An oscillator's value at a known time is exactly the waveform's value (Priority: P1)

A scene author wants a parameter (for example the glow) to breathe slowly with a sine or triangle wave
of a chosen rate, phase, depth and centre. The oscillator's value at any moment must be exactly what
the mathematical waveform gives, so a show looks the same every time and never drifts.

**Why this priority**: This is the roadmap acceptance: "Known time samples match mathematical waveforms."

**Independent Test**: For sine and triangle at several rates, phases, amplitudes and centres, sample at
t = 0, ¼, ½ and ¾ of a period, at irrational times and after hours of running, and compare with the
closed-form waveform.

**Acceptance Scenarios**:

1. **Given** an oscillator with a shape, rate, phase offset, amplitude and centre, **When** it is sampled
   at 0, ¼, ½ and ¾ of a period, **Then** each value equals the closed-form waveform within 1e-9.
2. **Given** the same oscillator, **When** it is sampled at irrational times (π s, √2 s), **Then** each
   value equals the closed-form waveform within 1e-9.
3. **Given** an oscillator that has run for hours, **When** it is sampled, **Then** the value still equals
   the closed-form waveform within 1e-9 (no accumulated drift).

---

### User Story 2 - Deterministic, bounded and safe (Priority: P1)

The value depends only on the elapsed time since the oscillator's origin, so two runs (and any frame
rate) give identical values. The output always stays within 0…1. With Reduce flashing on, a fast
oscillator cannot strobe a brightness parameter.

**Why this priority**: An oscillator on brightness is a flash risk (Constitution, FR-072); results that
depend on frame rate would make shows unrepeatable.

**Independent Test**: Two runs with different frame steps give identical values at shared times; values
at extreme settings stay within 0…1; with Reduce flashing the effective rate is at most 3 Hz.

**Acceptance Scenarios**:

1. **Given** two runs sampling at 60 fps and 120 fps, **When** they are compared at the same times,
   **Then** the values are bit-identical.
2. **Given** an amplitude and centre whose swing would leave 0…1, **When** the oscillator is sampled,
   **Then** the output is clamped to 0…1.
3. **Given** a 10 Hz oscillator and Reduce flashing on, **When** it runs, **Then** it oscillates at 3 Hz.

---

### User Story 3 - A scene keeps its oscillators and they drive bindings (Priority: P2)

A scene stores up to eight oscillators. A binding names an oscillator as its source, exactly as it names
an audio feature, and goes through the same range, curve and envelope. Opening the scene makes them
live; in the app an oscillator-driven binding moves the glow. A scene with an oscillator this version
cannot use still opens, reports where the problem is, and keeps the oscillator for re-save.

**Why this priority**: Without persistence and binding an oscillator exists only in code.

**Independent Test**: Scene round trip; a scene with invalid and unknown oscillators; an app unit test
with an oscillator binding on the glow intensity.

**Acceptance Scenarios**:

1. **Given** a scene with oscillators, **When** it is saved and reopened, **Then** the oscillators are equal
   and give identical values.
2. **Given** a scene without oscillators, **When** it is saved, **Then** no new field is written.
3. **Given** an oscillator with a rate outside the allowed range or an unknown shape, **When** the scene
   opens, **Then** the scene opens, the oscillator is not live, a warning names its path, and the entry
   is written back unchanged with its unknown fields.
4. **Given** the app with a binding from an oscillator to the glow intensity, **When** frames advance,
   **Then** the effective glow follows the oscillator's waveform.

### Edge Cases

- Time before the origin (or a repeated time) reads as the origin (elapsed 0), never as negative time.
- Phase offset 1 is the same as 0.
- Amplitude 0 gives a constant equal to the clamped centre.
- A binding that names an oscillator the scene does not define (or one that is invalid) reads 0, like a
  missing audio feature.
- More oscillators than the limit: the extra ones are reported and kept, not live.
- Very long running time (days): the phase stays exact to well within the tolerance.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-007-R1**: An oscillator MUST have a shape (sine or triangle), a rate in hertz (0.01…20), a phase
  offset (0…1 cycle), an amplitude (0…1) and a centre (0…1); invalid settings MUST be refused.
- **MOD-007-R2**: Its value MUST be a pure function of the elapsed time since its origin:
  phase φ = frac(phase offset + rate·t), output = clamp(centre + amplitude/2 · w(φ), 0, 1), where the sine
  waveform is w(φ) = sin(2πφ) and the triangle waveform is the piecewise-linear wave with the same zero
  crossings and peaks (0 at φ = 0, +1 at ¼, 0 at ½, −1 at ¾).
- **MOD-007-R3**: The phase MUST be computed from the integer elapsed time without accumulated error, so
  the value after hours (and days) of running matches the closed form within 1e-9.
- **MOD-007-R4**: Results MUST be deterministic: identical times give identical values, independent of
  the frame rate or of how often the oscillator is sampled.
- **MOD-007-R5**: An oscillator MUST be usable as a binding source alongside the audio features, with the
  same range, curve, envelope and mix handling, without changing how existing audio bindings are written.
- **MOD-007-R6**: With Reduce flashing on (the ACC-012 effective setting) the effective rate MUST be at
  most 3 Hz.
- **MOD-007-R7**: A scene MUST store its oscillators in a new optional field, written only when the scene
  has oscillators, with no format version change; unknown fields of an oscillator are kept verbatim.
- **MOD-007-R8**: A stored oscillator that is invalid, uses an unknown shape, or exceeds the limit (8 per
  scene) MUST be reported with a warning at its path, not applied, and kept for re-save.
- **MOD-007-R9**: The app MUST evaluate a scene's live oscillators once per frame at the frame's display
  time and feed them to the bindings.
- **MOD-007-R10**: The oscillator MUST be a pure, allocation-free computation that builds on every CI
  host (Linux included).

### Key Entities

- **Oscillator (LFO)**: shape, rate, phase offset, amplitude, centre; value as a function of elapsed time.
- **Oscillator bank**: up to eight oscillators of a scene with one shared origin (the first frame after
  they are set).
- **Stored oscillator**: one entry of a scene's oscillator list, kept as written.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-007-S1**: For sine and triangle at several rates, phases, amplitudes and centres, samples at 0,
  ¼, ½, ¾ period, at irrational times and after hours match the closed-form waveform within 1e-9.
- **MOD-007-S2**: Two runs sampled at different frame rates give identical values at shared times; every
  tested setting keeps the output within 0…1.
- **MOD-007-S3**: With Reduce flashing on, no oscillator runs faster than 3 Hz.
- **MOD-007-S4**: A scene round trip keeps the oscillators exactly; a scene without oscillators encodes as
  before; invalid and unknown oscillators are reported at their paths and kept.
- **MOD-007-S5**: In the app, an oscillator-driven binding moves the effective glow along the waveform.
- **MOD-007-S6**: The ParameterGraph and SceneFormat suites keep passing on macOS and Linux, each under
  one minute.

## Assumptions

- No oscillator or binding editor is added (none exists; MOD-004 to MOD-006 decided the same).
- Square and sample-and-hold shapes are MOD-008; tempo sync is MOD-009.
- No settings key is added; oscillators live only in scenes.
