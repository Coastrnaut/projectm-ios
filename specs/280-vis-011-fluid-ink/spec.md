# Feature Specification: VIS-011 Fluid Ink

**Feature Branch**: `feature/vis-011` (spec directory `280-vis-011-fluid-ink`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-011 (Fluid ink) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior,
verbatim: "Simulate advection of colored dye from audio impulses." Acceptance, verbatim: "Fixed-step simulation remains
stable after repeated strong impulses." P2, XL, depends on ANL-016 (analysis event bus, integrated). Keep the projectM
backend isolated; follow the shader policy."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-011-R1…`, success criteria `VIS-011-S1…`, tasks `VIS-011-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-012 (brightness below full
white); ANL-004 (onsets), ANL-016 (analysis event bus); VIS-008 (particle fountain, the onset path the host already
drains); VIS-010 and VIS-020 (fixed-allocation textures); VIS-013 to VIS-015 and VIS-020 (modes of the noise field
generator, reviewed compile site ADR-0066); FX-019 (strobe safety envelope); PERF-009 (native pipeline archive);
SHD-011 (reviewed Metal compile sites); QA-002 (golden images).

## Baseline: what exists today (audit of 2026-11-14, commit `142b6063`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Onsets (ANL-004 over ANL-016) | The native host holds a bus subscription while the particle fountain, orbit or beat rings are shown and drains it every frame (`nextEvent`, no allocation); `ParticleFountainTrigger.onset` extracts an onset's strength and threshold. | No visual turns onsets into fluid motion. |
| Fixed-step simulations | VIS-008's fountain steps a seeded CPU simulation at fixed 1/240 s steps from an anchor in exact integer nanoseconds, skipping the rest of a stalled gap. | Nothing simulates a fluid. |
| Noise field generator (VIS-013/014/015/020) | One generator, a fragment entry point per mode, pipelines built lazily through PERF-009's archive in the reviewed compile site (ADR-0066); VIS-020 keeps a fixed history texture made once. | No grid simulation, no render-target ping-pong. |
| Feedback textures (VIS-010) | Two fixed `rgba16Float` textures made on first use, never recreated; tests assert identity and `allocatedSize`. | The pattern to copy for the fluid's fields. |
| Strobe safety (FX-019) | 17-area envelope; VIS-013's 64-sample estimate (`NoiseFieldFlashAreas`). | No estimate for advected dye. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option. Further answers are recorded by `/speckit-clarify` below.

