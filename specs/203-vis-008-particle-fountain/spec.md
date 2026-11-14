# Feature Specification: VIS-008 Particle Fountain

**Feature Branch**: `feature/vis-008` (spec directory `203-vis-008-particle-fountain`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-008 (Particle fountain) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Spawn particles from onset events with gravity and drag." Acceptance,
verbatim: "Fixed seed and event log produce repeatable particle counts and trajectories." P1, L, depends on
ANL-004 (onsets, integrated). Mirror the native visuals VIS-006 and VIS-007; the particles go through
FX-019's flash envelope and respect ACC-012's caps and ACC-001's Reduce Motion."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-008-R1…`, success criteria `VIS-008-S1…`, tasks `VIS-008-T01…`. Requirements of
other features are cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility),
FR-072 (Reduce flashing); ACC-001 (Reduce Motion); VIS-001-R1, R12 to R16 (native visual contract,
lifecycle, fallback); VIS-003-R12 (scene capture); VIS-005-R12 (generator goldens); VIS-006 (event-driven
native visual, bus subscription); ANL-004 (onset events), ANL-016 (analysis event bus); FX-001-R10 (glow
and flash safety); FX-019-R4, R9, R11 (strobe safety envelope); ACC-003-R13 (palette); ACC-012 (sensory
safety clamp); QA-002 / QA-003 (golden images, image diff).

## Baseline: what exists today (audit of 2026-11-14, commit `7a07c74e`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 to VIS-007 in the native visual package: CPU geometry implementing the flash region model, flat triangles drawn by the shared flat-shape pass, one host with one frame loop, glow, capture and recording. | No visual simulates moving particles. |
| Onsets | ANL-004's onset detector publishes `onset(strength, threshold)` events on ANL-016's bus; the native host already holds a bus subscription for VIS-006's beat rings and drains it each frame. VIS-006 ignores onsets. | Onsets drive nothing visual yet. |
| Flash safety | FX-019's envelope over 17 areas, fed by any flat region layout; ACC-012's profile reaches the generators through the frame context. | The particles' squares feed the same model. |
| Motion | ACC-001's Reduce Motion reaches the native host (VIS-007 halves the mandala's turn). | Fewer and slower particles under Reduce Motion. |
| Choosing a visual | Settings → Visual lists one row per visual choice; native visuals show their options and Glow. | A new choice and its option. |
| Golden images | VIS-003 to VIS-007 keep generator-level goldens per platform class. | One golden of a seeded fountain. |
| Determinism | VIS-006 is a pure function of accepted births and time. | A seeded simulation that does not depend on how frames chunk time. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
conservative, local-first option. Lengths are in R, half the output's shorter side; positions are measured
from the emitter, y up.

- Q: How many particles does an onset spawn, and how are they launched? → A: The onset's excess e = clamp((strength − threshold) / 0.25, 0, 1) (non-finite reads 0) gives a burst of 4 + round(20·e) particles (4…24). Each particle draws, from a SplitMix64 generator seeded with a fixed seed (default 0x5EED0008, restored at every loop restart), a launch angle uniform within ±20° of vertical and a speed uniform in 3.0…4.0 R/s, from an emitter at the bottom centre 0.1 R above the bottom edge. Rejected: spawning from the band vector (not the row's input); system randomness (not repeatable); bursts unbounded in strength (a storm on loud material) (VIS-008-R2).
- Q: How is motion integrated so it does not depend on frame timing? → A: A fixed step of 1/240 s on the injected frame clock: step k starts at anchor + ⌊k·10⁹/240⌋ ns (the anchor is the first frame time after a loop restart); a frame advances every step that ends at or before its time (at most 240 steps per frame; a longer gap skips the rest and re-anchors). Semi-implicit Euler: v ← v + (g − k·v)·Δt, then p ← p + v·Δt, with gravity g = (0, −G) and linear drag k = 0.8 per second. An onset spawns its burst at the first step starting at or after its time, before that step is integrated. Gravity G is the one setting: Low 2.0, Medium 3.0 (default), High 4.5 R/s². Rejected: variable steps of the frame duration (trajectories would depend on the frame rate); quadratic drag (no closed form for the tests) (VIS-008-R3, R6).
- Q: What bounds the particle count, and when does a particle die? → A: A preallocated pool of 512 particles and a queue of 32 pending onsets; a burst that does not fit is truncated and onsets past the queue are dropped, both counted; a live particle is never replaced. A particle dies when its age reaches its lifetime (2.5 s), when it falls below −0.15 R (0.05 R below the bottom edge) or when |x| > 3 R (past any side of a 3:1 output). Bounds in R units keep the simulation independent of the output size. Rejected: replacing the oldest particle (a visible pop mid-flight); size-dependent bounds (the golden and the acceptance would depend on the view) (VIS-008-R4, R5).
- Q: What does Reduce Motion change? → A: Bursts are halved, rounded up (2…12), and the motion is slowed by a time scale of 0.7: launch speed × 0.7, gravity × 0.49, drag × 0.7 and lifetime ÷ 0.7, so each particle traces the same arc 0.7 times as fast. Applies to particles spawned afterwards; particles in flight keep their parameters. Rejected: stopping the fountain (the brief asks for fewer and slower); only fewer particles (motion speed is what Reduce Motion is about) (VIS-008-R9).
- Q: How is a particle drawn, and which settings are offered? → A: A flat square of side max(0.025 R, 2 px) centred on the particle, palette colour (spawn sequence mod 16) of 16 (ACC-003-R13), alpha 0.8 × min(1, age / 0.05 s) × (1 − age / lifetime), premultiplied over opaque black; the brightest alpha 0.8 is ACC-012's cap shared with VIS-006 and VIS-007. One setting, Gravity (Low/Medium/High). Rejected: additive blending (overlaps could reach full white); sliders for drag, speed or count (more keys and more motion risk) (VIS-008-R7, R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose the particle fountain (Priority: P1)

