# Feature Specification: FX-016 Lens Distortion

**Feature Branch**: `feature/fx-016` (spec directory `306-fx-016-lens-distortion`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (FX-016-T01-T16 verified on the Mac and an own iOS 27.2 simulator; T17 `{device}` open)

**Input**: User description: "Implement FX-016 (Lens distortion) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Provide bounded barrel and pincushion warps." Acceptance, verbatim: "Zero distortion is identity;
corners remain safely sampled." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-016-R1…`, success criteria `FX-016-S1…`, tasks
`FX-016-T01…`, research decisions `FX-016-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-006 to FX-008 (chromatic split, directional and radial blur), FX-010 (echo), FX-012 (mosaic;
ADR-0110), FX-014 (edge outline; ADR-0114, the template), FX-015 (vignette, integrated in parallel), FX-019 (flash
guard), FX-020 (effect chains; ADR-0054), ACC-005 (accessible sliders), PERF-004 (texture pool), SHD-011 (shader policy;
ADR-0024), FILE-005/FILE-011 (backup and erase policy).

## Baseline: the audit (2026-11-15, commit `cfe3f6a9`)

**No lens, barrel or pincushion warp exists.** Searching the packages and the app for "barrel", "pincushion", "lens
distortion" and "lensDistortion" finds nothing.

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder` (Trails,
Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic, Edge outline) → FX-019 flash guard → output pass
(grade, FX-002 tone map). FX-014 (edge outline) is the newest instance of the pattern this feature follows: an own pass
writing one pooled picture while active, walked in `Compositor.encodeOutputEffects`, its shader a module constant spliced
into the reviewed compile site in `Compositor.init` and listed in `CompositorShaderSources.archived`; Color listed before
it is folded into FX-020's grade pass right before it; scenes store the entry only while it is on. FX-015 (vignette) is
being merged in parallel and is placed after this effect when both are integrated.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: How is the amount controlled? → A: One signed **strength** −1…+1 (default +0.3 once turned on): positive bends
  straight lines outward (barrel), negative inward (pincushion), 0 is no distortion. The strength maps to a radial
  coefficient k = 0.3 × strength, so |k| ≤ 0.3, below the 1⁄3 at which the pincushion mapping would fold back on
  itself; the warp therefore stays one-to-one (monotonic) at every strength. Applied to FX-016-R2, R3.
- Q: Which geometry? → A: Radially symmetric about the frame's middle, measured in pixels and divided by the half
  diagonal, so the corners are at radius 1 at every aspect ratio and circles stay circles. Each output pixel shows the
  picture at radius r × (1 + k r²) along the same ray (divided by the zoom below). Applied to FX-016-R3.
- Q: What is shown where barrel would read outside the picture? → A: **Zoom to fill** (on by default) enlarges a barrel
  warp just enough that each corner shows the picture's corner, so every output pixel reads inside the picture. With it
  off, the areas that would read outside the picture are transparent black, never stretched edge pixels or anything
  outside the picture. A pincushion warp never reads outside the picture, so zoom changes nothing for it. Applied to
  FX-016-R4, R5.
- Q: How is a sample taken between pixels? → A: Bilinear interpolation of the four nearest pixels, each clamped to the
  frame (no read outside the picture), with an exact read where the sample falls on a pixel centre, so zero distortion
  run through the warp returns the input bit for bit. Applied to FX-016-R5, R6.
- Q: Is there a safety cap? → A: No intensity cap: the warp moves picture content and adds no brightness or flashing;
  every output value is a weighted average (weights sum to 1) of input values or transparent black. FX-019's flash
  guard still judges the shown frame. Applied to the Edge Cases.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Is Lens distortion a global setting or a per-scene value? → A: Both, like FX-006 to FX-014: a global setting the
  visuals use, which a scene or effect-chain preset with an `fx.lensDistortion` entry overwrites when opened; a scene
  without one leaves it alone. Applied to FX-016-R9, R10.
- Q: How are the values stored? → A: Settings `settings.lensDistortion.enabled` (a real Bool, absent → off),
  `settings.lensDistortion.strength` (a number, absent or unreadable → +0.3, NaN → +0.3, out of range → nearest bound)
  and `settings.lensDistortion.zoomToFill` (a real Bool, absent or unreadable → on), each written only when changed. In
  a scene entry: `strength` (−1…1) and `zoomToFill` (0 or 1; ≥ 0.5 reads as on, like FX-014's `mode`). Applied to
  FX-016-R9, R10.
- Q: What does the Strength control show and say? → A: The readout is a signed whole percent ("+30%", "0%", "-30%");
  VoiceOver says "Strength" and ACC-005's percent value ("30 percent", "-30 percent"), one percent per swipe; the
  footer explains that positive values bulge (barrel) and negative values pinch (pincushion). Applied to FX-016-R8.
- Q: Does the Zoom to fill switch stay visible at negative strength? → A: Yes; it is shown whenever the effect is on
  and the footer says it only changes barrel (positive) values, so the stored choice survives a trip through zero.
  Applied to FX-016-R8.
- Q: What counts as "inside the picture" for a sample that lands between the last pixel centre and the frame's edge?
  → A: The picture is the rectangle from the left/top edge (0) to the right/bottom edge (width, height) in pixel units;
  a sample inside it, including the half-pixel border band, is interpolated with its taps clamped to the edge pixels; a
  sample beyond it is outside (transparent black, barrel with zoom off only). Applied to FX-016-R4, R5.

### Session 2026-11-15 (speckit-analyze)

- Finding A1 (coverage): the app changes, so FX-016-T16 also runs the privacy manifest and network-symbol checks on the
  Debug app (agent rules). Finding A2 (underspecification): the direct strength-0 run of the pass in T07 uses the
  internal `LensDistortionPass` through `@testable import Compositor`, as existing compositor tests do. Finding A3
  (inconsistency): contract C2 treats a non-finite sample position as outside; the Edge Cases now say so. No
  constitution conflicts; 13/13 requirements and 8/8 success criteria have tasks (S8 is the `{device}` task T17).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bend the picture like a lens (Priority: P1)

A performer shows the Camera visual and turns on Settings → Lens distortion: the picture bulges outward like a
wide-angle lens. Dragging the Strength slider below zero pinches it inward instead. A Zoom to fill switch decides
whether the bulged picture is enlarged to cover the frame.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: a grid picture shows its lines bowed outward at positive strength and inward at negative strength,
and the middle pixel is unchanged.

**Acceptance Scenarios**:

1. **Given** Lens distortion on at strength +100 %, **When** a picture is shown, **Then** the middle stays in place,
   content near the edges is pushed toward the middle, and every output pixel is a finite value.
2. **Given** strength −100 %, **When** a picture is shown, **Then** content near the edges is pulled outward and every
   output pixel is taken from inside the picture.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Zero distortion and safe corners (Priority: P1)

At zero strength the picture is exactly what the app showed before; at the strongest barrel and pincushion the corners
show picture content (or, with zoom off, transparent black) and never garbage.

**Acceptance Scenarios**:

1. **Given** Lens distortion on at strength 0, or off, **When** any frame is shown, **Then** the output is
   bit-identical to the output without this feature and no extra picture memory is held.
2. **Given** strength ±100 % with zoom on, **When** a frame of any aspect ratio is shown, **Then** every output pixel
   reads inside the picture, corners included.
3. **Given** strength +100 % with zoom off, **When** a frame is shown, **Then** the corner areas that would read outside
   the picture are transparent black.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Lens distortion on the Effect order screen, saves a scene and an effect-chain preset, and gets
the same warp back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Lens distortion on, **When** it is opened, **Then** its values and position are
   restored; a scene without the entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes exactly
   as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit.
- A frame smaller than 2 pixels in either direction: passes through.
- Extreme aspect ratios (a frame 2 pixels wide and thousands tall, or the reverse): the corners are still at radius 1,
  every sample stays in range and every value is finite.
- Transparent areas: premultiplied colour and alpha are interpolated together.
- A non-finite sample position (impossible for valid values, but checked) counts as outside the picture.
- Non-finite picture values: the warp only moves and averages values; FX-002 handles a non-finite value downstream.
- Sensory safety: no cap is needed (no brightness is added); the flash guard still judges the shown frame.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-016-R1**: Lens distortion (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo,
  Video, Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-016-R2**: Settings: strength −1…+1 (default +0.3, step 0.01; positive barrel, negative pincushion), zoom to fill
  (default on).
- **FX-016-R3**: For an output pixel centre at offset d from the frame's middle, r = |d| ÷ half diagonal and the sample
  is taken at the middle + d × (1 + k r²) ÷ z, with k = 0.3 × strength and z = 1 + k when zoom is on and k > 0,
  otherwise z = 1. The radial mapping r ↦ r (1 + k r²) ÷ z is strictly increasing on 0…1 for every allowed strength.
- **FX-016-R4**: The picture is the rectangle 0…width × 0…height in pixel units. With zoom on, every sample lies inside
  it for every strength and frame size; with zoom off a pincushion warp still lies inside, and a barrel sample outside
  it gives transparent black.
- **FX-016-R5**: A sample inside the picture is the bilinear interpolation of the four nearest pixels, each clamped to the
  frame; a sample exactly on a pixel centre is that pixel, bit for bit. No read ever falls outside the picture and, for
  finite input, every output value is finite.
- **FX-016-R6**: The effect is active only when on, its strength is not 0 and the frame is at least 2 × 2; otherwise no
  pass runs and the output is bit-identical to the output before this feature. Run with strength 0 the warp is the
  identity bit for bit.
- **FX-016-R7**: Lens distortion is an FX-020 reorderable output effect (`fx.lensDistortion`), appended after Edge
  outline in the standard order. Its position is honoured; the flash guard and the tone map always run after it.
- **FX-016-R8**: Settings has a "Lens distortion" section: a toggle and, while on, a Strength slider with ACC-005 spoken
  values (signed percent, readout "+30%", 1 % per swipe), a Zoom to fill switch (shown whenever the effect is on) and
  help text. The Effect order screen lists it with its
  own switch.
- **FX-016-R9**: The values (`settings.lensDistortion.enabled`, `.strength`, `.zoomToFill`) are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-016-R10**: Scenes and effect-chain presets store the effect as an `fx.lensDistortion` entry in FX-020's `effects`
  list, written only while it is on; out-of-range values are clamped and reported; scenes without it encode
  byte-identically.
- **FX-016-R11**: An active warp uses one pooled picture at output size and one full-screen pass per frame, no per-frame
  allocation; the picture returns to the pool when it turns inactive, the size changes or the visual is released.
- **FX-016-R12**: A plain-software reference of the mapping, the sample and the output exists, testable without a GPU
  (Linux), and the GPU output matches it.
- **FX-016-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Lens distortion setting**: on/off, signed strength, zoom to fill.
- **Radial mapping**: from an output radius to the picture radius it shows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-016-S1**: Strength 0 (several zoom values) and off: output bit-identical to the input on random content, with no
  pass; the warp run directly at strength 0 also returns the input bit for bit.
- **FX-016-S2**: At strength +1 and −1, with zoom on and off, over every pixel of frames at aspect ratios 1:1, 16:9, 9:16,
  1:64 and 64:1 (corners included): every sample coordinate and every interpolation tap is inside the picture (or the
  sample is reported outside and filled with transparent black, barrel with zoom off only) and every output value is
  finite.
- **FX-016-S3**: The radial mapping is strictly increasing on a dense grid of radii 0…1 at every strength step.
- **FX-016-S4**: The GPU output matches the software reference within half-float rounding; the middle pixel is
  unchanged.
- **FX-016-S5**: Off and zero strength render the golden scene exactly as no chain; a saved lens scene reloads and renders
  the same picture.
- **FX-016-S6**: A scene and a preset with Lens distortion round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-016-S7**: A user can find Lens distortion, turn it on and change the strength (UI test under 30 s); the values
  survive a relaunch (setting test with a reloaded store).
- **FX-016-S8**: The device frame rate with Lens distortion on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-006 to FX-014, FX-019 and FX-020 are as integrated; FX-015 adds the Vignette kind in parallel and
  goes after Lens distortion when both are merged.
- Live audio-reactive modulation of the strength is not wired; the warp centre is the frame's middle (no centre control).
