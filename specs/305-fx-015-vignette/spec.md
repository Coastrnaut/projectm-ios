# Feature Specification: FX-015 Vignette

**Feature Branch**: `feature/fx-015` (spec directory `305-fx-015-vignette`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-015 (Vignette) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior,
verbatim: "Apply radial falloff with center and softness controls." Acceptance, verbatim: "Center brightness stays
unchanged at zero intensity." P2, effort S, depends on VIS-001 (integrated). Test: Metal render passes; snapshot +
shader unit + device GPU."

Identifiers in this feature carry the roadmap ID: requirements `FX-015-R1…`, success criteria `FX-015-S1…`, tasks
`FX-015-T01…`, research decisions `FX-015-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-003 (colour grade), FX-008 (radial blur, whose focus control this feature's centre mirrors;
ADR-0107), FX-012 (mosaic, the output-pass pattern followed here; ADR-0110), FX-013 (posterization), FX-014 (edge
outline, built in parallel), FX-019 (flash guard), FX-020 (effect chains; ADR-0054), ACC-005 (accessible sliders),
PERF-004 (texture pool), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy), RenderGoldens
(QA-002).

## Baseline: the audit (2026-11-15, commit `3e1376fb`)

**No vignette exists.** Searching the packages, the app, the scripts, the specs and the ADRs for "vignette" finds
nothing.

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder` (Trails,
Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic; FX-014's Edge outline is being added in
parallel) → FX-019 flash guard → output pass (grade, FX-002 tone map). FX-006 to FX-012 set the pattern for a
position-dependent effect: an own pass writing one pooled picture while active, walked in
`Compositor.encodeOutputEffects`, its shader a module constant spliced into the reviewed compile site in
`Compositor.init` and listed in `CompositorShaderSources.archived`; a non-neutral Color listed before it is folded into
FX-020's grade pass; scenes store its entry only while it is on. FX-008's radial blur already has a focus control
(fractions of the frame, 0…1, default 0.5) that this feature's centre control mirrors.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: An output pass of its own, or a step inside the per-pixel colour grade (`cmp_grade_at`, made position-aware by
  FX-013)? → A: An own output pass, appended last in the FX-020 chain ("Vignette", stored kind `fx.vignette`). A
  vignette is a framing effect: placed last, later spatial effects (blurs, split, mosaic) do not smear its edge; it
  can be reordered and switched off on the Effect order screen like its siblings; and the grade block, shared by every
  output path, stays untouched. Applied to FX-015-R1, R7.
- Q: What does the falloff do to a pixel? → A: It only darkens: the pixel's colour is multiplied by
  1 − intensity × w, where w (0…1) is the falloff weight at the pixel; alpha is kept. Brightness never rises, so
  premultiplied colour stays valid and no safety cap is needed. Applied to FX-015-R3, R4.
- Q: What shape is the falloff? → A: An ellipse that follows the frame's aspect: distance is measured in half-widths
  and half-heights and scaled so the frame's corners are at distance 1 from the frame's middle. Every edge of a
  portrait or landscape picture darkens alike. Applied to FX-015-R3.
- Q: What do softness and the centre control? → A: Softness (10…90 %, default 50 %) is the width of the falloff band:
  the band starts at distance 1 − softness and ends at distance 1, with a smooth (smoothstep) curve. Inside distance
  1 − softness (at least 0.1) nothing changes. The centre is the middle of the ellipse, as fractions of the width and
  height (0…1, default 0.5, 0.5), like FX-008's focus. Applied to FX-015-R2, R3.
- Q: What does zero intensity do? → A: Intensity is 0…100 % (default 50 %). At zero (or off) no pass runs: every
  output pixel is bit-identical to the output without this feature. Applied to FX-015-R4.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Is the darkening factor applied to linear light or to the encoded (sRGB) value? → A: To the linear premultiplied
  composite, where every output effect works; a factor in linear light is how lens falloff behaves, and the tone map
  and display encoding run after it as for every other effect. Applied to FX-015-R3.