A user playing music opens Settings, chooses the visual "Particle Fountain" and sees bursts of coloured
particles shoot up from the bottom of the screen on each musical onset (a drum hit, a plucked note), arc
under gravity, slow down through drag and fade out. Stronger onsets throw more particles. The user picks
how strong gravity is. The choice is remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Particle Fountain in Settings, check that Gravity is offered
and Bars is not, close Settings and check that the visual is shown and its value names the gravity.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Particle Fountain", **Then** it replaces the current visual without restarting the audio source.
2. **Given** Particle Fountain chosen, **When** Settings is open, **Then** Gravity (Medium selected by default) and the Glow controls are offered and Bars is not.
3. **Given** a gravity chosen, **When** the app is relaunched, **Then** it is restored.

---

### User Story 2 - Seeded and repeatable (Priority: P1)

Whoever checks the visual replays the same seed and the same onset event log and gets the same number of
particles at every moment and the same trajectories, however the frames divide time.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Replay a fixed seed and a fixed log of onset events (times and strengths) twice at 60
frames per second and once with irregular frame intervals; compare the live particle counts and every
particle's position at shared sample times.

**Acceptance Scenarios**:

1. **Given** a fixed seed and event log, **When** replayed twice with the same frames, **Then** live counts, spawned counts and every particle's position and velocity are bit-identical at every frame.
2. **Given** the same seed and log, **When** replayed with different frame intervals (60 Hz, 30 Hz, irregular), **Then** at shared sample times the live counts are equal and every position matches within 1e-9.
3. **Given** a different seed, **When** replayed, **Then** the counts are the same but the trajectories differ.
4. **Given** a seeded fountain rendered offscreen at a fixed time, **When** compared with the committed golden, **Then** it passes QA-002's rule.

---

### User Story 3 - Bounded, safe motion and light (Priority: P1)

Particles react to every onset, so the picture must not become a flashing storm or grow without limit.
However dense the onsets, the particle count stays bounded, the picture stays within the strobe envelope,
and with Reduce Motion on there are fewer, slower particles.

**Independent Test**: Feed onsets at the detector's highest rate at full strength for several seconds of
injected time and check the count bound and the per-area transition budget; compare spawn counts and launch
speeds with Reduce Motion off and on.

**Acceptance Scenarios**:

1. **Given** full-strength onsets at the highest rate, **When** simulated for 10 s, **Then** the live count never exceeds the pool's capacity and nothing is allocated per frame.
2. **Given** bursts of onsets alternating with silence at 60 Hz, **When** drawn with Reduce flashing on and off, with and without the strongest glow, **Then** no area has more transitions per window than the budget.
3. **Given** Reduce Motion on, **When** the same onset is replayed, **Then** at most half as many particles spawn and each launches at 0.7 times the speed.

### Edge Cases

