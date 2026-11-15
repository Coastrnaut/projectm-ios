# Feature Specification: VIS-013 Noise Field

**Feature Branch**: `feature/vis-013` (spec directory `252-vis-013-noise-field`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement VIS-013 (Noise field) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Generate layered procedural noise with frequency and seed controls."
Acceptance, verbatim: "Same seed and settings produce matching frames on same GPU class." P1, depends on
ANL-002 (normalized bands, integrated). Reuse SHD-006's seeded noise; keep the projectM backend isolated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `VIS-013-R1…`, success criteria `VIS-013-S1…`, tasks `VIS-013-T01…`. Other features are
cited by their own IDs: FR-065 (what the app may store), FR-070 (accessibility); ACC-001 (Reduce Motion),
ACC-003-R13 (palette), ACC-012 (sensory safety clamp, brightness below full white); VIS-001-R12 to R16 (native
visual contract, lifecycle, fallback); VIS-003-R12 (scene capture); VIS-007 (band groups); ANL-002 (normalized
bands); SHD-006 (seeded lattice noise, CPU reference, per-GPU exact digests); FX-019 (strobe safety envelope);
QA-002 (golden images); FILE-005 (settings backup policy).

## Baseline: what exists today (audit of 2026-11-14, commit `ae588a5d`)

This is a gap row. The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | VIS-001 to VIS-009: one host, frame loop, glow, capture; all draw flat geometry. | No native visual draws a full-screen procedural field. |
| Seeded noise | SHD-006's Noise Flow material: integer lattice hash with a seed, fBm octaves, lacunarity, gain, domain warp; a CPU mirror; exact per-GPU digests. It lives in the compositor's material module, drawn only as a compositor layer. | Not usable by the native visuals (the material module depends on the visuals package, not the other way). |
| Bands | ANL-002's normalized bands reach every native visual each frame; VIS-007 groups them into low, mid and high energies. | Nothing turns them into noise motion. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: How does the noise field reuse SHD-006 instead of duplicating it? → A: The seeded lattice hash, value noise and fBm move into the native visuals package as one shared, reviewed module: the CPU mirror (the material's CPU reference now calls it) and the GPU function text, which the noise field's shader is built from. The Noise Flow material keeps its shader literal unchanged (SHD-001-R7's source-safety test forbids interpolation in it), and a test asserts that its literal contains the shared function text verbatim, so the two can never drift; its recorded per-GPU digests must still match. Rejected: an unguarded copy (two definitions drift); making the visuals package depend on the compositor (a dependency cycle); loosening the material's source-safety rule (VIS-013-R2).
- Q: Which controls does the user get? → A: Three settings: Frequency (Low 2, Medium 4 (default), High 8 noise cells across the shorter side), Octaves (1…6, default 4) and Seed (0…65535, default 1301) with a "New Seed" button that takes the next seed of SHD-006's deterministic seed sequence (never the system random source). Lacunarity 2.03 and gain 0.5 are fixed (SHD-006's defaults). No new modulation catalog parameter (bindings, MIDI and OSC are out of scope). Rejected: exposing lacunarity, gain and warp (more keys, little value on a phone screen); a free-text seed field (keyboard on the visualizer's settings) (VIS-013-R4, R9).
- Q: How do the bands drive it? → A: VIS-007's band groups: the low energy adds domain warp (base warp 0.5 cells + up to 1.0 cell × low), the overall energy (mean of the groups) raises brightness from 0.5 to 0.8 (ACC-012: never above 0.8, below full white). Both follow a one-pole smoother with τ = 0.25 s on the frame's duration (never the wall clock). The field drifts by 0.12 cells per second along (1, 0.5) on the frame clock, from the first frame after a loop restart. Rejected: band-driven frequency (the pattern would jump); band-driven seed (flicker) (VIS-013-R3, R5).
- Q: How is the field kept flash-safe when it is not flat geometry? → A: Every frame the CPU mirror evaluates the field on an 8 × 8 grid of sample points (four per safety tile) with the frame's warp, drift and brightness, and the strobe envelope's gain (FX-019) is solved over all 17 areas from those samples, then multiplies the drawn colour. The estimate is exact in its sample points; the field is smooth (at most 8 base cells across the shorter side), so the tile means it gives are representative. Rejected: a whole-frame upper bound (misses drift between tiles); a GPU readback each frame (stalls the frame) (VIS-013-R6).
- Q: What does "matching frames on the same GPU class" mean, and how is it tested without wall-clock time? → A: Rendering the field twice with the same seed, settings, injected frame clock and fixture band timeline gives byte-identical pixels; a fresh run matches a recorded 64-bit digest per GPU class (the device name, as SHD-006), and a GPU class without a recorded digest prints its digest and skips that comparison; a different seed gives different pixels; a tolerant golden image holds on the macOS host and the iOS Simulator. Reduce Motion (ACC-001) halves the drift and the band warp depth. Rejected: comparing against the CPU mirror bit for bit (Float operations may round differently on a GPU) (VIS-013-R7, R8, R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A repeatable noise field (Priority: P1)

A user chooses "Noise Field" and sees soft, layered clouds of colour that drift slowly and swirl with the music.
They pick how coarse or fine the pattern is, how many layers of detail it has, and a seed; the same seed and
settings always give the same pattern.

**Why this priority**: It is the roadmap row and its acceptance.

**Independent Test**: Render the field offscreen twice with the same seed, settings, frame clock and band
timeline and compare the pixels; change the seed and compare again.

**Acceptance Scenarios**:

1. **Given** a seed, settings, frame clock and band timeline, **When** rendered twice on the same GPU, **Then** the frames are byte-identical and match the GPU class's recorded digest.
2. **Given** a different seed, **When** rendered, **Then** the frame differs.
3. **Given** more octaves or a higher frequency, **When** rendered, **Then** the picture has more fine detail.
4. **Given** a seeded field at a fixed time, **When** rendered, **Then** it matches the committed golden image (macOS host and iOS Simulator).

---

### User Story 2 - Music moves it, safely (Priority: P1)

Bass makes the field swirl more and overall loudness makes it brighter, smoothly, never above the safe
brightness and never flashing.

**Independent Test**: Feed a band timeline and check the warp and brightness follow it smoothly within their
bounds; feed loud bursts alternating with silence and check every area stays within the strobe envelope.

**Acceptance Scenarios**:

1. **Given** silence, **When** drawn, **Then** the field shows its base warp at brightness 0.5 and keeps drifting.
2. **Given** full bands, **When** settled, **Then** warp is 1.5 cells and brightness 0.8, never more.
3. **Given** bursts alternating with silence, **When** drawn with Reduce flashing on and off, **Then** no area exceeds the strobe envelope's transition budget.
4. **Given** Reduce Motion on, **When** drawn, **Then** the drift is half as fast and the bass swirls it half as much.

---

### User Story 3 - Choose and control it (Priority: P1)

The user chooses Noise Field in Settings, sets Frequency, Octaves and Seed, and they are remembered.

**Independent Test**: In the simulator, choose Noise Field, check that its controls are offered and Bars is not,
change Frequency, close Settings and check the visual's value.

**Acceptance Scenarios**:

1. **Given** the visualizer running, **When** the user chooses Noise Field, **Then** it replaces the visual without restarting the audio source.
2. **Given** a frequency, octave count and seed chosen, **When** the app is relaunched, **Then** they are restored.
3. **Given** the user taps New Seed, **When** the field redraws, **Then** it uses a different seed, and the sequence of new seeds is the same on every install.

### Edge Cases

- Output size 0: nothing drawn.
- Bands missing, not finite or outside 0…1: read as 0 or clamped (VIS-007's groups).
- A long frame gap or time going backwards: the drift advances by at most 1 s per frame and never backwards; the smoothers clamp the frame time.
- Pause and resume: the loop restart resets drift to 0 and the smoothers to silence; the strobe envelope's history is kept (FX-019-R11).
- Stored values outside their ranges: frequency → medium, octaves → 4, seed → 1301.
- Settings changed while running: apply from the next frame without rebuilding the visual.

## Requirements *(mandatory)*

### Functional Requirements

- **VIS-013-R1**: The noise field MUST be a native visual under VIS-001's generator contract and the shared host; the projectM backend is untouched.
- **VIS-013-R2**: The field MUST use SHD-006's seeded lattice noise from one shared module (GPU function text and CPU mirror); the material's CPU reference calls the shared mirror, a test proves the material's shader literal contains the shared GPU text verbatim, and the Noise Flow material's recorded digests MUST still match.
- **VIS-013-R3**: Layered noise: fBm of 1…6 octaves (lacunarity 2.03, gain 0.5) at the chosen frequency, domain-warped by two decorrelated fields, drifting on the frame clock; colour = palette colour at the noise value × (0.25 + 0.75 × value) × brightness × the safety gain.
- **VIS-013-R4**: Controls: Frequency (Low/Medium/High = 2/4/8 cells across the shorter side), Octaves (1…6) and Seed (0…65535), plus New Seed from SHD-006's deterministic sequence.
- **VIS-013-R5**: Audio: VIS-007's low group drives the added warp (0…1 cell) and the overall energy drives brightness (0.5…0.8), each smoothed with τ = 0.25 s of frame time; brightness never exceeds 0.8 (ACC-012).
- **VIS-013-R6**: Flash safety: every frame passes FX-019's envelope over all 17 areas, from the CPU mirror sampled on an 8 × 8 grid; no allocation per frame.
- **VIS-013-R7**: Determinism: given the seed, settings, frame clock and band timeline, the frame depends on nothing else (no random source, wall clock or device state).
- **VIS-013-R8**: Reduce Motion (ACC-001): drift × 0.5 and band warp depth × 0.5, applied from the next frame.
- **VIS-013-R9**: The app MUST offer "Noise Field" as a Visual choice (stored `noiseField` under `settings.visual`) with `settings.noiseField.frequency` (`low`/`medium`/`high`, anything else → medium), `settings.noiseField.octaves` (Int 1…6, anything else → 4) and `settings.noiseField.seed` (Int 0…65535, absent or outside → 1301). Glow shared, Bars hidden. The keys are FR-065 user settings, in the FILE-005 backup policy, the device privacy allow list, and reset by `-uitestResetNotice`.
- **VIS-013-R10**: A golden image of a seeded field MUST be compared under QA-002's rule per platform class (macOS host, iOS Simulator).
- **VIS-013-R11**: Scene capture records the noise field as no native layer (as VIS-003-R12).
- **VIS-013-R12**: Accessibility (FR-070): one element labeled "Noise Field visualization", identifier `noiseField`, value naming the settings and glow ("Medium frequency, 4 octaves, seed 1301, Glow off"); each control has a stable identifier.
- **VIS-013-R13**: The other native visuals and the Noise Flow material MUST NOT change behaviour: their tests pass; the package builds in the Linux shape.

### Key Entities

- **Noise field configuration**: frequency (cells), octaves, seed, Reduce Motion, palette, background.
- **Noise drive**: per frame, the smoothed warp and brightness and the drift phase.
- **Band timeline**: per frame, the normalized bands (ANL-002) and the frame time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **VIS-013-S1**: Two renders with the same seed, settings, frame clock and band timeline are byte-identical, and match the recorded digest of a known GPU class; a different seed differs in more than 10 % of pixels.
- **VIS-013-S2**: The settled warp and brightness for full bands are 1.5 cells and 0.8 (within 1 %), for silence 0.5 cells and 0.5; brightness never exceeds 0.8.
- **VIS-013-S3**: Bursts alternating with silence stay within the transition budget in all 17 areas with Reduce flashing on and off.
- **VIS-013-S4**: The GPU field agrees with the CPU mirror within 0.02 in its sample points, and more octaves raise high-frequency energy.
- **VIS-013-S5**: The seeded picture passes its golden on the macOS host and the iOS Simulator.
- **VIS-013-S6**: One UI test of at most 30 s chooses Noise Field with the source started once; the settings persist (unit test); the keys are in every list.
- **VIS-013-S7**: Every existing native visual, Noise Flow material and golden test passes; the packages build in the Linux shape.

## Assumptions

- Bands come from the native host's own analysis pipeline (ANL-002).
- Simulator results are not device evidence; the frame rate on D1 is `{device}` work.
- Three new setting keys; no new catalog parameter; no network; the privacy manifest does not change.
- projectM stays the default visual.
