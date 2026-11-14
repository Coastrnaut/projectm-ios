# Feature Specification: MOD-015 Envelope Follower Bank

**Feature Branch**: `feature/mod-015` (spec directory `199-mod-015-envelope-follower-bank`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MOD-015-T01-T10 verified on the Mac: ParameterGraph and SceneFormat package tests on the host, app unit tests on a private iOS 27.2 simulator; no ADR, no device task)

**Input**: User description: "Implement MOD-015 (Envelope follower bank) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Expose slow, medium and fast envelopes per frequency band." Acceptance, verbatim:
"Step tests verify independent smoothing profiles." Priority P1, effort M, depends on ANL-002 (bands)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-015-R1…`, success criteria `MOD-015-S1…`,
research decisions `MOD-015-D1…`, tasks `MOD-015-T01…`. Other features are cited by their own IDs: ANL-002
(band levels), ANL-003 (display band smoothing), MOD-002 (audio feature bindings), MOD-005 (binding
attack/release envelope), MOD-006 (threshold triggers), MOD-007 (LFOs as binding sources), MOD-011 (layers),
MOD-012 (modulation matrix), MOD-013 (stored binding IDs), SHD-009 (expressions), UIX-003 (inspector).

## Baseline: what exists today (audit of 2026-11-14, commit `9759985c`)

| Question | Today |
|---|---|
| Band levels | ANL-002 bands (up to 128, 0…1) reach the modulation graph as `AudioFeatureSource.band(i)`, borrowed per frame in `AudioFeatureFrame.bands`. |
| Smoothing | ANL-003 `BandSmoother` (AnalysisFeatures) smooths the *displayed* bands with one user-set attack/release pair. MOD-005 `AudioFeatureEnvelope` gives each *binding* one attack/release one-pole envelope (`step(from:toward:elapsedSeconds:)`, exact under time splitting, NaN-safe, 0…1). |
| Several envelopes of one band at once | **None.** A band can be followed only through one binding's own envelope; a trigger (MOD-006) or a second layer cannot read "the slow envelope of band 3" as a source. |
| Clock | Bindings advance on the frame's display time in integer nanoseconds (`AudioFeatureModulator.advance`), Δt clamped to 0.25 s. |
| Sources as names | `AudioFeatureSource.id` (`audio.band.3`, `audio.lfo.0`, …) is what scenes store (MOD-013); LFO sources are binding-only, not formula names (MOD-007-D4). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: What are the three profiles' time constants? → A: Fixed one-pole time constants (τ, the MOD-005 definition: 63.2 % of a step at t = τ), attack while the band is above the envelope, release while below: **fast** attack 10 ms / release 80 ms, **medium** attack 80 ms / release 350 ms, **slow** attack 400 ms / release 1.6 s. Each attack is at most a quarter of its release, and each profile's attack is ≥ 4× the next faster one's, so the profiles are clearly distinct at 60 fps. Not user-adjustable in this feature (a binding's own MOD-005 envelope still smooths further) (MOD-015-R2).
- Q: Which clock? → A: The frame clock only: the frame's display time in integer nanoseconds, as bindings use. Δt is 0 on the first advance or when time does not increase, at most 0.25 s (a pause counts as 0.25 s). No wall clock (MOD-015-R4).
- Q: How are they exposed? → A: As new bindable sources, one per band and profile, `audio.bandEnvelope.<fast|medium|slow>.<band>` (band 0…127), named "Band 4 fast" (1-based) in the inspector and the matrix. Bindings (MOD-002/MOD-011 layers) and threshold triggers (MOD-006) accept them; scenes store them by ID like other sources, and an older version orphans the unknown ID (MOD-013 path). They are **not** formula names in expressions (as MOD-007-D4 for LFOs), so no new expression opcode is needed (MOD-015-R5, R6).
- Q: Where is state kept and when does it start? → A: In one bank per modulation host, preallocated for 128 bands × 3 profiles. Each envelope starts at 0 and the bank resets to 0 when the band count changes. It advances on every frame the host evaluates modulation (MOD-015-R3, R7).
- Q: Robustness? → A: A non-finite band reads 0, an input above 1 reads 1 and below 0 reads 0; outputs are always finite and in 0…1. Splitting one interval of constant input into several advances gives the same envelope to 1e-12 (chunking invariance) (MOD-015-R8, R9).
- Q: Does the bank run while nothing uses modulation? → A: No. It advances only on frames where the host evaluates modulation (at least one binding or trigger), so an idle host spends nothing; while idle the state is held, and the first frame after idle advances by at most 0.25 s (the Δt cap), so a binding added later starts from the held state, not from a jump. Binding the first envelope source therefore starts from 0 on a fresh host (MOD-015-R7).
- Q: How is acceptance tested? → A: A package step test: silence 1 s → band 2 at full for 2 s → silence 3 s at 60 fps, other bands held at fixed levels. Each profile matches its closed-form rise and fall to 1e-9; the fast envelope reaches 90 % first, then medium, then slow; other bands' envelopes are bit-identical to a run without the step; changing one profile's constants does not change the others (independence). Also 120 fps and a seeded jittery clock (MOD-015-S1 to S3).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Follow one band at three speeds (Priority: P1)

A performer drives a fast flicker from the fast envelope of the bass band and a slow swell from the slow
envelope of the same band. Both respond to the same music, each at its own pace.

**Why this priority**: This is the roadmap row and its acceptance.

**Independent Test**: Feed a step into one band and compare each profile against its documented closed form.

**Acceptance Scenarios**:

1. **Given** silence, **When** band 2 steps to full, **Then** each profile rises with its own attack constant (fast first, medium next, slow last) and matches the closed form.
2. **Given** band 2 at full, **When** it drops to silence, **Then** each profile falls with its own release constant.
3. **Given** a step in band 2, **When** the other bands are steady, **Then** their envelopes are unaffected.

### User Story 2 - Bind an envelope to a parameter or trigger (Priority: P1)

**Independent Test**: A binding from `audio.bandEnvelope.slow.0` drives a parameter along the slow envelope; a
trigger accepts the source; the ID round-trips.

**Acceptance Scenarios**:

1. **Given** a binding from a band envelope to glow intensity, **When** frames advance, **Then** the effective value follows that envelope.
2. **Given** a stored scene with a band-envelope source, **When** it is restored, **Then** the binding is restored with the same source.
3. **Given** the inspector, **When** it lists the binding, **Then** the source reads "Band 1 slow".

### Edge Cases

- A band index above the frame's band count: the source reads 0.
- A band index outside 0…127: refused as for `audio.band.<i>`.
- NaN or ±∞ band input: read as 0; outputs stay finite.
- Band count changes (another layout): every envelope restarts at 0.
- Time going backwards or standing still: no change; a gap over 0.25 s counts as 0.25 s.
- No binding or trigger at all: the bank does not advance and holds its state.
- An expression naming `audio.bandEnvelope.fast.0`: refused as an unknown name.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-015-R1**: The system MUST provide three envelopes (fast, medium, slow) for every band of the current frame, up to 128 bands.
- **MOD-015-R2**: Each profile MUST use its fixed attack and release time constants (fast 10/80 ms, medium 80/350 ms, slow 400 ms/1.6 s), one-pole as defined by MOD-005.
- **MOD-015-R3**: Each envelope MUST depend only on its own band's input and its own profile's constants.
- **MOD-015-R4**: Envelopes MUST advance only on the injected frame time (nanoseconds), with MOD-002's Δt rules (first frame 0, non-increasing 0, at most 0.25 s).
- **MOD-015-R5**: Each band envelope MUST be a bindable source with a stable ID `audio.bandEnvelope.<profile>.<band>` that parses back exactly; bindings and threshold triggers MUST accept it with the band range check of `audio.band.<i>`.
- **MOD-015-R6**: People-facing names MUST read "Band <n> <profile>" (1-based band); expressions MUST NOT accept these names.
- **MOD-015-R7**: The bank MUST be preallocated; per-frame advance and reads MUST NOT allocate; envelopes start at 0 and reset when the band count changes.
- **MOD-015-R8**: Outputs MUST be finite and within 0…1 for any input, NaN and infinities included.
- **MOD-015-R9**: Advancing over an interval of constant input in several steps MUST give the same result (1e-12) as one step.
- **MOD-015-R10**: Changed packages MUST keep building and passing on Linux.

### Key Entities

- **Envelope profile**: fast, medium or slow, with fixed attack and release time constants.
- **Band envelope source**: (band index, profile), a bindable source.
- **Envelope bank**: the per-host state of every band's three envelopes and the last frame time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-015-S1**: In the step test, each profile's value agrees with its closed form within 1e-9 at every frame, at 60 fps, 120 fps and a seeded jittery clock; 90 % crossing times order fast < medium < slow and match τ·ln 10 within one frame.
- **MOD-015-S2**: Bands without the step, and profiles whose constants are changed in a variant bank, leave every other envelope bit-identical (independence).
- **MOD-015-S3**: Splitting intervals changes no value by more than 1e-12; NaN/∞/out-of-range input keeps every output finite within 0…1.
- **MOD-015-S4**: A binding from a band envelope drives a parameter in the app along that envelope; the ID round-trips through a scene.
- **MOD-015-S5**: The ParameterGraph tests pass on the host and on Linux (CI shape), each new test in under 2 s.

## Assumptions

- The envelopes follow the ANL-002 band levels as the frame loop passes them to modulation (after ANL-003 display smoothing when it is on, as `audio.band.<i>` does today).
- No settings, no UserDefaults key, no new UI screen: the sources appear wherever binding sources are named.
- Creating routes in the UI is out of scope (MOD-012-D6); envelopes are bound through scenes and the DEBUG seed paths like other sources.
