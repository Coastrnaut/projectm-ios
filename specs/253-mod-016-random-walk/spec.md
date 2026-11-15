# Feature Specification: MOD-016 Random walk modulator

**Feature Branch**: `feature/mod-016` (spec directory `253-mod-016-random-walk`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MOD-016 (Random walk modulator) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Generate bounded seeded smooth random
parameter motion." Acceptance, verbatim: "Seeded timeline reproduces identical values and never leaves
bounds." Priority P2, effort M, depends on MOD-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-016-R1…`, success criteria
`MOD-016-S1…`, research decisions `MOD-016-D1…`, tasks `MOD-016-T01…`. Other features are cited by their
own IDs: MOD-001 (typed parameter registry), MOD-007 (sine and triangle oscillators, `audio.lfo.<index>`
binding source, scene `lfos` list), MOD-008 (square and seeded sample-and-hold, counter-based seeded
levels), MOD-009 (tempo-synced cycle length), ACC-012 / FR-072 (Reduce flashing), SCN-001 / SCN-012
(scene document and its issue report), QA-004 (scene migration matrix meta-test).

## Baseline: what exists today (audit of 2026-11-14, commit `ae588a5d`)

| Question | Today |
|---|---|
| Oscillators | MOD-007/008: sine, triangle, square, sample-and-hold; rate 0.01…20 Hz, phase, amplitude, centre; the value is a pure function of the integer elapsed nanoseconds since the bank's origin; the whole-cycle count (step) is exact for hours; up to 8 per scene; Reduce flashing caps the effective rate at 3 Hz. |
| Seeded randomness | MOD-008: a counter-based seeded level per step (a pure function of seed and step number); a stored 32-bit seed or a default derived from the oscillator's position. Sample-and-hold may glide linearly from the previous level for part of a step, then holds: not a smooth continuous motion. |
| Tempo sync | MOD-009: an optional cycle length in beats; a synced oscillator continues its phase and step count across rate changes. |
| App feed | `NativeSpectrumHost.applyModulation` evaluates the bank once per frame at the frame's display time; bindings read `audio.lfo.<index>` and map it onto any compatible parameter (MOD-001 registry, MOD-002 bindings). |
| Scenes | `lfos` entries are kept verbatim (unknown fields included); an unknown shape is reported (`unknownLFO`) and the oscillator is kept but not used. |
| Editor UI | None for oscillators (MOD-007, MOD-008 and MOD-009 decided the same); oscillators come from scene files. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Smooth random motion that repeats exactly for the same seed (Priority: P1)

A scene author adds a random walk modulator to drift a parameter (for example the glow) smoothly and
unpredictably. The motion comes from the modulator's seed, so the same scene played again, on any device,
at any frame rate and after any pause or seek, produces exactly the same values at the same times on the
timeline; a different seed gives a different motion.

**Why this priority**: This is the roadmap acceptance ("seeded timeline reproduces identical values").

**Independent Test**: Run two random walks with the same seed and timebase, sampled at 60 frames per
second, 120 frames per second and with irregular frame times; compare the values at every time the runs
share. Repeat with a different seed and check that the values differ.

**Acceptance Scenarios**:

1. **Given** two random walks with the same seed and settings, **When** they are sampled with different
   frame timings, **Then** they give identical values at every shared time (exact equality).
2. **Given** a different seed, **When** it runs over the same times, **Then** the values differ.
3. **Given** a time far along the timeline, **When** it is sampled directly (a seek), **Then** it reads the
   same value as a run that played up to it frame by frame.

---

### User Story 2 - Motion that never leaves its bounds and never jumps (Priority: P1)

The random walk moves within its configured range (centre and depth) and never outside 0…1, however long
it runs, and moves smoothly: no jumps between frames, with a smoothness setting from gentle corners to
fully rounded motion.

**Why this priority**: The second half of the acceptance ("never leaves bounds"); smoothness is what
separates it from sample-and-hold.

**Independent Test**: Sweep the modulator densely over long durations (minutes, plus spot sweeps through
ten hours) with extreme settings and check every value; measure the largest change between neighbouring
samples at a given rate.

**Acceptance Scenarios**:

1. **Given** any valid settings, **When** the walk is sampled anywhere on a ten-hour timeline, **Then** every
   value is finite and within its range, which lies within 0…1.
2. **Given** a rate and a frame interval, **When** consecutive frames are compared, **Then** the change never
   exceeds the bound set by the rate, the depth and the frame interval.
3. **Given** the smoothness setting, **When** it is at its maximum, **Then** the motion eases into and out of
   each random target; at its minimum it moves at a constant speed between targets.

---

### User Story 3 - Stored, safe and live in the app (Priority: P2)

A scene stores the random walk (its rate or tempo sync, smoothness, depth and seed). Older apps keep the
entry verbatim. Reduce flashing still caps the rate at 3 Hz. In the app, a random walk bound to the glow
drives it.

**Why this priority**: Persistence and safety make the feature usable; the app test proves the wiring.

**Independent Test**: Scene round trip and issue paths; an app unit test with a random walk on the glow.

**Acceptance Scenarios**:

1. **Given** a scene with a random walk, **When** it is saved and reopened, **Then** its shape, rate, sync,
   smoothness, depth and seed are kept exactly; scenes without random walks write nothing new.
2. **Given** an out-of-range smoothness, **When** the scene opens, **Then** it opens, a warning names the
   oscillator, the oscillator is not used and the entry is kept verbatim.
3. **Given** a fast random walk and Reduce flashing on, **When** it runs, **Then** it reaches at most 3 new
   targets per second.
4. **Given** the app with a random walk on the glow, **When** frames advance, **Then** the effective glow
   equals the walk's value at each frame's time.

### Edge Cases

- Two random walks without a stored seed in one scene must not move in lockstep.
- A frame exactly on a target time reads that target exactly.
- Hours of running: the value stays exact (no drift, no accumulated error).
- A tempo-synced random walk whose tempo changes continues from where it is, without a jump.
- Depth 0 holds the centre; a centre near 0 or 1 with full depth stays within 0…1.
- Non-finite results never reach a parameter.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-016-R1**: An oscillator MAY use a random walk shape in addition to the existing shapes.
- **MOD-016-R2**: A random walk's value MUST be a pure function of its settings, its seed and the time on
  its timeline: identical for any frame timing, dropped frames, pauses or seeks.
- **MOD-016-R3**: The random walk MUST move continuously from one seeded random target to the next, reaching
  one new target per cycle (the rate or the tempo-synced cycle length); the targets come from the same
  seeded source as sample-and-hold.
- **MOD-016-R4**: Every value MUST be finite and within centre ± depth/2 clipped to 0…1, by construction:
  between two targets the value never goes beyond either of them.
- **MOD-016-R5**: A smoothness setting (0…1, default 1) MUST set how the walk moves between targets, from a
  constant speed (0) to easing in and out (1); values outside 0…1 MUST be refused.
- **MOD-016-R6**: The change between two samples MUST be bounded by a fixed multiple of the depth, the
  effective rate and the time between them.
- **MOD-016-R7**: Seeds MUST work as for sample-and-hold: a stored whole number 0…4294967295, or a default
  derived from the oscillator's position.
- **MOD-016-R8**: Tempo sync (MOD-009) and the Reduce flashing cap (3 Hz) MUST apply; a rate change MUST
  continue the motion without a jump.
- **MOD-016-R9**: A scene MUST store the shape and the smoothness in the oscillator entry (smoothness only
  when not the default), with no format version change; an invalid smoothness makes the oscillator
  unusable with a warning, entry kept.
- **MOD-016-R10**: The code MUST stay pure, allocation-free per frame and build on Linux.

### Key Entities

- **Random walk**: an oscillator shape that drifts smoothly between seeded random targets.
- **Target**: the seeded random level reached at the start of each cycle.
- **Smoothness**: how the motion eases between targets.
- **Seed**: the number that fixes the sequence of targets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-016-S1**: With the same seed and timebase, 60 Hz, 120 Hz, irregular frame timings and direct seeks
  give identical values at every shared time (exact equality over at least 100 cycles); a different seed
  differs.
- **MOD-016-S2**: Every sampled value over dense sweeps of long runs (including spot sweeps through ten
  hours) at extreme settings stays finite and within its bounds.
- **MOD-016-S3**: No change between consecutive samples exceeds the continuity bound.
- **MOD-016-S4**: Scene round trips keep shape, smoothness and seed; invalid values are reported and kept;
  scenes without random walks encode byte-identically.
- **MOD-016-S5**: In the app a random walk on the glow drives it with its values.
- **MOD-016-S6**: The affected package suites pass and build for Linux, each under one minute.

## Assumptions

- No editor UI is added (none exists for oscillators); reseeding means editing the scene's seed.
- Range uses the existing centre and depth (amplitude) settings; rate and sync are the existing ones.
- No UserDefaults key is added.
