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

## Clarifications

### Session 2026-11-15

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where does the marched scene live? → A: As one more mode of the noise field generator (`NoiseFieldConfiguration.signedDistance`, a settings value; nil = off, on forces every other mode off), drawn by its own entry point in that generator's module-constant shader, like VIS-012 and VIS-015. No new shader compile site, no compliance or ADR change; the new text joins the PERF-009 archive key automatically. Rejected: a new generator file with its own `makeLibrary(source:)` (a reviewed compile-site change under SHD-011 / ADR-0024) (VIS-017-R1).
- Q: What exactly is in the scene, and how is "bounded" guaranteed? → A: Six primitives, fixed: one sphere at the centre (radius 0.55, swelling with bass to at most 0.70), one torus around it (major radius 1.05, tube 0.11, tilted and turning), and four boxes (half-size 0.16, slightly rounded) orbiting at radius 1.6 in the torus's plane, turning the other way. Everything lies inside a bounding sphere of radius 2.0 at the origin, whatever the input; the camera sits 4.5 units away looking at the origin (vertical field of view about 50°). A ray that misses the bounding sphere is background with zero steps; a ray that enters starts marching at the entry point and stops at the exit point (VIS-017-R2, R3).
- Q: What do the quality presets bound? → A: The marching step cap per pixel: Low 24, Medium 48 (default), High 96; hit threshold 0.004, 0.002, 0.001 of a unit. The shader also clamps the cap to an absolute ceiling of 128 whatever the uniform says. Normals use 4 extra distance evaluations (the tetrahedral estimate) at a hit only; there are no shadow or ambient-occlusion marches, so a pixel costs at most cap + 4 scene evaluations. A ray that runs out of steps before hitting shows the background (VIS-017-R3, R4; S1).
- Q: How do the bands drive it, and how is it kept calm and finite? → A: VIS-007's groups of the ANL-002 bands, sanitized (NaN/negative → 0, above 1 → 1). Swell = low, smoothed (attack τ 0.08 s, release τ 0.3 s), sphere radius 0.55 + 0.15 × swell (× 0.5 depth with Reduce Motion). Turning speed 0.25 + 0.35 × mid rad/s (≤ 0.6; × 0.5 with Reduce Motion), smoothed τ 0.5 s, angle advanced on the injected frame clock (≤ 0.25 s per frame, never backwards) and wrapped to [0, 2π). Brightness 0.5 + 0.3 × overall (≤ 0.8, ACC-012), smoothed τ 0.25 s. Shading: palette colour per primitive kind × (0.15 ambient + 0.85 diffuse) × brightness × the FX-019 gain; every value is NaN-guarded and clamped to 0…1. The FX-019 estimate is the CPU mirror of the same march at the 64 sample points (VIS-017-R5, R6, R7).
- Q: How does the app name and store it? → A: Visual choice "SDF Shapes" (stored `signedDistance`), one key `settings.signedDistance.quality` (`low`/`medium`/`high`, anything else → `medium`), Quality as a segmented picker (`signedDistanceQualityPicker`); accessibility label "SDF Shapes visualization", identifier `signedDistance`, value "<Quality> quality, <glow>" (e.g. "Medium quality, Glow off"). A quality change applies in place from the next frame (same generator, the pose keeps turning). No SCN-001 layer kind, as VIS-015 (VIS-017-R8, R10, R11).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See solid shapes move with the music (Priority: P1)

A user chooses "SDF Shapes" and sees a lit sphere, a ring (torus) and a few boxes floating in the dark,
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

The user chooses "SDF Shapes" in Settings, sets Quality, and the choice is remembered.

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
- **VIS-017-R8**: The app MUST offer "SDF Shapes" as a Visual choice (stored `signedDistance` under `settings.visual`) with `settings.signedDistance.quality` (`low`/`medium`/`high`; anything else → `medium`). Glow and palette shared; Bars hidden. The key is an FR-065 user setting, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-017-R9**: A golden image of the scene MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-017-R10**: Scene capture records the visual as no native layer (as VIS-003-R12).
- **VIS-017-R11**: Accessibility (FR-070): one element labeled "SDF Shapes visualization", identifier `signedDistance`, value "Medium quality, Glow off"; the Quality control has the identifier `signedDistanceQualityPicker`.
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