- Q: How are the centre coordinates measured? → A: As continuous fractions of the frame: 0 is the left (top) edge and
  1 the right (bottom) edge, so the centre in pixels is (centerX × W, centerY × H) and pixel centres sit at
  (x + ½, y + ½). At 0.5 this is the frame's exact middle on any size, the same point as FX-008's default focus.
  Applied to FX-015-R3.
- Q: Is Vignette a global setting or a per-scene value? → A: Both, like FX-006 to FX-012: a global setting the visuals
  use, which a scene or effect-chain preset with an `fx.vignette` entry overwrites when opened; a scene without one
  leaves it alone. Applied to FX-015-R9, R10.
- Q: Do the sensory safety profile or Reduce flashing limit the vignette? → A: No cap: it only darkens and never adds
  brightness; the flash guard still judges the shown frame. Applied to the Assumptions.
- Q: What do the sliders show and VoiceOver say? → A: Intensity and Softness as whole percentages ("50 %", spoken
  "50 percent"), Center X and Center Y as two-decimal fractions ("0.50"), each through ACC-005's accessible slider
  with the steps of FX-015-R2. Applied to FX-015-R8.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Frame the picture (Priority: P1)

A performer shows the Photo visual and turns on Settings → Vignette: the picture's edges and corners darken smoothly
while its middle stays as it was. An Intensity slider sets how dark the corners get, a Softness slider how wide the
transition is, and Center X / Center Y sliders move the bright middle.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a uniform grey picture with the vignette on: the middle pixel is unchanged, brightness
falls monotonically from the centre to every corner, and moving the centre moves the brightest point.

**Acceptance Scenarios**:

1. **Given** Vignette on at intensity 50 % and softness 50 %, **When** a uniform picture is shown, **Then** the pixel at
   the centre keeps its exact value and brightness never rises along any line from the centre to a corner, and the
   corners are darker than the centre.
2. **Given** the centre moved to (0.25, 0.5), **When** a uniform picture is shown, **Then** the brightest region is
   around a quarter of the width from the left, and the right edge is darker than the left edge.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Zero intensity is the picture (Priority: P1)

A performer who leaves Vignette off, or sets its intensity to zero, sees exactly the picture the app showed before:
the centre and every other pixel unchanged.

**Acceptance Scenarios**:

1. **Given** the effect off, or on at intensity 0 with any softness and centre, **When** any frame (random content) is
   shown, **Then** every output pixel, centre and corners included, is bit-identical to the output without this
   feature, and no extra picture memory is held.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Vignette on the Effect order screen, saves a scene and an effect-chain preset, and gets the same
vignette back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Vignette on, **When** it is opened, **Then** its values and position are restored; a
   scene without a Vignette entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes
   exactly as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit.
- Centre at an edge or corner (0 or 1): the far side of the frame lies beyond distance 1 and is fully darkened by the
  intensity; the centre itself is unchanged.
- A frame smaller than 2 pixels in either direction: passes through.
- Non-finite picture values: multiplied like any other value (FX-002 handles them downstream); finite input gives
  finite output.