- Silence (no onsets): no particles; a black screen.
- Onset strength not finite or below its threshold: the smallest burst; above 1 read as 1.
- More pending onsets than the queue holds between two frames: the excess is dropped and counted.
- The pool is full: new particles are dropped and counted; live particles are never replaced mid-flight.
- Output size 0: nothing drawn; the simulation still advances; tiny sizes give valid geometry.
- Pause and resume: the loop restart clears the particles and pending onsets and reseeds (no burst of stale particles); the envelope history is kept (FX-019-R11).
- A long frame gap (over 1 s of injected time): the simulation advances at most 1 s and skips the rest of the gap.
- Time going backwards: nothing advances; no crash.
- Gravity changed while running: applies from the next substep without rebuilding the generator; particles keep their positions.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-008-R1**: The particle fountain MUST be a native visual under VIS-001's generator contract and the shared host contract, drawn by the shared flat-triangle pass, driven by ANL-004's onset events from ANL-016's bus (the band vector is unused).
- **VIS-008-R2**: Spawning: each onset event spawns a burst of 4 + round(20·e) particles, e = clamp((strength − threshold) / 0.25, 0, 1) (non-finite reads 0); each particle starts at the emitter (bottom centre, 0.1 R above the bottom edge) with a launch angle uniform within ±20° of vertical and a speed uniform in 3.0…4.0 R/s, drawn from a seeded SplitMix64 generator (default seed 0x5EED0008, restored at every loop restart).
- **VIS-008-R3**: Motion: particles move under constant downward gravity G (Low 2.0, Medium 3.0, High 4.5 R/s²) and linear drag 0.8 per second, integrated by semi-implicit Euler with a fixed step of 1/240 s on the injected frame clock (step k starts at anchor + ⌊k·10⁹/240⌋ ns; at most 240 steps per frame, a longer gap is skipped), so a trajectory does not depend on the frame rate or on how frames divide time. An onset spawns at the first step starting at or after its time.
- **VIS-008-R4**: Lifetime: a particle dies when its age reaches its lifetime (2.5 s), when it falls below −0.15 R or when |x| > 3 R; dead particles free their slot.
- **VIS-008-R5**: Bounds: a pool of 512 particles and a queue of 32 pending onsets; a burst that does not fit is truncated and excess onsets are dropped, both counted; a live particle is never replaced; nothing is allocated per frame (Constitution VII).
- **VIS-008-R6**: Determinism: the particle state at any time is a pure function of the seed, the configuration, the onset event log (times and strengths) and the loop restarts; no wall clock is read and no system randomness is used.
- **VIS-008-R7**: Drawing: each particle is a flat square of side max(0.025 R, 2 px) in palette colour (spawn sequence mod 16) of 16 (ACC-003-R13), alpha 0.8 × min(1, age / 0.05 s) × (1 − age / lifetime) (at most 0.8, below full white: ACC-012), premultiplied over an opaque black background.
- **VIS-008-R8**: Flash safety: every frame passes FX-019's envelope with the 17-area model built from the particles' squares (FX-019-R4, R9, FX-001-R10), as the other native visuals; overlapping particles are counted twice (an overestimate).
- **VIS-008-R9**: Reduce Motion (ACC-001): bursts are halved (rounded up) and the motion slowed by a time scale of 0.7 (launch speed × 0.7, gravity × 0.49, drag × 0.7, lifetime ÷ 0.7), so each particle traces the same arc 0.7 times as fast; the change applies to particles spawned afterwards.
- **VIS-008-R10**: The app MUST offer "Particle Fountain" as a Visual choice (stored `particleFountain` under `settings.visual`) with Gravity (`settings.particleFountain.gravity`: `low`/`medium`/`high`, anything else → medium). Glow shared, Bars hidden. Switching does not restart the audio source; lifecycle and fallback are VIS-001-R12 to R16's. The key is an FR-065 user setting, in the FILE-005 backup policy and the device privacy allow list, and is reset by `-uitestResetNotice`.
- **VIS-008-R11**: Scene capture records the particle fountain as no native layer (as VIS-003-R12).
- **VIS-008-R12**: Accessibility (FR-070): one element labeled "Particle Fountain visualization", identifier `particleFountain`, value naming the gravity and glow (for example "Medium gravity, Glow off"); the new control has a stable identifier.
- **VIS-008-R13**: A golden image of a seeded fountain MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator), with the record policy and integrity check.
- **VIS-008-R14**: The other native visuals MUST NOT change: their tests pass unchanged.

### Key Entities

- **Fountain configuration**: gravity, drag, lifetime, particle size, seed, Reduce Motion, palette, background.
- **Particle**: position, velocity, age, lifetime, spawn sequence; lives in a fixed pool slot.
- **Onset event log**: ordered pairs of time and strength.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-008-S1**: A fixed seed and event log replayed twice give identical live and spawned counts and identical positions at every frame.
- **VIS-008-S2**: The same seed and log replayed with 60 Hz, 30 Hz and irregular frame intervals give equal counts and positions within 1e-9 at shared sample times.
- **VIS-008-S3**: A burst's size grows monotonically with onset strength and stays within 4…24; the live count never exceeds 512.
- **VIS-008-S4**: With no drag a particle's path matches the closed-form ballistic path of the fixed step within 1e-9; with drag its speed never increases while it rises.
- **VIS-008-S5**: Onset bursts alternating with silence at 60 Hz stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow.
- **VIS-008-S6**: With Reduce Motion on, a burst has half the particles (rounded up) and each particle's path is the same arc traced 0.7 times as fast (positions within 1e-9 at matching path times).
- **VIS-008-S7**: The seeded picture passes its golden on the macOS host and the iOS Simulator.
- **VIS-008-S8**: One UI test of at most 30 s chooses Particle Fountain with the source started once; the setting key persists (unit test).
- **VIS-008-S9**: Every existing native visual and golden test passes; the package builds in the Linux shape.

## Assumptions

- Onsets come from the native host's own analysis pipeline (ANL-004 on ANL-016's bus), which already runs while a native visual is shown.
- Simulator results are not device evidence; the look and frame time on devices are `{device}` work.
- No new stored data besides the one setting key; no network; the privacy manifest does not change.
- projectM stays the default visual.
