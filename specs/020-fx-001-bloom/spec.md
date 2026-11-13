# Feature Specification: FX-001 Bloom

**Feature Branch**: `feature/fx-001` (spec directory `020-fx-001-bloom`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FX-001 (Bloom) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Add thresholded glow with radius and intensity controls."
Acceptance, verbatim: "Black pixels remain black and bright test patch gains bounded halo."
Dependencies: VIS-001 (integrated; ADR-0009). Honor the repository constitution."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FX-001-R1…`, success criteria `FX-001-S1…`, tasks `FX-001-T01…`. Requirements of
feature 001 that this row touches are cited by their own IDs: FR-065 (what the app may store),
FR-070 (accessibility), FR-072 (Reduce flashing). VIS-001's requirements stay in force, in
particular VIS-001-R10 (Reduce flashing bounds), VIS-001-R16 (failure fallback) and VIS-001-R17
(runtime-compiled shaders).

## Baseline: what exists today (audit of 2026-11-13, commit `8580d23`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Post-processing | None. `CircularSpectrumGenerator` (VIS-001) draws straight into the `CAMetalLayer` drawable. projectM frames go through ANGLE and `CFlashLimiter`; nothing of the app's own processes a finished frame. | An effect interface, a chain that runs effects in order, and the bloom effect. |
| Native visuals | `Packages/VisualGenerators`: the `TextureGenerator` contract (encode into a caller-owned texture and command buffer; `bgra8Unorm_srgb` or `rgba16Float`; linear premultiplied color), `FlashSafetyLimiter` (bar slew and mean-luminance rise bound computed from the CPU geometry). | The limiter knows only the generator's own luminance; a glow added after it would raise the final brightness without the limiter seeing it. |
| Settings | `settings.visual` and `settings.circularSpectrum.bars` (VIS-001-R11); Reduce flashing (FR-072). | No glow controls, no stored glow values. |
| Compositor | Not started (CMP-001 depends on this row). | Effects must be usable by a future layer compositor without depending on the circular spectrum. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option, recommended option
first.

- Q: What does "black pixels remain black" mean, given that a glow must light dark pixels next to a bright patch? → A: Two testable statements. (1) A frame that is entirely black stays exactly (0, 0, 0, 0) at every allowed setting: the effect adds no bias, noise, dithering or ambient fog. (2) A black pixel farther than the stated halo extent from every contributing pixel stays exactly black; inside that extent black pixels may glow, which is the "bounded halo" half of the criterion. Rejected: "black pixels never change" (it would forbid any halo on black, contradicting the second half of the criterion) (FX-001-R5, R7).
- Q: Where does the post-processing infrastructure live: a new `Packages/Compositor` (the roadmap's proposed layout) or the existing `Packages/VisualGenerators`? → A: A new target `VisualEffects` inside `Packages/VisualGenerators`, in the same library product. It depends on the `VisualGenerators` target (linear color, luminance model hook) and nothing else; the circular spectrum does not depend on it. Reasons: the roadmap says to prefer extending existing packages; the same product means CI's package loops and `project.yml` need no change while another agent edits them; CMP-001 can move the target into `Packages/Compositor` (or depend on this package) without touching effect code. ADR-0010 records the effect architecture. Rejected: effects inside the generator (CMP-001 needs them on any layer) and a new package now (shared CI and project edits for no functional gain) (FX-001-R1, R2).
- Q: Is the glow on or off by default, and what are the defaults? → A: Off. VIS-001's approved picture and brightness stay unchanged until the user asks for a glow, which is the conservative choice for sensory safety. When turned on: Intensity 0.5, Radius 0.02 of the shorter side, Threshold 0.7, soft knee 0.5 (FX-001-R4). Intensity is capped at 1 so that no halo pixel can exceed the brightest source pixel (FX-001-R7 b).
- Q: How does Reduce flashing see the glow's added brightness: a conservative multiplier, a GPU read-back, or an exact CPU model? → A: An exact CPU model. The circular spectrum is made of flat-colored regions whose areas the generator already computes (VIS-001-D7). The glow's added mean luminance is at most intensity × the mean luminance of the thresholded image (the blur's weights sum to one and pixels outside the frame read zero, so it never adds energy), and the thresholded value of a flat color is a known function of that color. The limiter therefore solves for the largest gain whose modeled final luminance (bars + background + glow) stays within the 0.25-per-second rise, by bisection with a fixed iteration count (no allocation). Rejected: a fixed (1 + intensity) multiplier (it would let the actual luminance jump when a bar crosses the threshold) and a GPU read-back (one frame late and a stall on the frame path). The GPU test measures the composited frames to confirm the model (FX-001-R10, S4).
- Q: In what unit is the Radius control and how is the blur's cost bounded? → A: Radius is a fraction of the output's shorter side (0.005…0.06), so the halo looks the same on every screen size and render scale. The thresholded image is reduced by a factor D of 2, 4 or 8 (the smallest that keeps the blur radius at or below 16 samples per side), blurred with a separable, normalized, truncated Gaussian (at most 33 taps per direction) and enlarged with bilinear interpolation. The halo extent bound is then (R + 2) × D pixels from the nearest contributing pixel, where R is the blur radius in reduced pixels; the plan derives it (FX-001-R7, R15).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn on a glow around the bright parts of the circular spectrum (Priority: P1)

A user watching the Circular Spectrum opens Settings, turns on "Glow", and sees a soft halo spread
around the bright bars while the dark background stays dark. They adjust Intensity (how strong the
halo is), Radius (how far it spreads) and Threshold (how bright a part must be to glow) and see the
change on the running visual without the music restarting. The choices are remembered next launch.

**Why this priority**: It is the row's observable behavior ("Add thresholded glow with radius and
intensity controls").

**Independent Test**: In the simulator, choose Circular Spectrum, turn Glow on, move the sliders,
relaunch: the toggle and slider values persist and the source start count does not change.

**Acceptance Scenarios**:

1. **Given** Circular Spectrum is the visual and Glow is off (the default), **When** the user turns
   Glow on, **Then** Intensity, Radius and Threshold controls appear with their current values and
   the visual shows a halo around its bright bars.
2. **Given** Glow is on, **When** the user changes a slider, **Then** the running visual uses the new
   value from the next frame and audio is not restarted.
3. **Given** the user set Glow and its values, **When** the app is relaunched, **Then** the same
   values are shown and used.
4. **Given** projectM is the visual, **Then** no glow controls are shown and projectM's picture is
   unchanged.

---

### User Story 2 - Black stays black, the halo is bounded (Priority: P1)

The glow must never fog the picture: an all-black frame stays exactly black, dark content below the
threshold is unchanged, and the halo around a bright patch stays within a known distance, never
gets brighter than the patch and fades with distance.

**Why this priority**: It is the row's acceptance criterion ("Black pixels remain black and bright
test patch gains bounded halo").

**Independent Test**: Render synthetic frames (all black; a bright square on black; a gradient; a
patch below the threshold) through the real effect on a GPU, read the pixels back and compare them
with the documented bounds.

**Acceptance Scenarios**:

1. **Given** an all-black input, **When** the glow runs at any allowed setting, **Then** every
   output pixel is exactly black (0, 0, 0, 0).
2. **Given** a bright square on black, **When** the glow runs, **Then** pixels just outside the
   square become non-zero, no pixel outside the square is brighter than the square, values do not
   increase moving away from the square, and every pixel farther than the documented halo extent is
   exactly black.
3. **Given** a patch below the threshold, **When** the glow runs, **Then** the output equals the
   input within 1/255 per channel.
4. **Given** intensity 0 or Glow off, **Then** the output is bit-for-bit the input.
5. **Given** the same input and settings twice, **Then** both outputs are bit-for-bit identical.

---

### User Story 3 - Reduce flashing still holds with the glow on (Priority: P1)

A user who relies on Reduce flashing turns Glow on. The glow raises brightness, so the brightness
limit must apply to the final picture, including the glow, not only to the bars beneath it.

**Why this priority**: Sensory safety (FR-072) must not regress; a feature that adds brightness
could otherwise defeat the limit.

**Independent Test**: Feed alternating silent and full-scale band frames through generator → glow
with Reduce flashing on and check that the final frame's mean luminance rises no faster than the
documented bound; on a GPU, measure it from the read-back pixels.

**Acceptance Scenarios**:

1. **Given** Reduce flashing is on and Glow is at maximum intensity, **When** the bands alternate
   between silence and full scale every frame, **Then** the final frame's mean relative luminance
   rises by at most 0.25 per second of frame time (VIS-001-R10's bound), measured on the composited
   output.
2. **Given** Reduce flashing is on, **When** the user turns Glow on while the visual runs, **Then**
   the brightness added by the glow is introduced no faster than the same bound.

---

### User Story 4 - The visual never goes black when the glow fails (Priority: P2)

If the glow cannot be set up on a device (for example its shaders fail to build), the Circular
Spectrum still renders without it and the app says so in Settings and to VoiceOver.

**Why this priority**: Failure boundary (roadmap architecture 8): degrade, never a black screen.

**Independent Test**: Launch with a test flag that makes the glow fail to build; the circular
spectrum is shown and a notice "Glow isn't available on this device." is shown and announced.

**Acceptance Scenarios**:

1. **Given** the glow's pipeline cannot be built, **When** the user turns Glow on, **Then** the
   circular spectrum keeps rendering without glow, a visible notice appears and is announced, and
   the stored Glow setting is kept.

---

### Edge Cases

- Output size changes (rotation, iPad multitasking, the quality governor's render scale): the
  effect's working images are resized once for the new size; no frame is lost to a mismatched size.
- Tiny outputs (1×1, sizes not divisible by the downsample factor): the effect still runs and the
  bounds still hold.
- Out-of-range or non-numeric stored values (NaN, negative, too large): clamped into range; NaN reads
  the default.
- Glow enabled with intensity 0: pass-through, no extra GPU work.
- Glow on while the app is in the background: no frames run (PERF-011), nothing changes.
- Reduce flashing switched on while Glow is on: the limit applies from the next frame, from the
  current picture (no jump).
- Very bright input above 1.0 in an extended-range target: the glow stays finite (no NaN or
  infinity) and the halo bound uses the brightest source pixel.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-001-R1**: A reusable post-processing effect interface: an effect reads one input image and
  writes one output image of the same size and pixel format, in linear light with premultiplied
  alpha, and declares the pixel formats it accepts. Its working images are created before frames run
  and sized to the output; per-frame work creates no new images or buffers.
- **FX-001-R2**: An effect chain that runs an ordered list of effects from a source to a final
  output, skips effects that are pass-through, and lets the source draw straight into the output
  when every effect is pass-through. The chain's order and parameters have a stable, versioned,
  serializable description with stable effect identifiers, so FX-020 can store chains in scene
  documents later.
- **FX-001-R3**: Bloom: a thresholded glow. Each pixel contributes to the glow only by how much its
  brightness exceeds a threshold, with a soft knee so the onset is smooth; the contribution is
  spread with a blur of fixed, bounded cost and added to the input scaled by the intensity.
- **FX-001-R4**: Bloom controls and ranges: Glow on/off (default off); Intensity 0…1 (default 0.5);
  Radius 0.005…0.06 of the output's shorter side (default 0.02); Threshold 0.1…1.0 of full
  brightness (default 0.7); soft knee 0…1 of the threshold (default 0.5, not shown in Settings).
  Out-of-range values are clamped; non-numeric values read the default.
- **FX-001-R5**: Black stays black: an all-black input gives an exactly black output at every
  allowed setting, and any input pixel farther than the halo extent (R7) from every pixel above the
  knee's lower end is output unchanged; for black input pixels that means exactly black.
- **FX-001-R6**: Below-threshold content is unchanged: pixels whose brightness is at or below the
  knee's lower end contribute nothing; a frame containing only such pixels is output equal to the
  input within 1/255 per channel.
- **FX-001-R7**: The halo is bounded: (a) its extent from the nearest contributing pixel is at most
  the configured radius plus the blur's support, stated in pixels by the plan; (b) no pixel outside
  a bright patch gets brighter than the patch's brightest pixel; (c) along a line leaving the patch
  the halo does not increase; (d) the total added brightness is at most intensity × the
  above-threshold brightness of the input.
- **FX-001-R8**: Intensity 0 or Glow off is an exact pass-through (bit for bit).
- **FX-001-R9**: Determinism: identical input and parameters give bit-identical output on the same
  device.
- **FX-001-R10**: Reduce flashing on the final picture: while Reduce flashing (FR-072) is on, the
  circular spectrum's mean-luminance limit (VIS-001-R10: rise at most 0.25 per second of clamped
  frame time) applies to the frame after the glow, using an exact model of the glow's added
  brightness; the bar slew limit is unchanged.
- **FX-001-R11**: Settings: in the Visual section, for Circular Spectrum only, a "Glow" toggle and,
  while it is on, Intensity, Radius and Threshold sliders with VoiceOver labels and values (FR-070).
  The four values are stored as user settings (FR-065) under `settings.circularSpectrum.glow`,
  `…glowIntensity`, `…glowRadius`, `…glowThreshold`; the device privacy check's allowed list gains
  them.
- **FX-001-R12**: Changing a glow setting takes effect on the running visual from the next frame,
  does not restart the audio source and does not rebuild shaders.
- **FX-001-R13**: Failure boundary: if the glow cannot be built, the circular spectrum renders
  without it, Settings shows "Glow isn't available on this device." and VoiceOver announces it; the
  stored setting is kept. The screen is never black because of the glow.
- **FX-001-R14**: Resize: the glow's working images follow the output size; they are recreated only
  when the size or format changes.
- **FX-001-R15**: Cost is bounded: the blur reads a fixed maximum number of samples per pixel
  whatever the radius, at a reduced resolution chosen from the radius.
- **FX-001-R16**: Scope and isolation: projectM's renderer, frames and presets are untouched; no
  networking, no private APIs, no new dependencies; shaders are compiled at runtime from package
  constants (VIS-001-R17).

### Key Entities

- **Bloom parameters**: enabled, intensity, radius, threshold, soft knee; clamped values with
  documented ranges and defaults.
- **Effect chain description**: a format version and an ordered list of effect entries, each a
  stable effect identifier plus its parameters.
- **Glow settings**: the four stored user settings of the circular spectrum's glow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-001-S1**: In GPU checks of an all-black frame at every allowed corner of the parameter ranges,
  100 % of output pixels are exactly (0, 0, 0, 0).
- **FX-001-S2**: In GPU checks of a bright square on black, the pixel next to the square is non-zero,
  0 pixels beyond the stated halo extent are non-zero, 0 halo pixels exceed the square's brightness,
  and the halo never increases moving outward.
- **FX-001-S3**: A below-threshold patch is reproduced within 1/255 per channel; intensity 0 and
  identical repeated runs are bit-for-bit equal.
- **FX-001-S4**: With Reduce flashing on and the glow at maximum, alternating silent and full-scale
  frames never raise the final frame's mean luminance by more than 0.25 per second of frame time
  (CPU model on every host; GPU measurement within 0.002 where a GPU exists).
- **FX-001-S5**: Glow settings persist across relaunch and changing them never restarts the source
  (source start count stays 1).
- **FX-001-S6**: A forced glow failure leaves the circular spectrum on screen with an accessible
  notice in 100 % of runs.
- **FX-001-S7**: Glow off is pixel-identical to VIS-001's picture (the generator draws directly to
  the screen).

## Assumptions

- The glow applies to the Circular Spectrum only; post-processing projectM frames needs the layer
  compositor (CMP-001).
- Glow is off by default so the approved VIS-001 picture and its brightness are unchanged until the
  user asks for it.
- GPU checks run on the Mac host and the simulator and skip (never fail) where no GPU exists; device
  GPU checks (frame cost, appearance) are final-phase `{device}` tasks.
- Tone mapping (FX-002), grading (FX-003), motion feedback (FX-009), the shared strobe envelope
  (FX-019), stored chains (FX-020), adaptive quality (PERF-003) and a texture pool (PERF-004) are
  later rows; this feature leaves room for them but does not implement them.
