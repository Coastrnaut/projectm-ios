# Feature Specification: SHD-007 Particle Emitter Editor

**Feature Branch**: `feature/shd-007` (spec directory `271-shd-007-particle-emitter-editor`)
**Created**: 2026-11-14
**Status**: Implemented 2026-11-14 (SHD-007-T01-T12 verified on the Mac: host, Linux shape, host GPU, iOS 27.2 simulator; device task T13 `{device}` open)
**Input**: User description: "Implement SHD-007 (Particle emitter editor) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Adjust spawn shape, rate, velocity, lifetime and collision bounds." Acceptance,
verbatim: "Ten-second seeded run matches expected spawn count and lifetime bounds." P2, size L, depends on VIS-008
(integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`SHD-007-R1…`, success criteria `SHD-007-S1…`, tasks `SHD-007-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `8fa893f8`)

| Area | Today | Gap for this row |
|---|---|---|
| Particle Fountain (VIS-008) | Onset-driven bursts (4…24 particles) from one point at the bottom centre; fixed 20° cone, speed 3…4 R/s, one life for every particle (2.5 s), gravity Low/Medium/High (`settings.particleFountain.gravity`), drag 0.8; a fixed 512-particle pool and a 32-onset queue allocated once; fixed 1/240 s steps on the injected frame clock; SplitMix64 seeded generator restored at every reset; death below the floor or beyond the sides. Goldens: Metal render tests; flash areas over 17 regions (FX-019). | No continuous spawning, no spawn shape, no velocity or lifetime ranges, no bounce; nothing to edit beyond gravity. |
| Particle Orbit (VIS-009) | Particles on orbits around the centre; its own simulation. | Orbits have no spawn shape, velocity or collision to edit, so the emitter does not apply (Clarifications). |
| Parameter metadata (SHD-003) | Metadata JSON for material shader slots. | The fountain is a native generator, not a material: no shader slots to describe. |
| Gradient and Noise editors (SHD-005, SHD-006) | Settings screens: preview at the top, a Reset button, a seed control, ACC-005 sliders; settings saved at once in one key, lenient reading. | The pattern this editor copies. |
| Authoring preview fixture (SHD-012) | Runs a material against fixture audio and a fixed 30 fps clock. | Material-specific; the emitter preview reuses its idea (a fixed frame clock, never the wall clock). |
| Seeded draws (MOD-008) | `SteppedRandom` (SplitMix64). | The fountain already has the same SplitMix64; reused as is. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option. The SHD-011 policy holds: no user-authored executable shaders, parameters only.

- Q: Which visual does the emitter configure? → A: The Particle Fountain (VIS-008). The emitter settings are an
  optional part of its configuration: absent (the default) keeps VIS-008 exactly as it is, goldens included;
  present switches the fountain to the edited emitter. The Particle Orbit is not changed: its particles are not
  spawned with a shape, velocity or collision, so the editor's controls would mean nothing there.
- Q: What does the emitter hold, and in what ranges? → A: (lengths in R, half the output's shorter side, from the
  fountain's emitter point, y up)
  - spawn shape: point, line (width), circle (diameter; uniform inside the disc) or rectangle (width × height);
    width and height 0…2 R;
  - rate: 0…240 particles per second, resolved to 0.001 per second (at most one particle per 1/240 s step);
  - initial velocity: speed range min…max in 0…8 R/s, direction −180…180° from straight up, spread 0…180°
    (half-angle, uniform within ± spread);
  - lifetime range min…max in 0.1…10 s;
  - gravity 0…10 R/s² (0 allowed for floating particles);
  - collision bounds: none, floor (the output's bottom edge) or box (half-width 0.2…3 R, height 0.5…5 R above the
    bottom edge), each with an action: bounce (restitution 0…1) or kill;
  - seed: any 64-bit value (the editor offers 0…65535 plus a deterministic "New seed").
  Every value is clamped to its range when the settings are built or decoded; non-finite values take the default;
  a min above its max is swapped into order.
- Q: How is the particle count bounded? → A: The fountain's fixed 512-particle pool never grows. A spawn that does
  not fit is counted as dropped (as VIS-008 counts burst overflow). The editor shows the steady-state estimate
  rate × mean lifetime and a note when it exceeds the pool.
- Q: How is the spawn count made exact? → A: An integer accumulator: each fixed step adds the rate in
  thousandths of a particle per second; a particle is spawned whenever the accumulator reaches 240 000 (one
  particle). After k steps at a constant rate the spawn attempts are exactly ⌊rate_milli · k / 240 000⌋, so a
  10 s run (2 400 steps) spawns ⌊rate · 10⌋ (rate in thousandths). The schedule depends only on the frame clock,
  never on how frames divide time, so 60 Hz and a jittery frame rate give identical runs. A rate change keeps the
  accumulated fraction.
- Q: How is each particle's lifetime drawn? → A: Uniformly in [min, max] from the seeded SplitMix64, in a fixed
  draw order per particle (position, direction, speed, lifetime). A particle dies at the first step where its
  age ≥ its lifetime, so its age at death lies in [lifetime, lifetime + 1/240 s). With collision "kill" or no
  bounds it can also die earlier by leaving the bounds; the lifetime test uses bounce.
- Q: What do collisions do? → A: After each step, a particle beyond a bound is either removed (kill) or put back
  on the bound with that velocity component reversed and scaled by the restitution (bounce). With bounds on, no
  live particle is ever outside them. Spawn positions are clamped into the bounds. With "none", particles fly
  freely until their lifetime ends (off-screen particles are not drawn; the lifetime caps them).
- Q: What about onset bursts and Reduce Motion while the emitter is on? → A: Onset bursts still happen (the visual
  stays audio reactive) and use the emitter's shape, velocity and lifetime. Reduce Motion keeps VIS-008's rule
  (time scale 0.7: speed × 0.7, gravity × 0.49, lifetime ÷ 0.7) and halves the rate.
- Q: Where is the editor and where are its settings stored? → A: Settings › Particle emitter, a screen next to
  the Noise editor: a "Use on Particle Fountain" switch, a live preview, Reset to defaults, the seed (stepper and
  "New seed"), then the shape, rate, velocity, lifetime, gravity and collision controls (ACC-005 sliders). One
  UserDefaults key, `settings.particleFountain.emitter`, holds JSON of the switch and the settings (absent =
  off with defaults); included in settings backups and the Settings erase like the other fountain setting;
  lenient reading (damaged data reads as defaults, values are clamped).
- Q: Do scenes store the emitter? → A: No. Scenes do not store the fountain's gravity either (the fountain is not
  a compositor layer, VIS-008-R11); the emitter follows the same rule.
- Q: How does the preview work without the wall clock? → A: The preview runs the real fountain simulation on a
  fixed 30 fps frame clock (frame n at n × 10⁹ / 30 ns, as REC-013 and SHD-012 pace frames) and draws the
  simulation's laid-out squares (the fountain's own layout code) in a small canvas. It plays only while the
  screen is shown and not under Reduce Motion (then "Step" advances one second); any settings change restarts it
  from the seed, so the same settings always show the same run.
- Q: "New seed" without a system random source? → A: SHD-006's `NoiseSeedSequence` (a per-launch counter hashed and
  reduced to 0…65535, skipping the current seed), reused as is.
- Q: Does the Gravity picker still apply? → A: Only with the emitter off. With it on the emitter's gravity is used;
  the picker's footer says so.
- Q: How does VoiceOver describe the preview? → A: As one element "Emitter preview" whose value reads the live
  particle count and the spawn count of the run ("42 particles, 120 spawned"); the sliders read their values with
  units (ACC-005).
- Q: Can the preview flash? → A: It draws the fountain's colours at their fixed alpha ≤ 0.8 (VIS-008-R7) in a
  small inline canvas, on a dark background, with no full-frame changes; it plays only while visible and never
  under Reduce Motion. The full-screen visual keeps the strobe safety envelope.
- Q: What does "jittery frame rate" mean in the acceptance test? → A: Frame gaps drawn from a fixed seed between
  5 ms and 40 ms, with the last frame at exactly 10 s after the anchor. Because the spawn schedule depends only
  on the fixed steps, the jittery run must equal the 60 Hz run particle for particle.

### Session 2026-11-18 (QA-011 device run)

- Q: SHD-007-T13 failed at "the Rate slider" on D1-D3 and lost `particleBoundsProbe` on D2; does the box leak? → A: No: outside=0 with 415-527 bounces on D1 and D3. The slider reveal used `isHittable` (false for ACC-005 slider rows) and dragged the list until the preview row, which holds the probe, left the lazy list; the test reveals by frames and scrolls back to the probe.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shape the fountain's emitter and see it at once (Priority: P1)

Someone opens Settings › Particle emitter, turns on "Use on Particle Fountain", picks a circle spawn shape,
raises the rate, narrows the spread, lengthens the lifetime and sets box collisions with bounce. The preview shows
each change immediately; the Particle Fountain visual uses the emitter; the settings survive relaunch.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: A UI test opens the editor, turns the switch on, moves the rate slider and reads the value
back; app tests cover storage, clamping and that the fountain visual receives the emitter.

**Acceptance Scenarios**:

1. **Given** the editor at defaults, **When** the rate slider is moved, **Then** its value changes and the preview
   restarts with the new rate.
2. **Given** the switch on and the Particle Fountain visual, **When** settings change, **Then** the fountain's
   configuration carries the emitter.
3. **Given** edited settings, **When** the app is relaunched, **Then** the editor shows the same values.
4. **Given** "Reset to defaults", **Then** every value returns to its default and the switch turns off.

### User Story 2 - A seeded ten-second run is exact (Priority: P1)

For a seed S, rate R and lifetime range [a, b], a 10-second run spawns exactly the expected count, every
particle's age at death lies in [a, b] (to one frame), no particle leaves enabled bounds, the pool never grows,
and the same seed reproduces the run while another seed differs, at 60 Hz and at a jittery frame rate.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: A pure simulation test (no GPU) runs the emitter for 10 s with an injected frame clock.

**Acceptance Scenarios**:

1. **Given** rate 37.5/s, **When** the run lasts 10 s at 60 Hz, **Then** 375 particles were spawned.
2. **Given** the same settings at a jittery frame rate ending at 10 s, **Then** the spawn count and every particle
   are identical to the 60 Hz run.
3. **Given** lifetime [0.8, 1.6] s and box bounce, **Then** every death happens at an age in [0.8, 1.6 + 1/60] s.
4. **Given** box bounds, **Then** after every frame each live particle is inside the box.
5. **Given** seed S twice, **Then** the runs are identical; **given** seed S + 1, **Then** they differ.

### User Story 3 - The configured emitter draws as expected (Priority: P2)

The fountain with an emitter draws the laid-out particles on the GPU; a fixed seed and time give a stable frame.

**Independent Test**: A Metal render test compares a configured emitter's frame with a golden signature and checks
that every lit pixel belongs to a laid-out particle inside the bounds.

### Edge Cases

- Rate 0: no continuous spawning (onset bursts only).
- Rate × mean lifetime above 512: the pool stays at 512; extra spawns are counted as dropped; the spawn attempt
  count is still exact.
- Lifetime min = max: every particle lives exactly that long (to one step).
- Spread 0 and speed min = max: every particle starts with the same velocity.
- Shape size 0: a line, circle or rectangle of size 0 behaves as a point.
- Damaged or out-of-range stored settings: clamped or defaults.
- Long frame gaps: VIS-008's rule (at most 1 s of steps per frame, the rest skipped) still applies.
- Reduce flashing and the strobe safety envelope apply to the fountain as before.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-007-R1**: The fountain MUST accept optional emitter settings: spawn shape and size, rate, speed range,
  direction, spread, lifetime range, gravity, collision bounds with an action, and a seed. Without them it MUST
  behave exactly as VIS-008.
- **SHD-007-R2**: Every emitter value MUST be validated and clamped to its documented range; the particle pool
  MUST stay at its fixed capacity.
- **SHD-007-R3**: Continuous spawning MUST be deterministic on the injected frame clock: after k fixed steps at a
  constant rate the spawn attempts MUST equal ⌊rate_milli · k / 240 000⌋, independent of frame timing.
- **SHD-007-R4**: Each particle's lifetime MUST be drawn from the seeded generator within [min, max]; it MUST die
  within one step after its lifetime.
- **SHD-007-R5**: With collision bounds on, no live particle MUST ever be outside them (bounce reflects and damps,
  kill removes).
- **SHD-007-R6**: The same seed and settings MUST reproduce the run exactly; a different seed MUST change it.
- **SHD-007-R7**: The app MUST offer a Particle emitter editor with a switch, a live preview on a fixed frame
  clock, Reset, a seed control and ACC-005 sliders for every value.
- **SHD-007-R8**: The editor's settings MUST persist, follow the settings backup and erase rules, and tolerate
  damaged stored data; with the switch on, the Particle Fountain visual MUST use them.
- **SHD-007-R9**: No user-authored code or shader is accepted (SHD-011): the editor sets parameters only.

### Key Entities

- **Emitter settings**: shape, shape size, rate, speed range, direction, spread, lifetime range, gravity, bounds,
  bounds action, restitution, seed.
- **Stored emitter choice**: whether the fountain uses the emitter, plus the emitter settings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-007-S1**: A 10-second seeded run spawns exactly the expected count at 60 Hz and at a jittery frame rate,
  and every age at death lies in [a, b] to one frame — the acceptance.
- **SHD-007-S2**: With bounds on, zero particles are outside them in any frame of the run; the pool capacity is
  unchanged.
- **SHD-007-S3**: Two runs with one seed are identical; two seeds differ.
- **SHD-007-S4**: A person can change any emitter value and see the preview react in under 30 seconds; the UI test
  runs in under 30 s.
- **SHD-007-S5**: Unit tests under 10 s each; package suites under one minute.

## Assumptions

- The editor applies to the Particle Fountain only; the Particle Orbit keeps its own settings.
- A look at the emitter on a physical device (frame rate and appearance with a full pool) is a `{device}` task;
  correctness is proven by pure simulation tests, the Mac's GPU and the simulator.