- Q: Where does the fluid live? → A: A fifth mode of the noise field generator ("Fluid Ink"), beside plain, kaleidoscope, tunnel and waterfall: its shader functions are module constants appended to the generator's reviewed source (ADR-0066 site, part of PERF-009's archive key), its pipelines are built lazily from that library. No new compile site, no compute pipeline, no ADR. Rejected: a new generator class (a second compile site); compute kernels (fragment passes into render targets do the same work and stay inside the reviewed site's render-pipeline path) (VIS-011-R1, R9).
- Q: Which solver? → A: Stable fluids on a fixed 128 × 128 grid over the unit square: per step, impulses (Gaussian velocity and dye splats), semi-Lagrangian advection of velocity with dissipation, divergence, exactly 20 Jacobi pressure iterations starting from zero, gradient subtraction, then semi-Lagrangian advection of the dye with a fade. The same grid on every device (it costs about 0.8 MiB and a few hundred microseconds of GPU time; a smaller grid on compact devices would change the look and the goldens per device class). Rejected: a warm-started pressure (state that carries between steps), vorticity confinement (adds energy) (VIS-011-R3, R4).
- Q: How is time stepped? → A: A fixed step of 1/60 s on the frame clock, from an anchor in exact integer nanoseconds as VIS-008's fountain; each frame runs every step that ends by the frame's time, at most 4 (the spiral-of-death guard); a longer stall skips the rest of the gap (counted). So 30 fps and 120 fps frame clocks run the same steps at shared times (VIS-011-R5).
(Further decisions: see the session continued by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ink that moves with sudden sounds (Priority: P1)

A user chooses "Fluid Ink". Each sudden new sound (an onset) puffs a blob of coloured ink into dark water and pushes
it; the ink swirls, drifts and slowly fades. Stronger onsets push harder and give more ink.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: Drive the visual with a scripted series of impulses on an injected clock and compare with a golden image.

**Acceptance Scenarios**:

1. **Given** silence, **When** an onset arrives, **Then** ink appears at a seeded position and is carried by the flow.
2. **Given** the same seed and impulse timeline, **When** rendered twice, **Then** the frames are identical.
3. **Given** no onsets, **When** time passes, **Then** the ink fades and the flow comes to rest.

---

### User Story 2 - Stable under a barrage (Priority: P1)

However loud and dense the music, the simulation never blows up: no exploding colours, no frozen or corrupt picture.

**Why this priority**: It is the roadmap row's acceptance.

**Independent Test**: Apply a maximum-strength impulse every frame for 60 simulated seconds on a reference solver and on the GPU.

**Acceptance Scenarios**:

1. **Given** a maximum-strength impulse every frame for 60 s, **When** checked, **Then** every value stays finite, speed and ink stay within their caps, and the total kinetic energy stays bounded (no growth in the last 10 s over the 10 s before).
2. **Given** frame clocks of 30 and 120 frames per second, **When** the same impulses arrive, **Then** the simulation state at shared times is identical.
3. **Given** a non-finite value somehow reaches a field, **When** detected, **Then** the field is reset to rest and drawing continues.

---

### User Story 3 - Constant memory and safe light (Priority: P1)

**Acceptance Scenarios**:

1. **Given** minutes of frames, resizes and mode switches, **When** checked, **Then** the fluid's textures keep their count, identities and allocated size after the first fluid frame.
2. **Given** ink appearing after silence, **When** the strobe safety envelope measures the frame, **Then** it sees an upper bound of the ink's light and its gain scales the picture; no value exceeds 0.8 (ACC-012).
3. **Given** Reduce Motion, **When** onsets arrive, **Then** the flow is slower and fewer impulses are accepted.

---

### User Story 4 - Choose it (Priority: P2)

**Acceptance Scenarios**:

1. **Given** Settings, **When** the user picks "Fluid Ink" as the visual, **Then** it is shown instead of projectM, stored across launches, with an accessibility value describing it.

### Edge Cases

- Output size 0: nothing drawn; the simulation is kept.
- Output size changes: the field is independent of the output (no reset, no reallocation); it is drawn stretched to the new size.
- Loop restart and entering the mode from another noise-field mode: the field starts at rest and empty (storage kept).
- More impulses than a step accepts: the excess is dropped and counted; a full queue refuses new impulses (counted).
- Non-finite or negative onset strengths: ignored.
- A frame clock that goes backwards: nothing runs.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-011-R1**: Fluid Ink MUST be a mode of the VIS-013 noise field generator, switchable in place with the other modes; projectM is untouched.
- **VIS-011-R2**: Impulses come from ANL-004 onsets on the ANL-016 bus, drained by the host each frame and stamped with the frame's time; each onset's strength maps to an impulse strength in a fixed range; invalid ones are ignored.
- **VIS-011-R3**: The simulation runs on a fixed grid independent of the output size, with a fixed number of pressure iterations per step.
- **VIS-011-R4**: Each step applies, in order: impulses, velocity advection with dissipation, pressure projection, dye advection with fade; every stored value is finite and clamped (speed and dye caps) after every pass.
- **VIS-011-R5**: A fixed step on the frame clock with a bounded number of steps per frame; equal step counts at shared times for any frame rate.
- **VIS-011-R6**: Impulse strength is clamped; at most a fixed number of impulses and a fixed total strength per step; the queue has fixed capacity.
- **VIS-011-R7**: A non-finite value detected in a field resets the field to rest (counted); the reference solver and the GPU path both guard.
- **VIS-011-R8**: Storage: the fluid's textures are created on the first fluid frame and never recreated, resized or freed while the generator lives; nothing allocates per frame.
- **VIS-011-R9**: No new Metal compile site; the shader text is part of a reviewed site's source and of PERF-009's archive key.
- **VIS-011-R10**: Flash safety: the FX-019 envelope MUST see an upper bound of the dye's light; its gain scales the drawn dye; drawn values never exceed 0.8.
- **VIS-011-R11**: Reduce Motion: slower flow (lower impulse speed and speed cap) and fewer impulses.
- **VIS-011-R12**: The app offers "Fluid Ink" as a visual choice (no new setting key), with accessibility identifier and value (FR-070); scenes record it as no layer.
- **VIS-011-R13**: A golden image of a scripted impulse timeline MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).

### Key Entities

- **Impulse**: frame time, strength (0.4…1), seeded position, direction and colour.
- **Fluid state**: velocity, pressure, divergence and dye fields on the fixed grid; step index and anchor.
- **Field health**: max speed, max dye, kinetic energy, non-finite flag (reference solver and GPU readback).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-011-S1**: 60 simulated seconds with a maximum-strength impulse every frame: all values finite, max speed ≤ cap, max dye ≤ 0.8, kinetic energy bounded and not growing — on the reference solver and on the GPU (readback).
- **VIS-011-S2**: 30 and 120 frames per second give identical states at shared times (reference solver bit-identical; GPU readback identical).
- **VIS-011-S3**: Texture count, identities and allocated size constant over a long fixture with resizes and mode switches.
- **VIS-011-S4**: Goldens pass on the macOS host and the iOS Simulator; existing noise field, kaleidoscope, tunnel and waterfall goldens unchanged.
- **VIS-011-S5**: Flash tests: the envelope's levels bound the drawn dye's light; Reduce flashing's budget holds under bursts after silence.
- **VIS-011-S6**: One UI test of at most 30 s chooses Fluid Ink; the new package tests take about 5 s in total on the host.

## Assumptions

- Device look and frame rate on D1 are `{device}` work; simulator results are not device evidence.
- Fluid Ink is not a scene layer kind (as VIS-013 to VIS-015, VIS-020).
- No network; the privacy manifest does not change.
