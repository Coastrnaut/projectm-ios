# Feature Specification: VIS-006 Beat Pulse Rings

**Feature Branch**: `feature/vis-006` (spec directory `186-vis-006-beat-rings`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-006 (Beat pulse rings) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Emit expanding rings from beat events with decay." Acceptance, verbatim:
"Four synthetic beats create exactly four independently timed rings." P1, S, depends on ANL-005
(integrated). Mirror the native visuals VIS-003, VIS-004 and VIS-005; rings go through FX-019's flash
envelope and respect ACC-012's caps."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-006-R1…`, success criteria `VIS-006-S1…`, tasks `VIS-006-T01…`. Requirements of
other features are cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility),
FR-072 (Reduce flashing); VIS-001-R1, R12 to R16 (native visual contract, lifecycle, fallback);
VIS-003-R12 (scene capture); VIS-005-R12 (generator goldens); ANL-005 (tempo and beat events), ANL-007
(kick transients), ANL-016 (analysis event bus); FX-001-R10 (glow and flash safety); FX-019-R4, R9, R11
(strobe safety envelope); ACC-003-R13 (palette); ACC-012 (sensory safety clamp); QA-002 / QA-003
(golden images, image diff).

## Baseline: what exists today (audit of 2026-11-14, commit `11cf8cd0`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 to VIS-005 in `Packages/VisualGenerators`: CPU geometry implementing the flash region model, flat triangles drawn by the shared flat-shape pass, one host with one frame loop, glow, capture and recording. | No visual reacts to discrete beat events; every one draws a continuous signal. |
| Beat events | ANL-016's analysis bus publishes ANL-005 `beat` events (tempo, period, confidence) and ANL-007 `kick` transients on every subscription of the native host's analyzer; the host reads only frames today (kick envelope, centroid…). | A per-frame, allocation-free drain of events for the rings. |
| Flash safety | FX-019's envelope over 17 areas, fed by any flat region layout; ACC-012's profile reaches the generators through the frame context. | Rings feed the same model. |
| Choosing a visual | Settings → Visual lists one row per visual choice; native visuals show their options and Glow. | A new choice and its option. |
| Golden images | VIS-003 to VIS-005 keep generator-level goldens per platform class. | One golden of four rings. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the
conservative, local-first option.

