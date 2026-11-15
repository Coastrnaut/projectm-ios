# Feature Specification: VIS-016 Starfield Flight

**Feature Branch**: `feature/vis-016` (spec directory `287-vis-016-starfield-flight`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement VIS-016 (Starfield flight) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Animate depth-scaled stars with user-set speed and density." Acceptance, verbatim: "Density limit
is enforced and deterministic reset reproduces star positions." P2, M, depends on ANL-002 (normalized bands,
integrated). Keep the projectM backend isolated; follow the shader policy."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-016-R1…`, success criteria `VIS-016-S1…`, tasks `VIS-016-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (palette), ACC-012
(brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12 (scene capture); VIS-007 (band
groups); VIS-008 (particle fountain: fixed pool, seeded generator, fixed-step clock); VIS-009 (particle orbit);
VIS-010 (particle trails); VIS-015 (tunnel, tempo-driven speed); ANL-002 (normalized bands); FX-019 (strobe safety
envelope); PERF-008 (power profile); QA-002 (golden images); FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-15, commit `52bcf734`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Particle visuals (VIS-008, VIS-009) | Fixed pools allocated once, the seeded SplitMix64 generator, 1/240 s fixed steps on the injected frame clock, squares laid out on the CPU and drawn by the shared flat-shape pass, FX-019 envelope over 17 areas from the squares. | No depth: particles live in a 2-D plane; no perspective projection, no density setting. |
| Particle trails (VIS-010) | Optional decayed streaks for the fountain and the orbit. | Wired only for those two visuals. |
| Tunnel (VIS-015) | Depth-like motion whose speed follows the tempo, smoothed. | Not a star field; its speed is not user-set. |
| Noise field family (VIS-013, 014, 015, 020, 011) | One generator with several modes; VIS-012 is adding another mode in parallel. | Not touched by this row. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fly through stars (Priority: P1)

A user chooses "Starfield" and flies through a field of stars: far stars are small and dim near the centre, and they
grow, brighten and stream outwards as they come closer, then are replaced far away. Bass makes the flight surge a
little.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: Drive the starfield with an injected clock; every star moves towards the viewer; its drawn size
and brightness grow as its depth shrinks; a star that passes the viewer reappears far away.

**Acceptance Scenarios**:

1. **Given** the starfield running, **When** frames are drawn, **Then** every active star's depth decreases at the set speed, and its drawn size and brightness never decrease as it approaches.
2. **Given** a star reaches the near plane, **When** the next step runs, **Then** it reappears at the far plane at a new position drawn from the seeded sequence.
3. **Given** a fixed seed, time and band timeline, **When** rendered, **Then** the frame matches the committed golden image (macOS host and iOS Simulator), and two renders are identical.

---

### User Story 2 - Set speed and density, within a limit (Priority: P1)

The user sets how fast they fly (Slow, Medium, Fast) and how many stars there are. Asking for more stars than the
limit gives exactly the limit.

**Why this priority**: The first half of the acceptance.

**Independent Test**: Request densities below, at and above the limit; check the active count; run for a while and
check it never exceeds the limit and the storage never grows.

**Acceptance Scenarios**:

1. **Given** a requested density above the limit, **When** applied, **Then** exactly the limit of stars is active.
2. **Given** any density, **When** the starfield runs, **Then** the active count never exceeds the limit and the star storage stays the same size and place.
3. **Given** a speed change while running, **When** the next frame is drawn, **Then** it applies without restarting the stars.

---

### User Story 3 - Deterministic reset (Priority: P1)

Restarting the visual (re-entering it, a seed change or a reset) puts every star back exactly where it started, and
the same seed always flies the same way whatever the frame rate.

**Why this priority**: The second half of the acceptance.

**Independent Test**: Record the initial positions; run; reset; compare bit for bit. Run the same seed at a steady
60 Hz and at jittery frame times and compare at shared times; run a different seed and compare.

**Acceptance Scenarios**:

1. **Given** a run of several seconds, **When** reset, **Then** every star's position equals its initial seeded position bit for bit.
2. **Given** the same seed, **When** run at 60 Hz and at jittery frame times, **Then** positions at shared times are identical.
3. **Given** a different seed, **When** run, **Then** the positions differ.

---

### User Story 4 - Safe and calm when asked (Priority: P2)

The stars never flash, the field's total light is bounded, and Reduce Motion slows the flight.

**Acceptance Scenarios**:

1. **Given** the densest field at the fastest speed with bass bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
2. **Given** any density and speed, **When** laid out, **Then** the field's mean light never exceeds the total-light bound.
3. **Given** Reduce Motion on, **When** settled, **Then** the speed is half.

---

### User Story 5 - Choose it in Settings (Priority: P2)

The user chooses Starfield in Settings, sets Speed and Stars, and both are remembered.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Starfield, **Then** it replaces the visual without restarting the audio source.
2. **Given** speed and density chosen, **When** the app is relaunched, **Then** both are restored; stored values out of range fall back to the defaults.

### Edge Cases

- Output size 0: nothing drawn. Non-square outputs: the centre is the frame centre; the shorter side sets the scale.
- Stars outside the frame: not drawn (and not counted for flash safety) until they respawn.
- Long frame gaps (over 1 s) or time going backwards: at most 1 s of motion per frame, never backwards; the skip is counted.
- Density requested below the minimum, above the limit, or not a number: clamped to the range.
- Bands absent, NaN or negative: read as silence.
- Switching density down and back up: the stars that come back are where the shared sequence put them (the whole pool keeps moving).

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-016-R1**: The starfield MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-016-R2**: Stars live in a fixed pool sized to the density limit, allocated once; the user's density selects how many are active, clamped to the limit; nothing is allocated per frame.
- **VIS-016-R3**: Each star has a seeded position (x, y, depth z). It approaches at the speed setting on fixed time steps of the injected frame clock; below the near plane it respawns at the far plane with new x, y drawn from the seeded generator in a fixed order.
- **VIS-016-R4**: Positions over time are a deterministic function of the seed, the band input and the injected frame times; reset (loop restart, visual re-entry, seed change) restores the exact initial positions.
- **VIS-016-R5**: Perspective: the drawn position is (x, y) / z from the centre; size and brightness grow with 1 / z, within bounds; stars fade in at the far plane and out at the near plane.
- **VIS-016-R6**: Speed: Slow, Medium (default), Fast, plus a bass boost from the low band group within a cap; Reduce Motion halves it.
- **VIS-016-R7**: Flash safety: the field's total light is bounded (mean frame light ≤ the bound, star alphas scaled uniformly when over); every frame passes FX-019's envelope over all 17 areas; star alpha ≤ 0.8 (ACC-012).
- **VIS-016-R8**: The app MUST offer "Starfield" as a Visual choice (stored `starfield` under `settings.visual`) with `settings.starfield.speed` (`slow`/`medium`/`fast`; anything else → `medium`) and `settings.starfield.density` (Int 100…2000 in steps of 100; anything else → 600). Glow and palette shared; Bars hidden. The keys are FR-065 user settings, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-016-R9**: A golden image of the starfield MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-016-R10**: Scene capture records the starfield as no native layer (as VIS-003-R12).
- **VIS-016-R11**: Accessibility (FR-070): one element labeled "Starfield visualization", identifier `starfield`, value "Medium speed, 600 stars, Glow off"; the two controls have stable identifiers.
- **VIS-016-R12**: The other native visuals MUST NOT change behaviour: their tests pass; the package builds in the Linux shape.

### Key Entities

- **Star**: x, y (lateral), z (depth); in a fixed pool.
- **Starfield configuration**: density (requested), speed choice, seed, Reduce Motion, palette, background.
- **Starfield simulation**: the pool, the seeded generator, the step anchor and count, the smoothed bass, respawn and skip counters.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-016-S1**: Requesting 5000 stars gives exactly 2000 active; over a 5 s run the active count never exceeds 2000 and the storage address and size do not change.
- **VIS-016-S2**: After any run, reset restores every star's (x, y, z) bit for bit; 60 Hz and jittery frame times give bit-identical positions at shared times; another seed differs.
- **VIS-016-S3**: Two GPU renders from scratch are identical, every lit pixel belongs to a laid-out star, and the golden passes on the macOS host and the iOS Simulator.
- **VIS-016-S4**: The densest, fastest field with bass bursts stays within the transition budget in all 17 areas with Reduce flashing on and off; the mean light never exceeds the bound.
- **VIS-016-S5**: One UI test of at most 30 s chooses Starfield with the source started once; the settings persist (unit test); the keys are in every list.
- **VIS-016-S6**: New package host tests take about 3 s in total; every existing test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis (ANL-002), as for every native visual.
- Simulator results are not device evidence; the frame rate and look on D1 are `{device}` work.
- Two new setting keys; no new catalog parameter; no network; the privacy manifest does not change.
- projectM stays the default visual.
- No new shader: the starfield draws through the reviewed flat-shape pass (its shader source is already a pipeline archive key source).
