# Feature Specification: FX-008 Radial Blur

**Feature Branch**: `feature/fx-008` (spec directory `296-fx-008-radial-blur`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-008 (Radial blur) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Blur outward from an adjustable focus point." Acceptance, verbatim: "Center remains stable while
outer test points spread predictably." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-008-R1…`, success criteria `FX-008-S1…`, tasks
`FX-008-T01…`, research decisions `FX-008-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-003/FX-004 (colour grade), FX-006 (chromatic split; ADR-0104), FX-007 (directional blur, built in
parallel), FX-009 (Trails), FX-019 (flash guard), FX-020 (effect chains; ADR-0054), ACC-005 (accessible sliders),
ACC-012 (sensory safety profile), PERF-004 (texture pool), PERF-009 (pipeline archive), SHD-011 (shader policy;
ADR-0024), FILE-005/FILE-011 (backup and erase policy), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, commit `d9f4bd6d`)

**No radial or zoom blur exists in the compositor.** Searching the packages and the app for radial blur, zoom blur or
focus point finds only FX-006's radial *split* (a channel offset, not a blur) and FX-001's bloom (native spectra only).

**Spatial output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output
chain: layers → composite (`rgba16Float`, linear premultiplied) → FX-020's reorderable effects in
`OutputEffectOrder` (FX-009 Trails, FX-003 Color, FX-006 Chromatic split) → FX-019 flash guard → output pass (grade,
FX-002 tone map). FX-006 added the pattern this feature follows: an own pass (`ChromaticSplitPass`, `cmp_chromatic`)
writing one pooled picture while active, walked in `Compositor.encodeOutputEffects`, its shader a module constant
spliced into the reviewed compile site in `Compositor.init` and listed in `CompositorShaderSources.archived`; a
non-neutral Color listed before an active spatial effect is folded into FX-020's grade pass right before it.

**Storage.** FX-020's optional scene `effects` list stores reorderable effects as `{kind, enabled, parameters}`;
FX-006 stores `fx.chromatic` only when on (a disabled split counts as default, so older scenes encode byte-identically).
The app keeps one global setting per effect (`settings.chromatic.*`), a Settings section, and a row on the Effect order
screen (`EffectChainView`).

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: What kind of blur is "outward from a focus point"? → A: A zoom (radial) blur: every pixel is averaged with
  samples on the straight line from itself towards the focus point, so detail smears along lines through the focus
  and a bright point becomes a streak pointing away from the focus. Applied to FX-008-R2.
- Q: What does "center remains stable" mean? → A: The pixel at the focus point is not blurred at all (shown bit for
  bit when the focus falls on a pixel), and the blur grows smoothly from zero with distance from the focus. Applied to
  FX-008-R3, S2.
- Q: What does "outer test points spread predictably" mean? → A: A single bright point at distance d from the focus
  becomes a streak that starts at the point and ends at d × (1 + Strength) from the focus, on the line from the focus
  through the point: its length is d × Strength, linear in both. Applied to FX-008-R3, S3.
- Q: Where does it apply? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output, as a
  reorderable entry of the FX-020 effect chain ("Radial blur", stored kind `fx.radialBlur`), appended after FX-006's
  split. The native spectra and projectM are unchanged. Applied to FX-008-R1, R7.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zoom blur towards a point (Priority: P1)

A performer shows the Photo visual and turns on Settings → Radial blur: the picture smears outward from its centre,
like a zoom during a long exposure. A Strength slider sets how far the smear reaches; Focus X and Focus Y sliders move
the point the blur radiates from.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show small bright dots at the focus and at several distances from it; the focus dot stays sharp
and each outer dot becomes a streak pointing away from the focus, its length growing with its distance.

**Acceptance Scenarios**:

1. **Given** Radial blur on at Strength s with the focus at the centre, **When** a dot at distance d right of the
   focus is shown, **Then** it appears as a streak along its row from d to d × (1 + s) (within one pixel), and the
   dot at the focus is unchanged.
2. **Given** the focus moved to 25% across, **When** the same pattern is shown around the new focus, **Then** the dot
   at the new focus stays sharp and streaks radiate from it.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Off is exactly the picture (Priority: P1)

A performer who leaves the effect off, or sets the strength to zero, sees exactly the picture the app showed before
this feature.

**Acceptance Scenarios**:

1. **Given** the effect off or on with strength 0, **When** any frame (random content) is shown, **Then** every output
   pixel is bit-identical to the output without this feature, and no extra picture memory is held.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Radial blur relative to Trails, Color and Chromatic split on the Effect order screen, saves a
scene and an effect-chain preset, and gets the same blur back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with the blur on, **When** it is opened, **Then** the blur's values and position are
   restored; a scene without a blur entry leaves the current blur values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes
   exactly as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit.
- Focus at a corner or an edge: still every sample lies inside the frame; the blur radiates from that corner.
- A frame smaller than 2 pixels in either direction: passes through.
- Non-finite picture values: a pixel whose own value is non-finite passes through (FX-002 then counts it).
- Transparent areas: colour and alpha are averaged together, so premultiplied colour never exceeds its alpha.
- A size change (rotation, external display) maps the normalized focus to the new size.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-008-R1**: Radial blur (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-008-R2**: With the blur active, each output pixel is the average of a fixed number of samples (16) taken on the
  segment from the pixel towards the focus point; sample k (k = 0…15) lies at F + (P − F) ÷ (1 + Strength × k ÷ 15),
  F the focus and P the pixel. Sample 0 is the pixel itself. Fractional positions are filtered between the four
  nearest pixels. Every sample position is clamped to the frame.
- **FX-008-R3**: Consequences that the tests check: the pixel at the focus has zero spread (shown unchanged); a
  pixel's spread is |P − F| × Strength ÷ (1 + Strength), linear in its distance; a bright point at distance d spreads
  outward along the ray from the focus over d × Strength pixels.
- **FX-008-R4**: Strength is 0…25% (default 10%, VoiceOver step 1%). Focus X and Focus Y are 0…100% of the frame's
  width and height (0 = left/top, default 50%, VoiceOver step 5%); the focus maps to the pixel position
  (X × (width − 1), Y × (height − 1)).
- **FX-008-R5**: The blur is active only when on, the strength is above zero and the frame is at least 2 × 2;
  otherwise no pass runs and the output is bit-identical to the output before this feature. A pixel with zero spread
  is passed through unchanged.
- **FX-008-R6**: The tap count is fixed (16) whatever the strength, distance or frame size: the cost per pixel is
  constant.
- **FX-008-R7**: The blur is an FX-020 reorderable output effect (`fx.radialBlur`); the standard order is Trails,
  Color, Chromatic split, Radial blur. Its position is honoured; the flash guard and the tone map always run after it.
- **FX-008-R8**: Settings has a "Radial blur" section: an on/off toggle, a Strength slider ("10%"), Focus X and
  Focus Y sliders ("50%"), with ACC-005 spoken values, and help text. The Effect order screen lists it with its own
  on/off switch.
- **FX-008-R9**: The values are saved on the device, restored at launch, included in library backups, erased with
  the other settings, checked on read, and removed by the UI-test reset.
- **FX-008-R10**: Scenes and effect-chain presets store the blur as an `fx.radialBlur` entry (`strength`, `focusX`,
  `focusY`) in FX-020's `effects` list, written only while the blur is on; out-of-range values are clamped and
  reported; scenes without it encode byte-identically.
- **FX-008-R11**: An active blur uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when the blur turns inactive, the size changes or the visual
  is released.
- **FX-008-R12**: A plain-software reference of the sample positions and the blurred pixel exists, testable without a
  GPU (Linux), and the GPU output matches it.
- **FX-008-R13**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Radial blur setting**: on/off, strength (fraction), focus X and focus Y (fractions of the frame).
- **Sample positions**: the 16 points per pixel on the segment towards the focus.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-008-S1**: Off and on-with-zero-strength outputs are bit-identical to the output without the feature on random
  content, in the stack result and the screen output; all existing RenderGoldens pass unchanged.
- **FX-008-S2**: With a dot pattern at the maximum strength, the focus pixel is bit-identical to the input, for the
  centred and an off-centre focus.
- **FX-008-S3**: Each outer dot (at least three distances, four directions) shows a streak whose outer end lies within
  one pixel of d × (1 + Strength) from the focus and whose inner end is the dot itself, on the dot's ray from the focus.
- **FX-008-S4**: The GPU output matches the software reference within 1/128 per channel, and no sample position lies
  outside the frame (software check over every pixel, including a focus at a corner).
- **FX-008-S5**: A scene and a preset with the blur round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-008-S6**: A user can find Radial blur, turn it on and change the strength (UI test under 30 s); the values
  survive a relaunch (setting test with a reloaded store).
- **FX-008-S7**: The device frame rate with the blur on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003/FX-004, FX-006, FX-009, FX-019 and FX-020 are as integrated; FX-007 (directional
  blur) is built in parallel and adds its own effect kind; the merge reconciles the order.
- The blur averages existing colour, adding no brightness, so it needs no ACC-012 cap; the flash guard judges the
  shown frame.
- Live audio-reactive modulation of the strength or focus is not wired.
