# Feature Specification: VIS-017 Signed-Distance Primitives

**Feature Branch**: `feature/vis-017` (spec directory `304-vis-017-signed-distance-primitives`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement VIS-017 (Signed-distance primitives) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Raymarch bounded spheres, toroids and boxes with quality cap." Acceptance, verbatim:
"Scene remains finite and quality presets bound step counts." P2, L, depends on ANL-002 (normalized bands,
integrated). Test: Metal, CoreGraphics; keep the projectM backend isolated; golden image + simulator + device GPU."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`VIS-017-R1…`, success criteria `VIS-017-S1…`, tasks `VIS-017-T01…`. Other features are cited by their own IDs:
FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion), ACC-003-R13 (palette), ACC-012
(brightness below full white); VIS-001-R12 to R16 (native visual contract); VIS-003-R12 (scene capture); VIS-007 (band
groups); VIS-013/014/015/020/011/012 (the noise field generator and its modes); ANL-002 (normalized bands); FX-019
(strobe safety envelope); PERF-009 (native pipeline archive); SHD-011 (shader policy); QA-002 (golden images);
FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-15, commit `47ea6947`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Full-screen procedural visuals (VIS-013 noise field, VIS-014 kaleidoscope, VIS-015 tunnel, VIS-020 waterfall, VIS-011 fluid ink, VIS-012 reaction diffusion) | One generator (`NoiseFieldGenerator`) with one module-constant shader, one entry point per mode, a CPU mirror sampled at 64 points for the FX-019 envelope, band-driven drive on the injected frame clock, palette, Reduce Motion, goldens. | No 3-D geometry, no ray marching, no quality setting. |
| Tunnel (VIS-015) | A depth illusion from a polar mapping. | Not a marched scene; no step count. |
| Starfield (VIS-016) | Perspective-projected points on the flat-shape pass. | Points only, no surfaces. |
| Shader compile sites (SHD-011, `check_compliance.py`) | Ten reviewed files; `NoiseFieldGenerator.swift` is one (ADR-0066). | — (this row adds none). |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See solid shapes move with the music (Priority: P1)

A user chooses the 3-D shapes visual and sees a lit sphere, a ring (torus) and a few boxes floating in the dark,
turning slowly; bass makes the sphere swell a little and the mid sound turns the scene a little faster; the overall
loudness brightens it gently.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: Render the scene with fixture bands at fixed times; the frame shows the three kinds of shape;
more bass makes the sphere larger within its bound; time turns the scene.

**Acceptance Scenarios**:

1. **Given** the visual running with silence, **When** a frame is drawn, **Then** a sphere, a torus and the boxes are visible on a dark background.
2. **Given** a bass-heavy input, **When** the drive settles, **Then** the sphere's radius grows but never beyond its bound, and the whole scene stays inside its bounding volume.
3. **Given** a fixed time and band timeline, **When** rendered, **Then** the frame matches the committed golden image (macOS host and iOS Simulator), and two renders are identical.

---

### User Story 2 - Pick a quality that bounds the work (Priority: P1)

The user picks Low, Medium or High quality. Each preset caps how many marching steps any pixel may take; higher
quality looks sharper, lower quality costs less.

**Why this priority**: The second half of the acceptance ("quality presets bound step counts").

**Independent Test**: Render a step-count view of the scene per preset (on the GPU) and march the CPU mirror over many
rays, including grazing and missing rays; the largest step count never exceeds the preset's cap; the presets' caps
are ordered Low < Medium < High.

**Acceptance Scenarios**:

1. **Given** any preset, **When** a frame is marched, **Then** no pixel takes more steps than the preset's cap.
2. **Given** a quality change while running, **When** the next frame is drawn, **Then** it uses the new cap without restarting the animation.

---

### User Story 3 - The picture never breaks (Priority: P1)

Whatever the input (silence, extreme or invalid band values, long frame gaps, huge times, zero-sized outputs), every
pixel is a finite colour within range: no black holes from invalid maths, no infinite loops.

**Why this priority**: The first half of the acceptance ("scene remains finite").

**Independent Test**: Render to a floating-point target with extreme inputs and read every pixel back; march the CPU
mirror with extreme parameters.

**Acceptance Scenarios**:

1. **Given** NaN, infinite, negative or above-range band values, **When** frames are drawn, **Then** every output value is finite and within 0…1.
2. **Given** a very long run time or a time jump, **When** drawn, **Then** the scene's turning stays bounded and every output value is finite.

---

### User Story 4 - Safe and calm when asked (Priority: P2)

The shapes never flash, their brightness stays below full white, and Reduce Motion slows the turning and softens the
swelling.

**Acceptance Scenarios**:

1. **Given** bass bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
2. **Given** Reduce Motion on, **When** settled, **Then** the turning speed and the swell depth are half.

---

### User Story 5 - Choose it in Settings (Priority: P2)

The user chooses the 3-D shapes visual in Settings, sets Quality, and the choice is remembered.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses the shapes visual, **Then** it replaces the visual without restarting the audio source.
2. **Given** a quality chosen, **When** the app is relaunched, **Then** it is restored; a stored value that is not a preset falls back to the default.

### Edge Cases

- Output size 0: nothing drawn. Non-square outputs: the centre is the frame centre; the shorter side sets the scale.
- Rays that miss the scene's bounding volume take no marching steps; rays that graze a surface stop at the step cap and show the background.
- Long frame gaps or time going backwards: at most a bounded step of motion per frame, never backwards.
- Bands absent, NaN or negative: read as silence; above 1: read as 1.
- Switching to and from the other noise-field modes keeps the generator; the shapes start from their initial pose.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-017-R1**: The shapes MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-017-R2**: The scene MUST contain spheres, a torus and boxes, all inside a fixed bounding volume whatever the input; the primitive count is fixed.
- **VIS-017-R3**: Each pixel is found by marching a ray through the scene's distance field with a step cap, a distance cap and a hit threshold, so the march always ends.
- **VIS-017-R4**: Quality presets Low, Medium (default) and High MUST each set a step cap, ordered Low < Medium < High, with an absolute ceiling no input can exceed.
- **VIS-017-R5**: Every output value MUST be finite and within 0…1 for any band input, time or output size.
- **VIS-017-R6**: Audio drive (ANL-002 bands, VIS-007 groups): low swells the sphere within a bound, mid speeds the turning within a cap, overall brightens within a cap below full white (ACC-012); smoothed on the injected frame clock; Reduce Motion halves turning speed and swell depth.
- **VIS-017-R7**: Flash safety: every frame passes FX-019's envelope over all 17 areas, estimated from a CPU mirror of the same scene.
- **VIS-017-R8**: The app MUST offer the visual as a Visual choice (stored `signedDistance` under `settings.visual`) with `settings.signedDistance.quality` (`low`/`medium`/`high`; anything else → `medium`). Glow and palette shared; Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-017-R9**: A golden image of the scene MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-017-R10**: Scene capture records the visual as no native layer (as VIS-003-R12).
- **VIS-017-R11**: Accessibility (FR-070): one element with a label, a stable identifier and a value naming the quality and glow; the Quality control has a stable identifier.
- **VIS-017-R12**: The other native visuals MUST NOT change behaviour: their tests and goldens pass; the package builds in the Linux shape.

### Key Entities

- **Quality preset**: step cap, hit threshold.
- **Scene pose**: turning angle, sphere radius, brightness (the drive's output per frame).
- **March result**: steps taken, distance travelled, hit or miss, primitive kind.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-017-S1**: On the GPU and on the CPU mirror, the largest per-pixel step count is ≤ the preset's cap for every preset, and the caps are strictly ordered.
- **VIS-017-S2**: With extreme inputs (NaN, ±infinity, 1e6 band values, a 10⁹ s time), every pixel of a floating-point render is finite and within 0…1.
- **VIS-017-S3**: Two GPU renders from scratch are identical, and the golden passes on the macOS host and the iOS Simulator.
- **VIS-017-S4**: Bass bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-017-S5**: One UI test of at most 30 s chooses the visual and a quality with the source started once; the setting persists (unit test); the key is in every list.
- **VIS-017-S6**: New package tests take a few seconds in total; every existing test passes; the package builds in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis (ANL-002), as for every native visual.
- Simulator results are not device evidence; the frame rate and look on D1 are `{device}` work.
- One new setting key; no network; the privacy manifest does not change.
- projectM stays the default visual.
