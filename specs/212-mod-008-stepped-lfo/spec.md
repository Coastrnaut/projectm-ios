# Feature Specification: MOD-008 Stepped LFO (square and sample-and-hold)

**Feature Branch**: `feature/mod-008` (spec directory `212-mod-008-stepped-lfo`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-008 (LFO square and sample-hold) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Add stepped oscillators with seeded
randomness." Acceptance, verbatim: "Same seed and timebase yield identical step values." Priority P2,
effort M, depends on MOD-007 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-008-R1…`, success criteria
`MOD-008-S1…`, research decisions `MOD-008-D1…`, tasks `MOD-008-T01…`. Other features are cited by their
own IDs: MOD-007 (sine and triangle oscillators, `audio.lfo.<index>` binding source, scene `lfos` list),
MOD-009 (tempo-synced cycle length, continuous phase segments), ACC-012 / FR-072 (Reduce flashing),
SCN-001 / SCN-012 (scene document and its issue report), QA-004 (scene migration matrix meta-test).

## Baseline: what exists today (audit of 2026-11-14, commit `691547a1`)

| Question | Today |
|---|---|
| Oscillators | MOD-007: sine and triangle; rate 0.01…20 Hz, phase, amplitude, centre; the value is a pure function of the integer elapsed nanoseconds since the bank's origin (no drift, no history); up to 8 per scene; Reduce flashing caps the effective rate at 3 Hz. MOD-007 left square and sample-and-hold to this row. |
| Tempo sync | MOD-009: an optional cycle length in beats; a synced oscillator keeps a phase segment and continues smoothly when its rate changes. |
| Randomness | None in the oscillators. Nothing seeded exists in the modulation package. |
| App feed | `NativeSpectrumHost.applyModulation` evaluates the bank once per frame at the frame's display time; bindings read `audio.lfo.<index>`. |
| Scenes | `lfos` entries are kept verbatim (unknown fields included); an unknown shape is reported (`unknownLFO`) and the oscillator is kept but not used. |
| Editor UI | None for oscillators (MOD-007 and MOD-009 decided the same); oscillators come from scene files. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Random steps that repeat exactly for the same seed (Priority: P1)

A scene author adds a sample-and-hold oscillator: at each cycle it jumps to a new random level and holds
it. The levels come from the oscillator's seed, so the same scene played again, on any device and at any
frame rate, produces the same sequence of levels; a different seed gives a different sequence.

**Why this priority**: This is the roadmap acceptance.

**Independent Test**: Run two sample-and-hold oscillators with the same seed and timebase, one sampled at
60 frames per second, one at 120 and one with irregular frame times; compare the level of every step.
Repeat with a different seed and check that the sequences differ.

**Acceptance Scenarios**:

1. **Given** two oscillators with the same seed, rate and phase, **When** they are sampled with different
   frame timings, **Then** every step holds the identical level in both (exact equality).
2. **Given** a different seed, **When** it runs over the same steps, **Then** the sequence of levels differs.
3. **Given** a step, **When** it is sampled anywhere inside it, **Then** it reads the same level (it holds).

---

### User Story 2 - A square wave with an adjustable duty cycle (Priority: P1)

A scene author adds a square oscillator that switches between its high and low levels; the share of the
cycle spent high (the duty cycle) defaults to half and can be set.

**Why this priority**: Square is the other stepped shape the row names.

**Independent Test**: Sample a square oscillator just before and just after the duty boundary and the
cycle boundary for several duty cycles.

**Acceptance Scenarios**:

1. **Given** a square oscillator with duty d, **When** it is sampled at a phase just below d, **Then** it is
   high; at d and after, **Then** it is low; at the start of the next cycle it is high again.
2. **Given** no duty cycle, **When** the oscillator runs, **Then** it is high for exactly half of each cycle.

---

### User Story 3 - Stored, safe and live in the app (Priority: P2)

A scene stores the shape, the duty cycle, the seed and an optional glide (a short ramp from one held
level to the next). Older apps keep the entry verbatim. Reduce flashing still caps the rate at 3 Hz. In
the app, a stepped oscillator bound to the glow drives it.

**Why this priority**: Persistence and safety make the feature usable; the app test proves the wiring.

**Independent Test**: Scene round trip and issue paths; an app unit test with a sample-and-hold oscillator
on the glow.

**Acceptance Scenarios**:

1. **Given** a scene with square and sample-and-hold oscillators, **When** it is saved and reopened,
   **Then** shape, duty cycle, seed and glide are kept exactly; a scene with only sine and triangle
   oscillators writes nothing new.
2. **Given** an out-of-range duty cycle, glide or seed, **When** the scene opens, **Then** it opens, a
   warning names the oscillator, the oscillator is not used and the entry is kept verbatim.
3. **Given** a fast stepped oscillator and Reduce flashing on, **When** it runs, **Then** it steps at most
   3 times per second.
4. **Given** the app with a sample-and-hold oscillator on the glow, **When** frames advance, **Then** the
   effective glow equals the oscillator's held level of the current step.

### Edge Cases

- Two sample-and-hold oscillators without a stored seed in one scene must not move in lockstep: the
  default seed depends on the oscillator's position.
- A frame exactly on a step or duty boundary belongs to the new step or the low half.
- Hours of running: the step number and phase stay exact (no drift, no rounding at a boundary).
- A tempo-synced stepped oscillator whose tempo changes keeps counting steps from where it is (no
  restart of the sequence and no repeated level).
- Glide never exceeds the step; with glide 0 the level jumps.
- Non-finite results never reach a parameter; values stay in 0…1.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-008-R1**: An oscillator MAY use the shapes square and sample-and-hold in addition to sine and
  triangle.
- **MOD-008-R2**: A square oscillator MUST be high (centre + amplitude/2) for phase < duty and low
  (centre − amplitude/2) otherwise; the duty cycle defaults to 0.5 and MUST be refused outside 0.05…0.95.
- **MOD-008-R3**: A sample-and-hold oscillator MUST hold one level per cycle (step); the level MUST be a
  pure function of the seed and the step number only, never of frame timing or earlier frames.
- **MOD-008-R4**: The step number MUST be the whole number of cycles since the origin (including the
  phase offset), exact for hours of running.
- **MOD-008-R5**: Each oscillator MAY store a seed (a whole number 0…4294967295); without one its seed
  MUST be derived from its position in the scene, so unseeded oscillators differ and repeat.
- **MOD-008-R6**: A sample-and-hold oscillator MAY glide: during the first glide fraction (0…1, default 0)
  of a step the level moves linearly from the previous step's level to the new one; the result stays a
  pure function of seed, step and phase.
- **MOD-008-R7**: Values MUST stay in 0…1 and finite; Reduce flashing MUST still cap the effective rate at
  3 Hz (so at most 3 steps or square cycles per second).
- **MOD-008-R8**: Tempo sync (MOD-009) MUST work for the new shapes, and a rate change MUST continue the
  step count without a restart.
- **MOD-008-R9**: A scene MUST store duty cycle, seed and glide in optional fields of the oscillator entry,
  written only when they matter (square: duty; sample-and-hold: seed when set, glide when not 0), with no
  format version change; out-of-range values make the oscillator unusable with a warning, entry kept.
- **MOD-008-R10**: The oscillator code MUST stay pure, allocation-free per frame and build on Linux.

### Key Entities

- **Shape**: sine, triangle, square or sample-and-hold.
- **Duty cycle**: the fraction of a square cycle spent high.
- **Seed**: the number that fixes a sample-and-hold sequence.
- **Step**: one cycle of a stepped oscillator, numbered from the origin.
- **Glide**: the fraction of a step spent ramping from the previous level.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-008-S1**: With the same seed and timebase, 60 Hz, 120 Hz and irregular frame timings give
  identical levels at every step (exact equality over at least 100 steps); a different seed differs.
- **MOD-008-S2**: Square transitions land exactly at the duty and cycle boundaries for several duty
  cycles.
- **MOD-008-S3**: Scene round trips keep shape, duty, seed and glide; invalid values are reported and
  kept; scenes without the new shapes encode byte-identically.
- **MOD-008-S4**: With Reduce flashing on no stepped oscillator steps more than 3 times per second.
- **MOD-008-S5**: In the app a sample-and-hold oscillator on the glow drives it with its held levels.
- **MOD-008-S6**: The affected package suites pass on macOS and build for Linux, each under one minute.

## Assumptions

- No editor UI is added (none exists for oscillators); reseeding means editing the scene's seed.
- The level distribution is uniform over the swing; no other distributions.
- No UserDefaults key is added.
