# Feature Specification: VIS-009 Particle Orbit

**Feature Branch**: `feature/vis-009` (spec directory `211-vis-009-particle-orbit`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-009 (Particle orbit) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Orbit particles around a beat-reactive center with controllable radius."
Acceptance, verbatim: "Radius responds to mapped bass while frame rate stays within budget." P1, depends on
ANL-007 (kick/bass, integrated). Mirror VIS-008 (particle fountain); keep the projectM backend isolated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-009-R1…`, success criteria `VIS-009-S1…`, tasks `VIS-009-T01…`. Other features are
cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion),
ACC-003-R13 (palette), ACC-012 (sensory safety clamp); VIS-001-R12 to R16 (native visual contract,
lifecycle, fallback); VIS-003-R12 (scene capture); VIS-006 (beat trigger, bus subscription); VIS-008 (seeded
fixed-step particles); ANL-005 (beats), ANL-007 (kick envelope and kick transients), ANL-016 (analysis bus);
MOD-001 (typed parameter registry), MOD-002 (audio feature bindings), MOD-011 (mix order), MOD-015 (band
envelopes); FX-019 (strobe safety envelope); PERF-001 / PERF-007 (frame telemetry), PERF-003 (effect
quality budget); QA-002 (golden images).

## Baseline: what exists today (audit of 2026-11-14, commit `5995f52e`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 to VIS-008: CPU geometry, flat triangles drawn by the shared flat-shape pass, one host and frame loop, glow, capture. VIS-008 has a seeded fixed-step particle simulation with a preallocated pool. | No visual orbits particles around a centre. |
| Bass | ANL-007's kick envelope (40–150 Hz transient, 1 on a kick decaying to 0) reaches the native host every frame and feeds MOD-002's Kick source; MOD-015's band envelopes are bindable sources. | Nothing visual follows the bass directly. |
| Beats | VIS-006's `BeatRingTrigger` turns confident ANL-005 beats (kick fallback) into events on the bus subscription. | No centre that pulses on beats. |
| Bindable parameters | MOD-001's visual catalog registers the spectra and glow; MOD-002 bindings can only drive the glow in the native host. | No visual geometry parameter is bindable. |
| Frame budget | PERF-001/007 measure stage times and drops on device; PERF-003 lowers the glow under budget pressure. | No particle visual has a documented per-frame work bound. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option. Lengths are in R, half the output's shorter side; positions are measured from the output's
centre, y up.

- Q: How are the particles placed and moved? → A: A fixed pool of 256 slots, 160 drawn by default (16…256). Slot k takes three draws, in slot order, from a SplitMix64 generator seeded with 0x5EED0009 (restored at every loop restart): a phase uniform in [0, 2π), an angular speed 0.8 × (0.75 + 0.5·u) rad/s (counter-clockwise) and a radial offset 1 + 0.1·(2u − 1). Particle k sits at the current radius × its offset, at its phase; phases advance on VIS-008's fixed 1/240 s step on the injected frame clock (same anchor, at most 240 steps per frame, a longer gap skipped). Rejected: free-flying particles with orbital physics (unbounded drift, no closed form); per-frame random jitter (not repeatable) (VIS-009-R2).
- Q: How does the radius follow the bass, and what bounds it? → A: Target = clamp(base × (1 + 0.4 × b), 0.15, 0.85), b = bass clamped to 0…1 (non-finite reads 0). Each fixed step moves the radius toward the target by a one-pole step with τ = 0.06 s, limited to 3 R/s × Δt; the target given at a frame applies to that frame's steps. With the largest offset the ring stays within 0.935 R, inside the output. Rejected: drawing the bass value directly (jumps on every kick, a flashing risk); an unbounded depth (the ring would leave the screen) (VIS-009-R3).
- Q: What is "mapped bass", and how is the radius bindable? → A: A new permanent MOD-001 parameter `visual.particleOrbit.radius` ("Radius (of half the shorter side)", group "Particle Orbit", 0.2…0.8, default 0.5, step 0.01, continuous, modulatable by default). Its manual value is the Radius setting: Small 0.35, Medium 0.5 (default), Large 0.65. Unbound, b is ANL-007's kick envelope (the built-in default mapping). With any MOD-002 binding on the parameter, the base is the modulator's value (MOD-011 order, kept in range) and b = 0, so bass is never counted twice. MIDI and OSC routes are not added (out of scope). Rejected: installing a default binding into the scene's binding list (it would be captured into every scene and shown as a user route); a separate bass-depth setting (more keys, little value) (VIS-009-R4).
- Q: What does the beat-reactive centre do, and what changes under Reduce Motion? → A: VIS-006's `BeatRingTrigger` (confident ANL-005 beats, the ANL-007 kick as fallback) queues a beat (queue of 16, excess dropped and counted); the pulse p is set to 1 at the first step starting at or after it and decays as exp(−t / 0.2 s). The centre is a square of side 0.12 R × (1 + A·p), A = 0.5, alpha 0.7. Reduce Motion (ACC-001, applied at once): angular speeds × 0.5, A = 0.2, radius τ = 0.15 s and rate 1.5 R/s. Rejected: moving the centre on beats (whole-picture motion, a Reduce Motion concern); stopping the orbit (VIS-009-R5, R9).
- Q: How are drawing and the frame budget made checkable without wall-clock tests? → A: Particles are flat squares of side max(0.022 R, 2 px), palette colour (k mod 16) of 16, alpha 0.75 (below ACC-012's 0.8). The budget is a fixed work bound: at 60 frames per second each frame runs exactly 4 steps over at most 256 particles (≤ 1,024 particle steps) and tessellates at most 257 squares (≤ 1,542 vertices), counted by the simulation and layout and asserted by a test over 600 frames with storage addresses unchanged; an XCTest `measure` baseline is reported, never asserted. Frame rate on D1 is a `{device}` task read from the PERF-001/007 overlay. One setting, Radius (Small/Medium/Large). Rejected: a wall-clock assertion (flaky); a particle-count slider (more keys, more GPU risk) (VIS-009-R6, R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bass-driven orbit (Priority: P1)

A user playing music chooses "Particle Orbit" and sees a ring of coloured particles circling a glowing centre.
When the bass (the kick drum) hits, the ring swells outward and eases back; on each beat the centre pulses.
The user picks how wide the orbit is.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: Replay a synthetic bass timeline into the visual and check that the drawn ring radius
follows the mapped value, rises with stronger bass and never leaves its bounds.

**Acceptance Scenarios**:

1. **Given** a steady bass level, **When** the orbit settles, **Then** the drawn radius equals the mapped radius within a small tolerance.
2. **Given** two bass levels, **When** each settles, **Then** the stronger bass gives the larger radius (monotonic).
3. **Given** any bass input (above 1, negative, not a number), **When** drawn, **Then** the radius stays within its documented bounds and changes no faster than its rate limit.
4. **Given** the user binds an audio feature (for example a bass band envelope) to the orbit radius parameter, **When** the feature moves, **Then** the radius follows the binding instead of the built-in kick response.

---

### User Story 2 - Within the frame budget (Priority: P1)

Whoever checks performance confirms that the largest orbit's per-frame simulation and geometry work is
bounded and allocation-free, so the frame rate stays within budget.

**Independent Test**: Run the maximum particle count for many frames and count the work per frame and the
storage addresses; render it on the GPU; record a baseline metric without asserting on wall time.

**Acceptance Scenarios**:

1. **Given** the maximum particle count at 60 frames per second, **When** simulated and laid out, **Then** each frame does at most the documented number of particle steps and vertices, and nothing is allocated.
2. **Given** a seeded orbit at a fixed time, **When** rendered offscreen, **Then** it matches the committed golden image (macOS host and iOS Simulator).
3. **Given** a physical device, **When** the orbit runs with music, **Then** the PERF-001/007 performance overlay shows the display's frame rate held, with no more dropped frames than the Mandala under the same music (`{device}`, VIS-009-T10).

---

### User Story 3 - Choose and control it, safely (Priority: P1)

The user chooses Particle Orbit in Settings, sets the Radius, and it is remembered. With Reduce Motion the
orbit turns more slowly and the centre pulses gently; the strobe safety envelope bounds every frame.

**Independent Test**: In the simulator, choose Particle Orbit, check that Radius is offered and Bars is not,
change it, close Settings and check the visual's value.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Particle Orbit, **Then** it replaces the visual without restarting the audio source.
2. **Given** a radius chosen, **When** the app is relaunched, **Then** it is restored.
3. **Given** Reduce Motion on, **When** the orbit runs, **Then** it turns at half speed and the centre's beat pulse is smaller.
4. **Given** beats alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.

### Edge Cases

- Silence: the ring sits at the base radius and keeps turning; the centre is still.
- Bass not finite, negative or above 1: read as 0 or clamped to 1.
- Output size 0: nothing drawn; the simulation still advances.
- Pause and resume: the loop restart reseeds the particles, resets the radius to the base and clears the pulse and pending beats.
- A long frame gap or time going backwards: as VIS-008 (at most 1 s advanced; nothing on backwards time).
- Radius or Reduce Motion changed while running: applies from the next frame without rebuilding the visual; the radius eases to the new value; phases are kept (no jump).
- More beats between two frames than the queue holds (16): the excess is dropped and counted.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-009-R1**: The particle orbit MUST be a native visual under VIS-001's generator contract and the shared host, drawn by the shared flat-triangle pass; the projectM backend is untouched.
- **VIS-009-R2**: Particles: a fixed set of particles, each with a seeded phase, angular speed and radial offset, circling the output's centre; deterministic given the seed, the configuration and the per-frame feature timeline (target radius, beats).
- **VIS-009-R3**: Radius: the drawn radius follows a target radius = base × (1 + depth × bass), bounded to a documented range, approached smoothly with a bounded rate on a fixed step independent of the frame rate.
- **VIS-009-R4**: Mapped bass: the base radius is a user setting and a registered, bindable visual parameter. Unbound, bass is ANL-007's kick envelope (the default mapping); when the parameter has a binding, the binding's value is the base and the built-in kick response is off, so bass never counts twice.
- **VIS-009-R5**: Beat-reactive centre: confident beats (kick fallback, VIS-006's trigger) make the centre pulse larger and decay; the pulse is bounded.
- **VIS-009-R6**: Bounds and work: at most 256 particles (160 by default), preallocated storage, no allocation per frame, and the per-frame work bound of Clarifications (≤ 1,024 particle steps and ≤ 1,542 vertices per 60 Hz frame).
- **VIS-009-R7**: Drawing: flat squares in palette colours (ACC-003-R13) at most 0.8 alpha (ACC-012), premultiplied over opaque black; the centre is a square of the same model.
- **VIS-009-R8**: Flash safety: every frame passes FX-019's envelope with the squares as regions, as the other native visuals.
- **VIS-009-R9**: Reduce Motion (ACC-001): half the angular speed, a smaller centre pulse and a slower radius response.
- **VIS-009-R10**: The app MUST offer "Particle Orbit" as a Visual choice (stored `particleOrbit` under `settings.visual`) with Radius (`settings.particleOrbit.radius`: `small`/`medium`/`large`, anything else → medium). Glow shared, Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy and the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-009-R11**: Scene capture records the particle orbit as no native layer (as VIS-003-R12).
- **VIS-009-R12**: Accessibility (FR-070): one element labeled "Particle Orbit visualization", identifier `particleOrbit`, value naming the radius and glow ("Medium radius, Glow off"); the new control has a stable identifier.
- **VIS-009-R13**: A golden image of a seeded orbit MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-009-R14**: The other native visuals and catalog consumers MUST NOT change behaviour: their tests pass (catalog lists updated for the one new parameter).

### Key Entities

- **Orbit configuration**: particle count, base radius, bass depth, angular speed, particle size, seed, Reduce Motion, palette, background.
- **Orbit particle**: phase, angular speed, radial offset, palette index; lives in a fixed slot.
- **Feature timeline**: per frame, the bass value (or bound radius) and the beats since the previous frame.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-009-S1**: For a synthetic bass timeline, the settled drawn radius matches the mapped radius within 1 % of R; higher bass never gives a smaller settled radius; the radius never leaves its bounds or exceeds its rate limit.
- **VIS-009-S2**: With a binding on the radius parameter, the drawn radius follows the binding's mapped value within 1 % of R.
- **VIS-009-S3**: At the maximum particle count and 60 frames per second, each frame runs at most 4 fixed steps of 256 particles and emits at most 1,542 vertices, with storage addresses unchanged over 600 frames.
- **VIS-009-S4**: Two replays with the same seed and timeline are bit-identical; a different seed differs.
- **VIS-009-S5**: Beats alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-009-S6**: The seeded picture passes its golden on the macOS host and the iOS Simulator.
- **VIS-009-S7**: One UI test of at most 30 s chooses Particle Orbit with the source started once; the setting persists (unit test).
- **VIS-009-S8**: Every existing native visual, catalog and golden test passes; the package builds in the Linux shape.

## Assumptions

- Bass and beats come from the native host's own analysis pipeline (ANL-007, ANL-005 on ANL-016's bus).
- Simulator results are not device evidence; frame rate on D1 is `{device}` work.
- One new setting key, one new catalog parameter ID (permanent); no network; the privacy manifest does not change.
- projectM stays the default visual.