- Bright (HDR, above 1) values: darkened by the same factor, never raised.
- Transparent areas: alpha is kept and colour only scaled down, so premultiplied colour stays valid.
- A size change (rotation, external display): the ellipse follows the new frame; the centre stays at the same fractions.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-015-R1**: Vignette (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-015-R2**: Controls: Intensity 0…100 % (default 50 %, VoiceOver step 1 %), Softness 10…90 % (default 50 %, step
  5 %), Center X and Center Y 0…1 of the width and height (default 0.5, step 0.05).
- **FX-015-R3**: For the pixel centre P, with C the centre in pixels and (W, H) the frame size, the distance is
  d = |((P − C) ÷ (W ÷ 2, H ÷ 2))| ÷ √2; with inner = 1 − softness, t = clamp((d − inner) ÷ softness, 0, 1) and the
  weight w = t² × (3 − 2t); the output colour is the input colour × (1 − intensity × w) and the output alpha is the
  input alpha. P and C are in pixels: pixel (x, y) has centre (x + ½, y + ½) and C = (centerX × W, centerY × H). The
  factor applies to the linear premultiplied composite, before the flash guard and the tone map.
- **FX-015-R4**: The vignette is active only when on, intensity is above zero and the frame is at least 2 × 2;
  otherwise no pass runs and the output is bit-identical to the output before this feature. Where w = 0 (every pixel
  within distance 1 − softness of the centre, the centre always) the pixel is exactly unchanged at any intensity.
- **FX-015-R5**: Brightness never rises: each output colour channel lies between 0 and the input channel (for
  non-negative input), and finite input gives finite output.
- **FX-015-R6**: Each output pixel costs one exact read and a few arithmetic steps, whatever the settings.
- **FX-015-R7**: Vignette is an FX-020 reorderable output effect (`fx.vignette`), appended last in the standard order
  (after Mosaic, and after FX-014's Edge outline once both are merged). Its position is honoured; the flash guard and
  the tone map always run after it.
- **FX-015-R8**: Settings has a "Vignette" section: an on/off toggle, Intensity, Softness, Center X and Center Y
  sliders with ACC-005 spoken values (Intensity and Softness "50 %", spoken "50 percent"; Center X and Y "0.50"), and
  help text. The Effect order screen lists it with its own on/off switch.
- **FX-015-R9**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-015-R10**: Scenes and effect-chain presets store Vignette as an `fx.vignette` entry (`intensity`, `softness`,
  `centerX`, `centerY`) in FX-020's `effects` list, written only while it is on; out-of-range values are clamped and
  reported; scenes without it encode byte-identically.
- **FX-015-R11**: An active vignette uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the vignette turns inactive, the size changes or the
  visual is released.
- **FX-015-R12**: A plain-software reference of the weight and of the output exists, testable without a GPU (Linux),
  and the GPU output matches it within half-float rounding.
- **FX-015-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Vignette setting**: on/off, intensity, softness, centre (x, y).
- **Falloff weight**: 0 inside the clear core, rising smoothly to 1 at distance 1 and beyond.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-015-S1**: Off, and on at intensity 0 (several softness and centre values), are bit-identical to the output
  without the feature on random content, at the centre and the corners and everywhere else; all existing RenderGoldens
  pass unchanged.
- **FX-015-S2**: At any intensity and softness, the centre pixel keeps its exact value; on a uniform picture the
  brightness never rises from the centre to each corner, and the corners are darker than the centre for any intensity
  above 0.
- **FX-015-S3**: Moving the centre moves the brightest point of a uniform picture to the pixel nearest the new centre.
- **FX-015-S4**: The GPU output equals the software reference within half-float rounding, and every output is finite
  for finite input, HDR values included.
- **FX-015-S5**: A scene and a preset with Vignette round-trip to the same values and picture; a scene from before the
  feature encodes byte-identically.
- **FX-015-S6**: A user can find Vignette, turn it on and change its sliders (UI test under 30 s); the values survive a
  relaunch (setting test with a reloaded store).
- **FX-015-S7**: The device frame rate with Vignette on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003, FX-006 to FX-013, FX-019 and FX-020 are as integrated; FX-014 is built in parallel
  and adds its own effect kind; the merge reconciles the order by keeping both (Vignette last).
- The vignette only darkens, adding no brightness; it needs no ACC-012 cap and the flash guard judges the shown frame.
- The roadmap's "CIColorKernel where appropriate" is not used: the compositor's Metal output-pass pattern already
  covers this per-pixel effect.
- Live audio-reactive modulation of the vignette is not wired.
