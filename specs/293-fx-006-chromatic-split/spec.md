# Feature Specification: FX-006 Chromatic Split

**Feature Branch**: `feature/fx-006` (spec directory `293-fx-006-chromatic-split`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-006 (Chromatic split) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Offset color channels with edge-aware controls." Acceptance, verbatim: "Zero offset is exact
pass-through and edges stay within frame bounds." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-006-R1…`, success criteria `FX-006-S1…`, tasks
`FX-006-T01…`, research decisions `FX-006-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor;
ADR-0013), CMP-013 (render caching), CMP-014 (scene transition bus), FX-001 (bloom), FX-002 (tone map), FX-003/FX-004
(colour grade), FX-005 (contrast curves, built in parallel), FX-009 (Trails; ADR-0051), FX-019 (composite flash
guard), FX-020 (effect chains; ADR-0054), ACC-005 (accessible sliders), ACC-012 (sensory safety profile), PERF-004
(texture pool), PERF-009 (pipeline archive), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase
policy), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, commit `3b447170`)

**No channel offset exists.** Searching the packages and the app for chromatic, aberration or channel split finds
nothing in the app's own pipeline.

**Spatial post effects today.** FX-001 bloom lives in `VisualEffects` (`BloomEffect`, `PostProcessEffect`,
`EffectChain`) and serves only the native spectra. The compositor-backed visuals (Camera, Photo, Video, Text) share
CMP-001's output chain: layers → composite (`rgba16Float`, linear premultiplied) → FX-009 Trails (`TrailsPass`,
`cmp_trails`, a pooled ping-pong pair) → FX-019 flash guard → output pass (FX-003/FX-004 grade, FX-002 tone map,
× the guard's gain). FX-020 made Trails and Color reorderable (`OutputEffectOrder`, `fx.trails`, `fx.grade`); when
Color comes first and Trails are active, `OutputGradePass` (`cmp_grade_pass`, one pooled picture) grades the composite
before Trails and the output pass uses the neutral grade. That small "own pass, own pooled picture, own shader
function" pattern is the one this feature follows.

**Shader policy.** Every compositor shader function is a constant in the `Compositor` module, spliced into the one
reviewed compile site in `Compositor.init` (`CompositorShaders.library`), and listed in
`CompositorShaderSources.archived` (PERF-009's archive key). SHD-011/ADR-0024: no user-authored shader, no new compile
site.

**Effect chain and storage.** The scene's optional `effects` list (FX-020, `SceneEffectChain.swift`) stores each
reorderable effect as `{kind, enabled, parameters}`; unknown kinds are kept and ignored. The app keeps the order in
`settings.effectChain.order`, Trails in `settings.feedback.*`, Color in `settings.grade.*`; Settings has a Trails
section, a Color section and the Effect order screen (`EffectChainView`, one row with an on/off switch per effect).

**Goldens.** RenderGoldens render scenes through a real compositor (`GoldenSceneRenderer`), applying a scene's
`effects` list with `apply(effects:to:)`.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: Which channels move? → A: Red and blue move in opposite directions by the same distance; green stays. Applied
  to FX-006-R2.
- Q: Where does it apply? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output, as a
  reorderable entry of the FX-020 effect chain ("Chromatic split", stored kind `fx.chromatic`). The native spectra
  and projectM are unchanged. Applied to FX-006-R1, R7.
- Q: What does "edges stay within frame bounds" mean? → A: Every sample the effect reads lies inside the frame, and
  the split fades to zero toward the frame border, so the outermost ring of pixels is shown unchanged and no colour
  from outside the picture (or wrapped from the opposite side) appears. Applied to FX-006-R4, S2.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Should the split also shrink at high-contrast edges inside the picture to avoid harsh fringes? → A: No, not in
  this row: the fringes at contrast edges are the look users choose the effect for, the amount is capped at 2% of
  the shorter side, and the frame-edge fade already removes the only out-of-picture artefact. "Edge-aware" in this
  row means the frame-border rule (FX-006-R4). Applied to the Assumptions.
- Q: Do the sensory safety profile or Reduce flashing limit the split? → A: No cap: the split only moves existing
  colour (each output channel value is a filtered input value of the same channel), so it adds no brightness and no
  flashing by itself; the flash guard still judges the shown frame. Applied to the Assumptions and FX-006-R7.
- Q: Is the split a global setting or a per-scene value? → A: Both, like Trails: a global setting the visuals use,
  which a scene or effect-chain preset with an `fx.chromatic` entry overwrites when opened; a scene without one
  leaves it alone (FX-020's rule). Applied to FX-006-R9, R10.
- Q: What slider steps are used? → A: Amount 0…2% with a 0.1% VoiceOver step (20 steps); Angle 0…360° with a 15°
  VoiceOver step; 360° is the same direction as 0°. Applied to FX-006-R3, R8.
- Q: How are fractional distances sampled, and how exact are whole-pixel distances? → A: Filtered between the four
  nearest pixels (smooth when the amount moves); a weight of exactly zero never mixes in the neighbour, so a
  whole-pixel distance copies values exactly and a pixel with a zero split vector is passed through bit for bit.
  Applied to FX-006-R2, R5, S3.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Colour fringes on the picture (Priority: P1)

A performer shows the Photo visual and turns on Settings → Chromatic split: the red and blue parts of the picture
separate slightly, giving a lens-fringe look. An Amount slider sets how far, an Angle slider sets the direction, and
a Radial switch makes the split grow from the centre outwards instead.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a thin white vertical line with an Amount of 2 px to the right; the red copy appears 2 px
right of the line, the blue copy 2 px left, the green stays.

**Acceptance Scenarios**:

1. **Given** Chromatic split on with an amount of d pixels at angle 0°, **When** a white vertical line is shown,
   **Then** the red channel shows the line d pixels to the right, the blue channel d pixels to the left and the
   green channel in place.
2. **Given** Radial on, **When** a picture is shown, **Then** the centre is unchanged and the split grows towards
   the corners, never above the amount.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Zero is exactly the picture (Priority: P1)

A performer who leaves the effect off, or sets the amount to zero, sees exactly the picture the app showed before
this feature.

**Why this priority**: it is half of the roadmap acceptance.

**Acceptance Scenarios**:

1. **Given** the effect off or on with amount 0, **When** any frame (random content) is shown, **Then** every output
   pixel is bit-identical to the output without this feature, and no extra picture memory is held.

---

### User Story 3 - Edges stay inside the frame (Priority: P1)

At a large amount, the picture's border never shows colour pulled from outside the frame or wrapped around from the
opposite side.

**Why this priority**: the other half of the roadmap acceptance.

**Acceptance Scenarios**:

1. **Given** a frame whose border pixels each have a unique colour around a uniform interior, **When** the maximum
   amount is applied at any angle or radially, **Then** every output colour channel value comes from a pixel inside
   the frame, the outermost ring of pixels is unchanged, and the split is complete only further from the border
   than the amount.

---

### User Story 4 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Chromatic split relative to Trails and Color on the Effect order screen, saves a scene and an
effect-chain preset, and gets the same split back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with the split on, **When** it is opened, **Then** the split's values and position are
   restored; a scene without a split entry leaves the current split values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened, **Then** it renders exactly as before.

### Edge Cases

- Amount values missing, not numbers, NaN or out of range: off, or the nearest limit; angles wrap into 0…360°.
- A frame smaller than 3 pixels in either direction: the split has no interior to act on and passes through.
- Non-finite picture values (NaN, ±Inf): a pixel whose own value is non-finite passes through (FX-002 then counts
  it); a non-finite neighbour never turns a finite pixel non-finite through filtering weight zero.
- Transparent areas next to opaque ones: the shown alpha is the largest alpha of the three samples, so colour never
  exceeds its alpha (premultiplied stays valid).
- A size change (rotation, external display) recomputes the pixel distance from the new shorter side.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-006-R1**: Chromatic split (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo,
  Video, Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-006-R2**: With the split active, each output pixel takes its green from its own position (alpha per FX-006-R6), its red from the position offset by −v and its blue from the position offset by +v, where v is the
  split vector; red therefore appears moved by +v and blue by −v. Fractional positions are filtered between the four
  nearest pixels; a filter weight of exactly zero never mixes in the neighbour.
- **FX-006-R3**: The split vector is Amount × the frame's shorter side, in the direction of Angle (0° = red moves
  right, 90° = red moves up), or, with Radial on, along the line from the centre with a length growing linearly to
  Amount at the corners. Amount is 0…2% of the shorter side (default 0.5%, VoiceOver step 0.1%); Angle 0…360° (default 0°, VoiceOver
  step 15°; 360° equals 0°).
- **FX-006-R4**: Edge rule: the split vector at a pixel is scaled by min(1, distance to the nearest border ÷ the
  amount in pixels); every sample position is additionally clamped to the frame. The outermost pixel ring is
  therefore unchanged and no sample lies outside the frame.
- **FX-006-R5**: The split is active only when on and the amount (in pixels) is above zero; otherwise no pass runs
  and the output is bit-identical to the output before this feature. A pixel whose split vector is zero (border,
  radial centre) is passed through unchanged.
- **FX-006-R6**: The shown alpha is the largest alpha of the three samples; non-finite samples follow the edge cases.
- **FX-006-R7**: The split is an FX-020 reorderable output effect (`fx.chromatic`); the standard order is Trails,
  Color, Chromatic split. Its position is honoured relative to Trails and Color; the flash guard and the tone map
  always run after it.
- **FX-006-R8**: Settings has a "Chromatic split" section: an on/off toggle, an Amount slider with a readout
  ("0.5%"), an Angle slider ("0°"), both with ACC-005 spoken values, a Radial switch, and help text. The Effect order
  screen lists it with its own on/off switch.
- **FX-006-R9**: The values are saved on the device, restored at launch, included in library backups, erased with
  the other settings, checked on read, and removed by the UI-test reset.
- **FX-006-R10**: Scenes and effect-chain presets store the split as an `fx.chromatic` entry (`amount`, `angle`,
  `radial`) in FX-020's `effects` list; out-of-range values are clamped and reported; scenes without it encode
  byte-identically.
- **FX-006-R11**: Active split uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the split turns inactive, the size changes or the
  visual is released.
- **FX-006-R12**: A plain-software reference of the sample-position maths (vector, edge fade, clamp) exists,
  testable without a GPU (Linux), and the GPU output matches it.
- **FX-006-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to
  the pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Chromatic split setting**: on/off, amount (fraction of the shorter side), angle (degrees), radial (on/off).
- **Split vector**: the per-pixel offset in pixels after the edge fade.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-006-S1**: Off and on-with-zero-amount outputs are bit-identical to the output without the feature on random
  content, in the stack result and the screen output; all existing RenderGoldens pass unchanged.
- **FX-006-S2**: At the maximum amount (linear at four angles and radial), 100% of output channel values match a
  value present inside the frame, 100% of border-ring pixels are unchanged, and no interior pixel shows a border
  colour except within the fade band.
- **FX-006-S3**: On a line test pattern the red and blue copies are found exactly at ±d pixels (d integer).
- **FX-006-S4**: The GPU output matches the software reference within half-float precision.
- **FX-006-S5**: A scene and a preset with the split round-trip to the same values; a scene from before the
  feature encodes byte-identically.
- **FX-006-S6**: A user can find Chromatic split, turn it on and change the amount (UI test under 30 s); the values
  survive a relaunch (setting test with a reloaded store, as FX-009 does, keeping the UI test short).
- **FX-006-S7**: The device frame rate with the split on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003/FX-004, FX-009, FX-019 and FX-020 are as integrated; FX-005 changes only the
  per-pixel grade and does not interact.
- The split moves colour but adds no brightness, so it needs no ACC-012 cap; the flash guard judges the shown frame.
- Contrast-aware softening at high-contrast picture edges is not part of this row (see research).
- Live audio-reactive modulation of the split is not wired.
