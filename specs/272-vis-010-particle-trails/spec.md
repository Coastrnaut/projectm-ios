# Feature Specification: VIS-010 Particle Trails

**Feature Branch**: `feature/vis-010` (spec directory `272-vis-010-particle-trails`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-010 (Particle trails) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Retain decaying streaks without accumulating unbounded textures." Acceptance, verbatim:
"Ten-minute fixture maintains constant texture allocation." P2, depends on VIS-008 (particle fountain, integrated).
Keep the projectM backend isolated; follow the shader policy. SHD-007 edits the fountain's emitter in parallel: do not
change the emitter, spawn code or its settings."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-010-R1…`, success criteria `VIS-010-S1…`, tasks `VIS-010-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-012 (brightness below full
white, sensory safety profile); VIS-008 (particle fountain), VIS-009 (particle orbit); VIS-020 (fixed-allocation
pattern); FX-009 (compositor Trails, half-life decay model, ADR-0051); FX-019 (strobe safety envelope); PERF-009
(native pipeline archive); SHD-011 (reviewed Metal compile sites, ADR-0024); QA-002 (golden images).

## Baseline: what exists today (audit of 2026-11-14, commit `459ffdaf`)

| Area | Today | Gap for this row |
|---|---|---|
| Particle fountain (VIS-008) | Seeded CPU simulation (512 particles, fixed 1/240 s steps), squares laid out per frame, FX-019 gain over 17 areas, drawn by the shared `FlatShapePass` (clear to background, premultiplied "over"); Gravity setting; goldens on host and simulator. | Each frame is drawn from a cleared target: nothing of earlier frames remains. |
| Particle orbit (VIS-009) | Same shape: seeded simulation, squares, FX-019 gain, `FlatShapePass`; Radius setting; goldens. | Same. |
| `FlatShapePass` | A reviewed Metal compile site (`METAL_SOURCE_ALLOWED`); its source is in PERF-009's archive key (`NativeShaderSources.visualGenerators`). | No texture input or feedback. |
| FX-009 Trails (compositor) | Max-blend feedback `max(current, d·previous)`, decay `d = min(0.5^(Δt/h), 0.99)`, Reduce flashing caps the half-life at 0.25 s (ADR-0051). Compositor-backed visuals only. | The native visuals have no feedback; the package cannot depend on the compositor. |
| VIS-020 waterfall | Fixed-size history texture made once in `init`, tests assert identity and byte count across frames and resizes. | The pattern to copy. |

## Clarifications

### Session 2026-11-14

