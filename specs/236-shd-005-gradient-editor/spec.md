# Feature Specification: SHD-005 Gradient Editor

**Feature Branch**: `feature/shd-005` (spec directory `236-shd-005-gradient-editor`)
**Created**: 2026-11-14
**Status**: Draft
**Input**: User description: "Implement SHD-005 (Gradient editor) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Edit multi-stop gradients with interpolation and alpha." Acceptance, verbatim:
"Gradient sample at each stop matches stored color." P1, depends on SHD-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`SHD-005-R1…`, success criteria `SHD-005-S1…`, tasks `SHD-005-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `c035898f`)

| Area | Today | Gap for this row |
|---|---|---|
| Gradient material (SHD-001, SHD-003, SHD-004) | `material.gradient` ("Gradient Field") blends two colour parameters (`colorA`, `colorB`) with a smoothstep along a rotating axis or by radius; parameters are MOD-001 descriptors from SHD-003 metadata (6 of 8 uniform slots used); one variant. The app keeps material layers in scenes but does not draw them; their settings are shown read-only. | Two colours only; no stops, no alpha, no interpolation choice. |
| Gradient masks (CMP-008) | `LayerGradientMask`: 2…8 stops of (position, alpha), stable-sorted, piecewise-linear evaluation (first stop's value before it, last stop's after it, equal positions give a hard step), CPU reference + shader loop, inspector with stop rows. | Alpha only, no colour; the evaluation rule is reusable. |
| Palettes (UIX-011) | `ColorPalette` (2…8 opaque sRGB colours, style gradient or swatches) in `palettes.json` (version 1, canonical writer, lenient reader); `PaletteRamp` blends evenly spaced stops in linear light; Settings › Palette editor with system colour picker, named colours, add/remove, VoiceOver names. Palettes colour every native visual (spectra, oscilloscope, Lissajous, radial waveform, beat rings, mandala, particles). | Stops are evenly spaced and opaque, interpolation is fixed. |
| Parameter registry (MOD-001) | Scalars, colours, enums; at most 8 slots per material. | A stop list does not fit the descriptor model. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where does the editor live so that it is actually usable? → A: In the existing palette editor (Settings ›
  Palette › a user palette), which colours every native visual the app draws today. A gradient-style palette
  gains, per colour, a position and an alpha, plus an interpolation choice for the whole palette. Material layers
  are not drawn by the app in this version, so an editor there would change nothing visible (SHD-003's rule).
  The same gradient is evaluated on the GPU by the Gradient Field material when a gradient is set on its layer
  (the compositor path used by goldens and future material drawing), from one shared definition.
- Q: How is a gradient stored? → A: In the palette file, as optional per-palette fields written only when they
  differ from today's behaviour: `positions` (integers 0…1000, thousandths, non-decreasing, one per colour),
  `alphas` (integers 0…255, one per colour) and `interpolation` (`"srgb"` or `"step"`; absent = linear light).
  No version bump: palettes without the fields read and draw exactly as before, and an older app reading a
  newer file ignores the fields (it draws evenly spaced opaque stops; an edit there drops them). A field that is
  malformed (wrong count, out of range, decreasing, unknown mode) makes the entry damaged (dropped and counted),
  the file's existing rule. Integer storage keeps canonical bytes stable and makes "the stored colour" exact.
- Q: Which interpolation modes? → A: Three: Smooth (linear light, the default and today's behaviour), sRGB
  (blend of the encoded values, as many design tools do) and Step (each stop's colour holds until the next
  stop). Alpha blends linearly (held in Step). Swatches style is unchanged and ignores positions, alphas and mode.
- Q: How are stops moved, and can they cross? → A: A stop's position is clamped between its neighbours'
  positions, so list order is always gradient order and rows never jump under the finger. Equal neighbouring
  positions give a hard edge (the later stop wins, CMP-008's rule). Added colours copy the last stop (colour,
  alpha) at position 1000; removing keeps the others' positions.
- Q: What does alpha mean for the native visuals and the material? → A: The material outputs premultiplied
  colour with the stop's alpha, so lower layers show through. Native visuals draw on black with their own
  per-visual alpha, so a palette's alpha fades the colour toward the background (colour × alpha, opaque); this
  keeps every visual's existing blending and flash-safety behaviour.
- Q: How is the GPU gradient fed? → A: A small fixed uniform block (up to 8 stops: linear and encoded colour,
  alpha, position; count; mode) bound next to the material's existing uniforms; the evaluation code is part of
  the reviewed module shader constant (SHD-011), no new Metal source file. With no gradient set the Gradient
  Field draws exactly as before (goldens unchanged). With a gradient, the axis maps linearly (no smoothstep):
  t = 0.5 + p·direction across the shorter side (or 2·radius for Radial), clamped to 0…1.
- Q: How fine are the controls, and how is the result previewed? → A: Position and alpha sliders move in steps
  of 1 % (VoiceOver adjusts by 1 % per swipe; stored values stay in thousandths and 0…255 so a 1 % step is exact
  to the stored precision after rounding); the preview strip draws the stops at their positions over black with
  the same colour × alpha the native visuals use (Step shows hard bands). Rows read "Stop i of n".
- Q: Are stop edits undoable scene edits? → A: No; like every palette edit (UIX-011) they are library edits saved
  at once, not scene edits, so they are not in scene undo. The scene's palette link is unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shape a gradient with positioned, translucent stops (Priority: P1)

In the palette editor, someone picks a gradient-style palette, moves the middle stop toward one end, lowers
the alpha of the last stop, and switches interpolation to Step. The preview strip and the visual update at once;
the palette is saved and survives relaunch and backup.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: A UI test opens a new palette, changes stop 2's position with its slider and checks the
value read back; unit tests cover editing, limits and the file round trip.

**Acceptance Scenarios**:

1. **Given** a user gradient palette, **When** stop 2's position is moved to 30 %, **Then** the row reads
   "Position 30 percent", the saved file holds `positions` with 300, and the native visual's colours follow.
2. **Given** a palette, **When** a stop is dragged past its neighbour, **Then** it stops at the neighbour's
   position.
3. **Given** a palette without the new fields, **When** it is loaded and saved again, **Then** its bytes are
   unchanged and it draws exactly as before.

### User Story 2 - The drawn gradient honours the stored stops (Priority: P1)

Wherever the gradient is drawn (on the GPU by the Gradient Field material, on the CPU for native visuals), the
colour at each stop's position is that stop's stored colour and alpha, and between stops it follows the chosen
interpolation.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: A GPU readback renders a gradient whose stops sit exactly on pixel centres and compares
each stop's pixel with the stored colour and alpha for every interpolation mode; a CPU reference is compared
with the GPU between stops; a golden signature pins the picture.

**Acceptance Scenarios**:

1. **Given** a 4-stop gradient with alphas below 1, **When** the material draws it in each mode, **Then** each
   stop's pixel, encoded to 8-bit sRGB, equals the stored colour within 1/255 per channel and its alpha the
   stored alpha within 1/255.
2. **Given** the same gradient, **When** pixels between stops are compared with the CPU reference, **Then** they
   agree within 2/255.

### User Story 3 - Accessible stop editing (Priority: P2)

A VoiceOver user hears each stop as "Stop 2 of 4, coral, position 30 percent, alpha 100 percent", adjusts
position and alpha by swiping up or down, and chooses interpolation from a labelled picker.

**Why this priority**: Constitution accessibility rules apply to every new control.

**Independent Test**: The sliders use the shared accessible-parameter helper (ACC-005); a UI test reads the
labels and values.

### Edge Cases

- Two stops at the same position: hard edge, later stop wins; the sample at that position is the later stop.
- Positions 0 and 1000 at the ends: outside the first/last stop the gradient holds that stop's colour.
- Step mode exactly at a stop: the stop's own colour (the segment starts there).
- Alpha 0: the material outputs transparent; native visuals draw black.
- A built-in palette: read-only, duplicate to edit (unchanged rule).
- Swatches style: positions, alphas and mode are hidden and ignored but kept.
- Reduce flashing and the composite flash guard still apply to everything drawn.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-005-R1**: A gradient MUST have 2…8 stops, each with a position 0…1 (stored in thousandths), an 8-bit sRGB
  colour and an alpha 0…1 (stored 0…255), positions non-decreasing in stop order, and one interpolation mode of
  Smooth (linear light), sRGB or Step.
- **SHD-005-R2**: Evaluation at t: before the first stop its colour, at or after the last stop its colour, else
  the segment [stop i, stop i+1] containing t with fraction f = (t − pᵢ)/(pᵢ₊₁ − pᵢ): Smooth lerps linear colour,
  sRGB lerps encoded colour then decodes, Step holds stop i; alpha lerps (held in Step). At t equal to a stop's
  position the result is that stop exactly (the later one for equal positions).
- **SHD-005-R3**: A user palette MUST store positions, alphas and mode as optional fields, written only when they
  differ from the defaults (even spacing, alpha 255, Smooth); without them every palette behaves and encodes as
  before. Malformed fields make the entry damaged (dropped and counted). No file version bump.
- **SHD-005-R4**: Editing MUST offer, for a gradient-style user palette: set a stop's position (clamped between
  neighbours), set its alpha, set the interpolation; adding and removing colours keep positions and alphas in
  step; duplicate copies them. Built-ins stay read-only.
- **SHD-005-R5**: Native visuals MUST draw a palette that has stop detail with the R2 evaluation (colour ×
  alpha, opaque); palettes without detail MUST draw exactly as before.
- **SHD-005-R6**: The Gradient Field material layer MUST accept an optional gradient and evaluate it on the GPU
  with the R2 rule from a fixed uniform block; without one it MUST draw exactly as before. The code is part of the
  reviewed module shader constant (SHD-011).
- **SHD-005-R7**: The editor's position and alpha sliders MUST use the ACC-005 accessible-parameter helper, and
  each stop MUST have a VoiceOver label naming its index, count, colour name, position and alpha.
- **SHD-005-R8**: No new UserDefaults keys; palettes stay in the palette file (backups and erase unchanged).

### Key Entities

- **Gradient stop**: position, colour, alpha.
- **Gradient**: 2…8 stops and an interpolation mode.
- **Palette stop detail**: the optional stored positions, alphas and mode of a user palette.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-005-S1**: For each of the three modes, the GPU sample at every stop matches the stored colour (8-bit sRGB)
  and alpha within 1/255 per channel (the acceptance).
- **SHD-005-S2**: Between stops, GPU and CPU reference agree within 2/255 per channel.
- **SHD-005-S3**: Palettes without stop detail encode byte-identically and draw identically to before (existing
  palette and material goldens unchanged).
- **SHD-005-S4**: Someone can move a stop, change its alpha and the mode in under 30 seconds; the UI test editing a
  stop runs in under 30 s.
- **SHD-005-S5**: Unit tests under 10 s each, package suites under one minute.

## Assumptions

- The app draws native visuals, not material layers, in this version; the GPU path is proven in the package and
  used by the compositor's material layer.
- No device task is needed for correctness (the GPU readback runs on the Mac's GPU); a look on D1 is a `{device}`
  task.
