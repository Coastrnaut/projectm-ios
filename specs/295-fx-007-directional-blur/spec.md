# Feature Specification: FX-007 Directional Blur

**Feature Branch**: `feature/fx-007` (spec directory `295-fx-007-directional-blur`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-007 (Directional blur) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Blur along a selected angle with fixed tap budget." Acceptance, verbatim: "Angle zero blurs
horizontally and radius zero is identity." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-007-R1…`, success criteria `FX-007-S1…`, tasks
`FX-007-T01…`, research decisions `FX-007-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor;
ADR-0013), FX-001 (bloom), FX-002 (tone map), FX-003/FX-004/FX-005 (colour grade and contrast curves), FX-006
(chromatic split; ADR-0104), FX-009 (Trails; ADR-0051), FX-019 (composite flash guard), FX-020 (effect chains;
ADR-0054), ACC-005 (accessible sliders), ACC-012 (sensory safety profile), PERF-004 (texture pool), PERF-009
(pipeline archive), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy), RenderGoldens
(QA-002).

## Baseline: the audit (2026-11-15, integration commit `ae8ab21a` plus `feature/fx-006`)

**No directional blur exists.** Searching the packages and the app for directional, motion blur or line blur finds
nothing in the compositor's output path. FX-001 bloom (`VisualEffects`, `BloomEffect`) has a separable Gaussian blur,
but it serves only the native spectra and blurs in both axes; it is not reused.

**The output effect chain.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (`rgba16Float`, linear premultiplied) → the FX-020 reorderable effects → FX-019 flash guard →
output pass (FX-003/FX-004/FX-005 grade, FX-002 tone map). FX-006 (chromatic split, branch `feature/fx-006`, passing
its gate) added `ChromaticSplitPass` (`cmp_chromatic`, one pooled picture), the `fx.chromatic` kind and the
`encodeOutputEffects` walk over `outputEffectOrder`. This branch merges FX-006 and follows its pattern exactly: its
own pass and shader function, its own pooled picture, its own `OutputEffectKind` case appended last.

**Shader policy.** Every compositor shader function is a module constant spliced into the one reviewed compile site in
`Compositor.init` and listed in `CompositorShaderSources.archived` (PERF-009). SHD-011/ADR-0024: no user-authored
shader, no new compile site.

**Effect chain and storage.** Scenes store reorderable effects in FX-020's optional `effects` list
(`{kind, enabled, parameters}`); settings live under `settings.<effect>.*`; Settings has one section per effect and
the Effect order screen lists every effect with an on/off switch.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: Where does the blur apply? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output, as
  a reorderable entry of the FX-020 effect chain ("Directional blur", stored kind `fx.directionalBlur`), appended after
  Chromatic split. The native spectra and projectM are unchanged. Applied to FX-007-R1, R7.
- Q: What do Angle and Radius mean? → A: Angle 0…180° is the blur's axis (the blur is symmetric, so 180° equals 0°):
  0° is horizontal, 90° vertical. Radius is how far along the axis, on each side, the blur reaches, as a fraction of
  the frame's shorter side. Applied to FX-007-R2, R3.
- Q: What does "fixed tap budget" mean? → A: Every output pixel reads exactly the same number of samples (16) for every
  radius and angle, so the cost does not grow with the radius. Applied to FX-007-R4.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: How are the 16 samples weighted? → A: Gaussian weights with a standard deviation of half the radius, normalised to
  sum to 1: a smooth streak without the hard ends of a box average, at the same cost. Applied to FX-007-R2, R4.
- Q: Where along the axis are the 16 samples placed? → A: Evenly from −radius to +radius, both ends included (spacing
  2 × radius ÷ 15); there is no separate centre sample (16 is even), so the pixel itself is reached through filtering
  between the two innermost samples. Fractional positions are filtered between neighbouring pixels. Applied to
  FX-007-R2, R4.
- Q: How are frame edges handled: clamped samples, or a fade to zero blur at the border like FX-006? → A: Clamped
  samples only: a sample past the border reads the border pixel (the edge is repeated), so nothing from outside the
  frame appears and the blur stays uniform up to the edge. Applied to FX-007-R6, Edge Cases.
- Q: Do the sensory safety profile or Reduce flashing limit the blur? → A: No cap: the blur only averages existing
  colour (each output value is a convex combination of input values), so it adds no brightness or flashing; the flash
  guard still judges the shown frame. Applied to the Assumptions.
- Q: Is the blur a global setting or a per-scene value? → A: Both, like Trails and the chromatic split: a global
  setting the visuals use, which a scene or effect-chain preset with an `fx.directionalBlur` entry overwrites when
  opened; a scene without one leaves it alone (FX-020's rule). Applied to FX-007-R10, R11.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A streak along a direction (Priority: P1)

A performer shows the Video visual and turns on Settings → Directional blur: the picture smears along one direction,
like a motion streak. A Radius slider sets how long the streak is and an Angle slider sets its direction.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a short bright vertical line at angle 0°: it spreads left and right only; nothing above or
below it changes.

**Acceptance Scenarios**:

1. **Given** Directional blur on at angle 0°, **When** a short bright vertical line is shown, **Then** it spreads only
   horizontally (rows above and below it are unchanged) and its total brightness on each row is kept.
2. **Given** angle 90°, **When** a short horizontal line is shown, **Then** it spreads only vertically.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Radius zero is exactly the picture (Priority: P1)

A performer who leaves the blur off, or sets the radius to zero, sees exactly the picture the app showed before this
feature.

**Why this priority**: it is half of the roadmap acceptance.

**Acceptance Scenarios**:

1. **Given** the blur off or on with radius 0, **When** any frame (random content) is shown, **Then** every output
   pixel is bit-identical to the output without this feature, and no extra picture memory is held.

---

### User Story 3 - Steady cost and clean edges (Priority: P2)

At any radius the blur costs the same, and the picture's border never shows colour from outside the frame.

**Acceptance Scenarios**:

1. **Given** any radius, **When** the blur runs, **Then** each output pixel combines exactly 16 samples.
2. **Given** the maximum radius at any angle, **When** a frame whose border has unique colours is shown, **Then** every
   output value lies within the range of values inside the frame.

---

### User Story 4 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Directional blur on the Effect order screen, saves a scene and an effect-chain preset, and gets
the same blur back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with the blur on, **When** it is opened, **Then** the blur's values and position are
   restored; a scene without a blur entry leaves the current blur values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened, **Then** it renders and encodes exactly as
   before.

### Edge Cases

- Radius or angle missing, not a number, NaN or out of range: off, the default, or the nearest limit; angles outside
  0…180° fold into it (the blur axis has no sign).
- A frame of 1 pixel in the blur's direction: samples clamp to the frame, so the pixel is returned.
- Non-finite picture values (NaN, ±Inf): a pixel whose own value is non-finite passes through; non-finite samples are
  skipped and the remaining weights renormalised, so they never spread.
- Transparent next to opaque: the blur averages premultiplied values, so colour never exceeds alpha.
- A size change (rotation, external display) recomputes the radius in pixels from the new shorter side.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-007-R1**: Directional blur (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo,
  Video, Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-007-R2**: With the blur active, each output pixel is a weighted average of samples taken along the blur axis
  through the pixel: 16 samples evenly spaced from −radius to +radius (both ends included), with Gaussian weights
  (standard deviation radius ÷ 2) that sum to 1; fractional positions are filtered between neighbouring pixels.
- **FX-007-R3**: Angle 0…180° (default 0°; 0° = horizontal, 90° = vertical; VoiceOver step 15°). Radius 0…2% of the
  frame's shorter side (default 0.5%; VoiceOver step 0.1%).
- **FX-007-R4**: Fixed tap budget: exactly 16 samples per output pixel for every radius and angle.
- **FX-007-R5**: At angle 0° the samples differ from the pixel only horizontally (and at 90° only vertically), so a
  blur at 0° never mixes rows and at 90° never mixes columns.
- **FX-007-R6**: Every sample position is clamped to the frame (a position past the border reads the border pixel);
  no value from outside the frame is read.
- **FX-007-R7**: The blur is active only when on and the radius (in pixels) is above zero; otherwise no pass runs and
  the output is bit-identical to the output before this feature.
- **FX-007-R8**: The blur is an FX-020 reorderable output effect (`fx.directionalBlur`); the standard order is Trails,
  Color, Chromatic split, Directional blur. The flash guard and the tone map always run after it.
- **FX-007-R9**: Settings has a "Directional blur" section: an on/off toggle, a Radius slider with a readout ("0.5%")
  and an Angle slider ("0°"), both with ACC-005 spoken values, and help text. The Effect order screen lists it with its
  own on/off switch.
- **FX-007-R10**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-007-R11**: Scenes and effect-chain presets store the blur as an `fx.directionalBlur` entry (`radius`, `angle`)
  in FX-020's `effects` list; out-of-range values are clamped and reported; scenes without it encode byte-identically.
- **FX-007-R12**: The active blur uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the blur turns inactive, the size changes or the visual
  is released.
- **FX-007-R13**: A plain-software reference of the kernel (offsets, weights, clamped positions, one pixel) exists,
  testable without a GPU (Linux), and the GPU output matches it.
- **FX-007-R14**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Directional blur setting**: on/off, radius (fraction of the shorter side), angle (degrees, 0…180).
- **Kernel**: 16 tap offsets along the axis and their weights.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-007-S1**: Off and on-with-radius-0 outputs are bit-identical to the output without the feature on random
  content, in the stack result and the screen output; no picture is held; all existing RenderGoldens pass unchanged.
- **FX-007-S2**: At angle 0°, a short vertical line spreads only horizontally: 100% of pixels in the rows outside the
  line are unchanged, and each row's total brightness is kept within 1%. At 90° the same holds with rows and columns
  swapped.
- **FX-007-S3**: The kernel has exactly 16 taps at every tested radius (including the maximum), with weights summing
  to 1.
- **FX-007-S4**: At the maximum radius, 100% of output values lie within the range of the frame's values, and every
  sample position lies inside the frame.
- **FX-007-S5**: The GPU output matches the software reference within half-float filtering precision.
- **FX-007-S6**: A scene and a preset with the blur round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-007-S7**: A user can find Directional blur, turn it on and change the radius (UI test under 30 s).
- **FX-007-S8**: The device frame rate with the blur on at the maximum radius is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002 to FX-006, FX-009, FX-019 and FX-020 are as integrated (FX-006 merged into this branch).
- The blur only averages existing colour, so it adds no brightness and needs no ACC-012 cap; the flash guard judges the
  shown frame.
- Live audio-reactive modulation of the blur is not wired.