(Filled by `/speckit-clarify`.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Streaks behind the particles (Priority: P1)

A user watching Particle Fountain or Particle Orbit turns Trails to Short or Long and sees each particle leave a
fading streak behind it; Long streaks fade more slowly than Short ones.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: Render a seeded fountain with trails on and compare with a golden image; compare with trails off.

**Acceptance Scenarios**:

1. **Given** Trails Off (the default), **When** the fountain or orbit draws, **Then** every frame is identical to before this feature (existing goldens unchanged).
2. **Given** Trails Short or Long, **When** a particle moves, **Then** the pixels it covered keep a fading copy of its colour, halving every half-life (Short 0.1 s, Long 0.3 s).
3. **Given** the same trail setting, **When** drawn at 30 and at 120 frames per second, **Then** a streak has the same brightness at the same time (frame-rate independent).

---

### User Story 2 - Constant memory for any length of use (Priority: P1)

However long the visual runs, whatever the screen size and however often the setting changes, trails hold the same
fixed amount of memory.

**Independent Test**: A 10-minute fixture on an injected clock (36 000 frames at 60 Hz).

**Acceptance Scenarios**:

1. **Given** 10 minutes of frames with resizes and setting changes, **When** checked after every frame, **Then** the number of trail textures, their identities and their total allocated size never change after the first frame with trails on.
2. **Given** Trails Off from the start, **When** drawn, **Then** no trail texture exists.

---

### User Story 3 - Safe brightness (Priority: P1)

**Acceptance Scenarios**:

1. **Given** continuous emission for minutes, **When** drawn with trails, **Then** no accumulated value exceeds 0.8 (ACC-012: below full white).
2. **Given** trails on, **When** the strobe safety envelope measures a frame, **Then** it includes an upper bound of the trail's light, and the gain it returns scales the trail too.
3. **Given** Reduce Motion, **When** trails are on, **Then** the half-life is halved; **Given** Reduce flashing, **Then** it is at most 0.25 s.

---

### User Story 4 - Choose it (Priority: P2)

**Acceptance Scenarios**:

1. **Given** Particle Fountain or Particle Orbit chosen, **When** the user opens Settings, **Then** a "Trails" picker (Off, Short, Long) is offered, stored across launches, and applies from the next frame without restarting the audio source.

### Edge Cases

- Output size 0: nothing drawn; the trail is kept.
- Output size changes: the trail is cleared (no stretched history), its storage kept.
- Loop restart (the host's) and turning trails on from Off: the trail starts empty.
- Trails turned Off: the accumulation is kept allocated (no reallocation if turned on again) and is not drawn.
- Non-finite values never enter the accumulation; tiny values fade to exactly 0.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-010-R1**: Trails MUST be an option of the VIS-008 fountain and VIS-009 orbit generators; their emitter, spawn code and configuration types are unchanged; the projectM backend is untouched.
- **VIS-010-R2**: Off MUST be the default and draw exactly the pre-feature frame (same pass, same output).
- **VIS-010-R3**: Storage: two accumulation textures of a fixed size, independent of the output size, created on the first frame with trails on and never recreated or freed while the generator lives; no allocation per frame.
- **VIS-010-R4**: Feedback: each frame the new accumulation is `max(particles, cut(min(d · previous, 0.8)))` per channel; the shown frame is the background, the decayed previous accumulation and the current particles, all scaled by the envelope gain.
- **VIS-010-R5**: Decay: `d = min(0.5^(Δt / h), 0.99)` with Δt the frame clock's duration; half-life h: Short 0.1 s, Long 0.3 s; values below 1/512 become 0.
- **VIS-010-R6**: Reduce Motion halves h; Reduce flashing (or a stricter sensory profile) caps h at 0.25 s.
- **VIS-010-R7**: Flash safety: the envelope's levels MUST include a per-area upper bound of the trail's light, scaled by the same gain as the particles; accumulated values never exceed 0.8.
- **VIS-010-R8**: No new Metal compile site: the trail shader text MUST be part of a reviewed site's module-constant source, so PERF-009's archive key covers it.
- **VIS-010-R9**: The app MUST offer a "Trails" setting (Off/Short/Long, key `settings.particleTrails`, default Off) under the fountain's and orbit's options; it is backed up, erased with Settings and allow-listed.
- **VIS-010-R10**: A golden image of the fountain with trails MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-010-R11**: Accessibility (FR-070): the visual's value appends ", Trails Short" or ", Trails Long" when on; unchanged when Off.

### Key Entities

- **Trail length**: Off, Short, Long (half-life).
- **Trail accumulation**: two fixed-size textures, the index of the newest, a reset flag, the last output size, the 17-area trail estimate.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-010-S1**: A 10-minute fixture (36 000 frames at 60 Hz on an injected clock) with resizes and setting changes keeps the texture count, identities and total allocated size constant after the first trails-on frame, and runs in seconds.
- **VIS-010-S2**: After 0.5 s, a streak's value at 30 and 120 frames per second differs by at most 0.01.
- **VIS-010-S3**: Under continuous emission, no accumulated value exceeds 0.8 (CPU model every frame; GPU readback).
- **VIS-010-S4**: Trails-on goldens pass on the macOS host and the iOS Simulator; existing fountain and orbit goldens are unchanged.
- **VIS-010-S5**: One UI test of at most 30 s chooses Particle Fountain and sets Trails to Long.

## Assumptions

- Device look and frame rate on D1 are `{device}` work; simulator results are not device evidence.
- Trails are not part of scenes (Gravity and Radius are not either).
- No network; the privacy manifest does not change.
