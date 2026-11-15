# Feature Specification: FX-018 Scanline texture

**Feature Branch**: `feature/fx-018` (spec directory `312-fx-018-scanline-texture`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (FX-018-T01-T15 verified on the Mac and an own iOS 27.2 simulator; T16 `{device}` open)

**Input**: User description: "Implement FX-018 (Scanline texture) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Apply adjustable scanline spacing and intensity." Acceptance, verbatim: "Spacing is consistent in
pixels and disabled state is identity." P3, effort S, depends on VIS-001 (integrated). Test: Metal render passes;
snapshot + shader unit + device GPU."

Identifiers in this feature carry the roadmap ID: requirements `FX-018-R1…`, success criteria `FX-018-S1…`, tasks
`FX-018-T01…`, research decisions `FX-018-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-011 (pixel sort, merged in parallel), FX-012 (mosaic, whose whole-pixel size this feature's
spacing mirrors; ADR-0110), FX-015 (vignette, the output-pass pattern followed here; ADR-0116), FX-016 (lens
distortion; ADR-0117), FX-017 (film grain, built in parallel), FX-019 (flash guard), FX-020 (effect chains; ADR-0054),
OUT-008 (grid warp), REC-001/REC-003 (capture, recording), ACC-005 (accessible sliders), PERF-004 (texture pool),
SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, commit `6f243f9d`)

**No scanline effect exists.** Searching the packages, the app, the scripts, the specs and the ADRs for "scanline"
finds only the roadmap row in `scripts/autonomous/scheduler.py`'s feature list.

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float, at the output's own pixel size) → FX-020's reorderable effects in
`OutputEffectOrder` (Trails, Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic, Edge outline, Lens
distortion, Vignette) → FX-019 flash guard → output pass (grade, FX-002 tone map), which reads the composite pixel for
pixel. The recording output (REC-003) is the same output cropped from the top-left; a still capture (REC-001) is the
composite at output size; an external display has its own compositor at its own size. OUT-008's grid warp, when on,
resamples the finished screen picture through a mesh after the output pass. FX-012 to FX-016 set the pattern for an
output effect: an own pass writing one pooled picture while active, walked in `Compositor.encodeOutputEffects`, its
shader a module constant spliced into the reviewed compile site in `Compositor.init` and listed in
`CompositorShaderSources.archived`; a non-neutral Color listed before it is folded into FX-020's grade pass; scenes
store its entry only while it is on.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: An own output pass, or a step inside the colour grade? → A: An own output pass, appended in the FX-020 chain
  ("Scanlines", stored kind `fx.scanlines`) after Vignette. A texture laid over the finished picture belongs at the end:
  later spatial effects (blurs, mosaic, lens warp) would smear or bend its lines. When FX-017's Film grain is merged it
  goes after Scanlines (grain on top of the lines, as film grain sits on top of a CRT photo); FX-011's Pixel sort stays
  between Lens distortion and Vignette. Applied to FX-018-R1, R7.
- Q: Is spacing measured in output pixels or in points or a fraction of the frame? → A: In whole pixels of the
  picture the chain works on (which is the output's own pixel size): an integer period of 2…16 pixels, default 3,
  never scaled by content scale, output size, aspect ratio, external display or recording size. Applied to FX-018-R2,
  R3.
- Q: How thick is a line? → A: A whole number of pixels, 1…15 (default 1), and always at most period − 1 so every
  period keeps at least one untouched row; a fraction of the period would give anti-aliased edges and break "consistent
  in pixels". Applied to FX-018-R2, R3.
- Q: What does a line do to a pixel? → A: It only darkens: the pixel's colour is multiplied by one factor
  f = 1 − intensity (intensity 0…100 %, default 50 %); alpha is kept; every other pixel is untouched. Applied to
  FX-018-R3, R4.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Does the first dark band start at the picture's first row, or does the pattern start with untouched rows? → A: At
  the first row: row (column) 0 is dark, so the phase is fixed to the top-left pixel and never depends on the size, the
  time or the content. Applied to FX-018-R3.
- Q: What does "consistent in pixels" mean exactly, so a test can decide it? → A: For every spacing p, thickness t and
  picture size W × H: the set of darkened rows is exactly {y : y mod p < t} (columns for vertical), every darkened
  pixel is the input × the same factor 1 − intensity, every other pixel is bit-identical, and the pitch measured from
  the rendered picture (the distance between the first rows of consecutive dark bands) equals p exactly for every
  pair of bands. Applied to FX-018-R3, S2.
- Q: Are the lines in the pixels of each output (screen, external display, recording, capture) or scaled from one
  master size? → A: In each picture's own pixels: the chain runs at the output's own pixel size (an external display
  has its own compositor at its size), a recording is the shown output cropped from the top-left (so its pixel rows
  are the screen's rows, phase unchanged) and a still capture is the composite at output size. Nothing scales the
  period. OUT-008's projection mesh resamples after the chain and bends the lines like everything else. Applied to
  FX-018-R1, R3 and the Edge Cases.
- Q: Is Scanlines a global setting or a per-scene value? → A: Both, like FX-006 to FX-016: a global setting the visuals
  use, which a scene or effect-chain preset with an `fx.scanlines` entry overwrites when opened; a scene without one
  leaves it alone. Applied to FX-018-R9, R10.
- Q: What happens to the thickness when the spacing is lowered below it? → A: The renderer always uses
  min(thickness, spacing − 1); the Settings slider for thickness ranges 1…spacing − 1 and lowering the spacing lowers a
  larger stored thickness with it, so what the slider shows is what is drawn. A scene, preset or stored value with a
  larger thickness is drawn as spacing − 1 (the renderer's rule) and the setting takes spacing − 1 when it is applied. Applied to FX-018-R2, R8.

### Session 2026-11-15 (speckit-analyze)

- Finding A1 (underspecified): at spacing 2 the thickness range is 1…1; the Thickness slider then shows 1 and is
  disabled (a slider with equal bounds is not offered). Applied to FX-018-R8. Finding A2 (coverage): T11 now asserts
  the sliders' spoken values. Finding A3 (ambiguity): S2 names the representative 4K cases (spacings 2, 3 and 16)
  within the test budget; every spacing 2…16 runs at the three smaller sizes. Finding A4 (coverage): T05 states the
  shader shape behind FX-018-R6 (one read, no loop). No constitution conflicts; every requirement has a task.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A scanline look (Priority: P1)

A performer shows the Photo visual and turns on Settings → Scanlines: thin dark horizontal lines cover the picture at
an even pitch, like an old CRT. A Spacing slider sets the pitch in pixels, a Thickness slider the line width, an
Intensity slider how dark the lines are, and an Orientation picker turns them vertical.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a uniform grey picture with scanlines on: exactly the predicted rows are darkened, all by
the same factor, the others are unchanged, and the measured pitch equals the spacing setting.

**Acceptance Scenarios**:

1. **Given** Scanlines on with spacing p, thickness t and intensity i, **When** any picture of any size is shown,
   **Then** every pixel in a row y with y mod p < t has its colour multiplied by 1 − i (alpha kept), every other pixel
   is bit-identical, and the distance between the first rows of two consecutive dark bands is exactly p pixels.
2. **Given** vertical orientation, **When** a picture is shown, **Then** the same holds for columns x.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Off is the picture (Priority: P1)

A performer who leaves Scanlines off, or sets its intensity to zero, sees exactly the picture the app showed before.

**Acceptance Scenarios**:

1. **Given** the effect off, or on at intensity 0 with any spacing, thickness and orientation, **When** any frame
   (random content) is shown, **Then** every output pixel is bit-identical to the output without this feature, and no
   extra picture memory is held.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Scanlines on the Effect order screen, saves a scene and an effect-chain preset, and gets the
same lines back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Scanlines on, **When** it is opened, **Then** its values and position are restored; a
   scene without a Scanlines entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes
   exactly as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit; spacing and thickness are
  rounded to whole pixels.
- Thickness at or above the spacing: used as spacing − 1 (at least one untouched row per period).
- Output height (width for vertical) not a multiple of the spacing: the last, partial period follows the same rule
  (its rows below t dark); the pattern never stretches to fit.
- Odd sizes, portrait and landscape, 4K: the same rule in that picture's pixels.
- A frame smaller than 2 pixels in either direction: passes through.
- Bright (HDR, above 1) values: darkened by the same factor, never raised; finite input gives finite output.
- Transparent areas: alpha kept, colour only scaled down, so premultiplied colour stays valid.
- A size change (rotation, external display): the lines restart at the new picture's top-left pixel; the pitch is
  unchanged.
- OUT-008 grid warp on: the lines are exact in the picture before the mesh; the projection mesh then bends them as it
  bends everything else.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-018-R1**: Scanlines (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-018-R2**: Controls: Spacing 2…16 pixels (default 3, step 1), Thickness 1…15 pixels (default 1, step 1, used as
  at most spacing − 1; the Settings slider ranges 1…spacing − 1 and follows a lowered spacing), Intensity 0…100 % (default 50 %, step 1 %), Orientation Horizontal (default) or Vertical.
- **FX-018-R3**: With p the spacing, t = min(thickness, p − 1) and c the pixel's row index y (column index x when
  vertical), counted from 0 at the picture's top (left) pixel, the pixel is in a line exactly when c mod p < t (so
  row or column 0 is always dark). The picture is each output's own picture at its own pixel size; nothing scales p. A pixel
  in a line has its colour multiplied by f = 1 − intensity (one value for the whole frame) and keeps its alpha; every
  other pixel is unchanged bit for bit. The factor applies to the linear premultiplied composite, before the flash guard
  and the tone map. The pattern has no time input: it is identical in every frame.
- **FX-018-R4**: Scanlines are active only when on, intensity is above zero and the frame is at least 2 × 2; otherwise
  no pass runs and the output is bit-identical to the output before this feature. Run at intensity 0 the pass would
  also be the identity (f = 1 exactly).
- **FX-018-R5**: Brightness never rises: each output colour channel lies between 0 and the input channel (for
  non-negative input), and finite input gives finite output.
- **FX-018-R6**: Each output pixel costs one exact read and a few integer and arithmetic steps, whatever the settings.
- **FX-018-R7**: Scanlines is an FX-020 reorderable output effect (`fx.scanlines`), appended after Vignette in the
  standard order. Its position is honoured; the flash guard and the tone map always run after it.
- **FX-018-R8**: Settings has a "Scanlines" section: an on/off toggle, Spacing, Thickness and Intensity sliders with
  ACC-005 spoken values (Spacing and Thickness "3 px", spoken "3 pixels"; Intensity "50%", spoken "50 percent"), an
  Orientation picker, and help text; at spacing 2 the Thickness slider shows 1 and is disabled. The Effect order screen lists it with its own on/off switch.
- **FX-018-R9**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-018-R10**: Scenes and effect-chain presets store Scanlines as an `fx.scanlines` entry (`spacing`, `thickness`,
  `intensity`, `vertical`) in FX-020's `effects` list, written only while it is on; out-of-range values are clamped
  and reported; scenes without it encode byte-identically.
- **FX-018-R11**: Active scanlines use one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the effect turns inactive, the size changes or the visual
  is released.
- **FX-018-R12**: A plain-software reference of the line rule and of the output exists, testable without a GPU
  (Linux), and the GPU output matches it within half-float rounding (exactly on unchanged pixels).
- **FX-018-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Scanlines setting**: on/off, spacing, thickness, intensity, orientation.
- **Line rule**: which rows (columns) are dark, from the spacing and thickness, anchored at pixel 0.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-018-S1**: Off, and on at intensity 0 (several spacings, thicknesses and both orientations), are bit-identical to
  the output without the feature on random content; all existing RenderGoldens pass unchanged.
- **FX-018-S2**: For every spacing 2…16 at several output sizes (odd widths and heights, portrait and landscape), and
  for representative spacings (2, 3, 16) at a 4K size, the darkened rows (columns) are exactly the predicted ones, all darkened by one factor, all other pixels
  bit-identical, and the pitch measured from the rendered picture (first row of each dark band to the next) equals the
  spacing exactly for every pair of bands.
- **FX-018-S3**: The GPU output equals the software reference within half-float rounding, and every output is finite
  for finite input, HDR values included.
- **FX-018-S4**: A scene and a preset with Scanlines round-trip to the same values and picture; a scene from before the
  feature encodes byte-identically.
- **FX-018-S5**: A user can find Scanlines, turn it on and change its controls (UI test under 30 s); the values survive
  a relaunch (setting test with a reloaded store).
- **FX-018-S6**: The device frame rate with Scanlines on, and the look on a real screen, are checked in the last stage
  (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003, FX-006 to FX-016, FX-019 and FX-020 are as integrated; FX-011 and FX-017 are built in
  parallel and add their own effect kinds; the merge keeps both (Pixel sort before Vignette, Film grain after
  Scanlines).
- Scanlines only darken and are static, so they add no brightness and no flashing; no ACC-012 cap is needed and the
  flash guard judges the shown frame.
- The roadmap's "CIColorKernel where appropriate" is not used: the compositor's Metal output-pass pattern already
  covers this per-pixel effect.
- Live audio-reactive modulation of the lines is not wired.