- Q: Which events emit rings? → A: ANL-005 beats with confidence ≥ 0.5 (`AdaptiveBeatTracker.highConfidence`); ANL-007 kick transients only while no confident beat arrived in the previous 2 s (a song's start, rubato, beatless passages). Onsets and the mid and high transients never emit. Rejected: every onset (far denser than beats, a flash risk and visually noisy); beats only (no rings until the tracker locks, several seconds into a song); beats and kicks together (double rings on most beats) (VIS-006-R2).
- Q: Which time is a ring's birth time? → A: The display-link target time of the frame on which the host drains the event from its bus subscription. The bus's own clock is a different monotonic base; stamping on the frame clock keeps the model a pure function of the frame clock (the latency is at most one frame plus the analysis hop, ≈ 30 ms). Rejected: converting the event's sample position into display time (two clocks to align for no visible gain) (VIS-006-R6).
- Q: Ring curves? → A: Radius eased out, r(a) = r₀ + (r₁ − r₀)·(1 − (1 − p)²) with p = a/L, r₀ = 0.05, r₁ = 0.95 of half the shorter side (rings stay inside the picture); brightness α = 0.8 · min(1, a/0.05 s) · (1 − p)². The 50 ms attack turns each birth into a ramp instead of a step, and the 0.8 peak keeps rings below full white (ACC-012's brightness cap). Rejected: linear growth (reads mechanical); full-white peaks (a brighter step per beat) (VIS-006-R3).
- Q: Limit, rate cap and Reduce flashing? → A: At most 16 live rings, the oldest replaced when full. A minimum interval between accepted rings of 1/6 s (≤ 6 per second, above any musical beat rate) and, while the frame's envelope limits rises (Reduce flashing or a stricter ACC-012 profile), 1/3 s (≤ 3 per second, about one ring per beat up to 180 BPM). Too-early emissions are dropped, never queued, so no backlog follows a burst. FX-019's envelope still limits every frame on top of this. Rejected: fainter rings instead of a rate cap (a faint ring per frame at 60 Hz is still a flicker pattern; the cap bounds the pattern's frequency itself) (VIS-006-R4, R5).
- Q: Which settings? → A: One segmented choice, Ring life: Short 1.0 s, Medium 1.5 s (default), Long 2.5 s, stored as a string so a bad value reads as the default. Thickness is fixed at 1.5 % of the shorter side (ACC-012: a thicker ring is a larger lit area per beat). Rejected: a thickness setting (a second key; the brief asks to keep the set small); continuous sliders (VIS-006-R7, R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See rings pulse out on the beat (Priority: P1)

A user playing music opens Settings, chooses the visual "Beat Rings" and sees a ring appear at the
centre on each beat, grow outward and fade away. The user can make rings last shorter or longer. The
choice is remembered.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: In the simulator, choose Beat Rings in Settings, check that Ring life is offered
and Bars is not, choose a ring life, close Settings and check that the visual is shown and its value
names the choice.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses "Beat Rings", **Then** it replaces the current visual without restarting the audio source.
2. **Given** Beat Rings chosen, **When** Settings is open, **Then** Ring life (Short, Medium, Long) and the Glow controls are offered and Bars is not.
3. **Given** a ring life chosen, **When** the app is relaunched, **Then** it is restored.

---

### User Story 2 - Exactly one independently timed ring per beat (Priority: P1)

Whoever checks the visual feeds four synthetic beats at known times and sees exactly four rings, each
with its own size and brightness given by its own age; once the last ring's life is over, none remain.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Feed four beat times to the ring model with an injected clock and read every
ring's radius and brightness at sample times; render four rings offscreen and compare with a golden.

**Acceptance Scenarios**:

1. **Given** four beats at known times, **When** sampled after the fourth, **Then** exactly four rings are live, and each ring's radius and brightness equal the documented curves evaluated at its own age.
2. **Given** the same four beats, **When** sampled after the last ring's life ends, **Then** zero rings remain.
3. **Given** the same beats and clock replayed, **When** sampled, **Then** the rings are identical.
4. **Given** four rings rendered offscreen, **When** compared with the committed golden, **Then** they pass QA-002's rule.

---

### User Story 3 - Safe at any tempo (Priority: P1)

Rings come on every beat, so fast music could become a flashing pattern. However fast the beats, the
picture never exceeds the strobe envelope; with Reduce flashing on, at most three rings start per
second; never more than a fixed number of rings are drawn at once.

**Independent Test**: Feed beats faster than the caps with injected frame times through the envelope
and count transitions per area; count accepted rings per second and live rings.

**Acceptance Scenarios**:

1. **Given** beats every frame at 60 Hz with thick rings, **When** drawn with Reduce flashing on and off, with and without the strongest glow, **Then** no area has more transitions per window than the budget.
2. **Given** beats every 50 ms with Reduce flashing on, **When** counted over any 1 s window, **Then** at most 3 rings started.
3. **Given** more beats than the ring limit inside one ring life, **When** counted, **Then** never more than 16 rings are live, and the oldest are the ones dropped.

### Edge Cases

- No beat estimate yet (start of a song, rubato): kick transients emit rings instead.
- A confident beat and a kick on the same beat: one ring (the second falls inside the rate cap or is a kick ignored while beats are confident).
- Events arriving out of order or with a time before the newest ring: ignored.
- Silence: no events, so rings finish their lives and the picture becomes the background.
- Output size 0: nothing drawn; tiny sizes give valid geometry.
- Pause and resume: live rings are cleared (no burst of stale rings).
- Ring life changed while running: applies to rings from the next frame without rebuilding the generator.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-006-R1**: Beat rings MUST be a native visual under VIS-001's generator contract and the shared host contract, drawn by the shared flat-triangle pass.
- **VIS-006-R2**: Emission source: an ANL-005 beat whose confidence is at least 0.5 emits a ring; an ANL-007 kick transient emits a ring only when no such confident beat arrived in the previous 2 s; onsets and the mid and high transients never emit rings.
- **VIS-006-R3**: Ring life: each ring has its own birth time; at age a in 0…L (L the ring life) its radius is r(a) = r₀ + (r₁ − r₀)·(1 − (1 − a/L)²) with r₀ = 0.05 and r₁ = 0.95 of half the output's shorter side, and its brightness is α(a) = α_peak · min(1, a/a_attack) · (1 − a/L)² with α_peak = 0.8 and a_attack = 0.05 s. A ring whose age is L or more is removed.
- **VIS-006-R4**: Limit: at most 16 rings are live; a new ring when 16 are live replaces the oldest.
- **VIS-006-R5**: Rate cap: an emission less than 1/6 s after the previous accepted ring is ignored; while the frame's flash envelope limits rises (Reduce flashing on, or a stricter ACC-012 profile) the interval is 1/3 s (at most 3 rings per second). Ignored emissions are dropped, never delayed.
- **VIS-006-R6**: Determinism: the rings drawn at a time are a pure function of the accepted emission times, the configuration and that time; no wall clock is read.
- **VIS-006-R7**: Drawing: each ring is an annulus of 64 flat segments, thickness 1.5 % of the shorter side (at least 1 px), in palette color (n mod 16) of 16 where n counts accepted rings (ACC-003-R13), with its brightness as premultiplied alpha, over an opaque black background.
- **VIS-006-R8**: Flash safety: every frame passes FX-019's envelope with the 17-area model built from the rings' segments (FX-019-R4, R9, FX-001-R10), as the other native visuals.
- **VIS-006-R9**: The app MUST offer "Beat Rings" as a Visual choice (stored `beatRings` under `settings.visual`) with Ring life (`settings.beatRings.life`: `short`/`medium`/`long` = 1.0 / 1.5 / 2.5 s, anything else → medium). Glow shared, Bars hidden. Switching does not restart the audio source; lifecycle and fallback are VIS-001-R12 to R16's. The key is an FR-065 user setting, in the FILE-005 backup policy and the device privacy allow list, and is reset by `-uitestResetNotice`.
- **VIS-006-R10**: Scene capture records beat rings as no native layer (as VIS-003-R12).
- **VIS-006-R11**: Accessibility (FR-070): one element labeled "Beat Rings visualization", identifier `beatRings`, value naming the ring life and the glow (for example "Medium ring life, Glow off"); the new control has a stable identifier.
- **VIS-006-R12**: A golden image of four rings MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator), with the record policy and integrity check.
- **VIS-006-R13**: The other native visuals MUST NOT change: their tests pass unchanged.
- **VIS-006-R14**: Real-time safety (Constitution VII): emission, layout, tessellation, area levels and the event drain allocate nothing per frame.

### Key Entities

- **Beat ring configuration**: ring life, thickness, palette, background.
- **Ring field**: up to 16 birth times with their sequence numbers, the time of the newest accepted ring.
- **Emission selector**: the time of the newest confident beat (for the kick fallback).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-006-S1**: Four synthetic beats at 0, 0.4, 0.8 and 1.2 s sampled at 1.3 s give exactly 4 rings whose radii and brightness match R3 at ages 1.3, 0.9, 0.5 and 0.1 s within 1e-9; sampled at 2.8 s (after the last ring's 1.5 s life), 0 rings.
- **VIS-006-S2**: A replay of the same emissions and clock gives bit-identical rings and geometry.
- **VIS-006-S3**: Beats every 50 ms for 2 s with Reduce flashing on start at most 3 rings in any 1 s window; off, at most 6; never more than 16 live.
- **VIS-006-S4**: Beats on every frame at 60 Hz stay within the transition budget in all 17 areas with Reduce flashing on and off, with and without the strongest glow.
- **VIS-006-S5**: The four-ring picture passes its golden on the macOS host and the iOS Simulator.
- **VIS-006-S6**: One UI test of at most 30 s chooses Beat Rings and a ring life with the source started once; the setting key persists (unit test).
- **VIS-006-S7**: Every existing VisualGenerators and RenderGoldens test passes; the package builds in the Linux shape.

## Assumptions

- Beat and kick events come from the native host's own analysis pipeline (ANL-016), which already runs while a native visual is shown.
- Simulator results are not device evidence; frame time on devices is `{device}` work.
- No new stored data besides the one setting key; no network; the privacy manifest does not change.
- projectM stays the default visual.
