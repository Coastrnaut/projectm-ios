# Feature Specification: CMP-008 Gradient Masks

**Feature Branch**: `feature/cmp-008` (spec directory `207-cmp-008-gradient-masks`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CMP-008-T01-T18 verified on the Mac host, the Linux shape and the iOS 27.2
simulator; T19 needs D1; report `docs/test-reports/gradient-masks.md`)

**Input**: User description: "Implement CMP-008 (Gradient masks) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Support linear and radial alpha gradients with editable stops."
Acceptance, verbatim: "Gradient alpha is monotonic between test stops." Verification: unit tests,
snapshots and GPU performance. P2; depends on CMP-007 (shape masks, integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-008-R1…`, success criteria `CMP-008-S1…`, tasks `CMP-008-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `d518a943`)

The row's gap status is "Gap candidate". The audit confirms a full gap: a layer can be cut by a shape
(CMP-007) but cannot fade by a gradient.

| Area | Today | Gap for this row |
|---|---|---|
| Layer composite settings (CMP-001, `LayerCompositeSettings`) | opacity, blend, transform, fit, and the CMP-007 shape `mask` (ellipse, rectangle, polygon; feather, invert, mask transform). | No gradient. |
| Compositor mask path (CMP-007) | One coverage term in every draw path: normal layers through the masked "over" pass (no extra pass), other modes in the blend pass; a per-record mask block rebuilt only when the mask or size changes. | The coverage term knows only shapes. |
| CPU reference (CMP-007, `LayerMaskGeometry`) | Signed distance and coverage per layer pixel, matching the shader. | No gradient reference. |
| Scene format (SCN-001, CMP-007) | `composite.mask`, optional, written only when set; unknown shape kinds kept verbatim and warned (`unsupportedMaskShape`), drawn unmasked. Version 1. | No place for a gradient. |
| Layer inspector (CMP-015) | The mask section edits shape (None/Ellipse/Rectangle), size, corner radius, feather and invert, with help, undo and VoiceOver-adjustable sliders. | No gradient editor. |
| Goldens (QA-002) | Generator-level goldens per platform class (`GeneratorGoldens/<name>/<class>/`). CMP-007 added none. | No mask golden. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: Is a gradient another kind of the CMP-007 `composite.mask` (beside ellipse, rectangle, polygon),
  or a separate optional value beside it? → A: **Separate**: `LayerCompositeSettings.gradientMask` and
  the saved `composite.gradientMask`, so a gradient can fade a layer alone or combine with any shape
  (alpha = shape coverage × gradient alpha). This replaces CMP-007's assumption that CMP-008 would add
  a shape kind: a shape kind could not combine with a shape. The compositor still has one coverage
  term and one mask block per layer (the CMP-007 block gains the gradient's numbers), so no pass and
  no pipeline is added. Rejected: a `gradient` key inside the shape mask (a gradient would need a shape).
- Q: In what units are the gradient's geometry and stops given, and where is it evaluated? → A: In
  **layer space**, at the same layer pixel as CMP-007 (pixel centre = index + 0.5, before the CMP-005
  transform). Linear: `start` and `end` in layer fractions (each coordinate clamped −10…10); t is the
  projection of the pixel onto start→end in pixels, divided by the squared length (t = 0 at start,
  1 at end). Radial: `center` in layer fractions (clamped −10…10) and `radius` in units of the layer's
  **shorter side** (clamped 0.01…20), so it stays round on any aspect; t = distance / radius. Stops:
  `position` and `alpha` each clamped 0…1; alpha is a straight multiplier (no sRGB curve). A linear
  gradient whose start and end are less than 1e-6 apart (layer fractions) is refused by the live model
  (typed error) and dropped from a file with `droppedField`.
- Q: How are stops ordered, how many are allowed, and what does a file with bad stops do? → A: 2…8
  stops (one fixed 8-stop shader block), sorted by position with a **stable** sort (equal positions keep
  their order and give a hard step). The live model sorts silently; the decoder sorts too and warns
  `valueClamped` ("stops were sorted") when the file's order differed, so a re-save is canonical. Fewer
  than 2 or more than 8 stops drop the whole gradient with `droppedField` naming the count (counted
  before any stop is decoded). Rejected: truncating to 8 (silently a different picture).
- Q: What does an unknown gradient kind (for example a future "conic") do? → A: The whole
  `gradientMask` object is kept verbatim (decode, encode, load, capture), validation warns with the
  existing `unsupportedMaskShape` kind at `…composite.gradientMask.kind` (so SCN-012's repair report
  lists it as a note with no new issue kind), and the layer is drawn without a gradient (its shape mask,
  if any, still applies). Missing fields of a known kind read defaults; unknown keys are dropped with
  `droppedField`; every field is written in full so decode → encode is byte-identical.
- Q: What does the inspector's gradient editor show, and what are its defaults and undo steps? → A: A
  "Gradient" section after Mask: a picker (None, Linear, Radial); Linear adds an **Angle** slider
  (−180…180°, step 5; the gradient keeps its midpoint and length in layer fractions and turns; default
  0° = left to right, start (0, 0.5), end (1, 0.5)); Radial adds a **Radius** slider (0.1…2, step 0.05;
  default centre (0.5, 0.5), radius 0.5). Both default to two stops (0, alpha 1) and (1, alpha 0). Each
  stop has a Position and an Alpha slider (ACC-005 `.accessibleParameter`, step 0.05, identifiers
  `layerControl.gradientStop<n>.position|alpha`) and a Remove button (disabled at 2 stops); **Add Stop**
  (disabled at 8) inserts at the middle of the widest gap with the alpha the gradient already has there,
  so the picture does not change. A drag is one undo step (key `layer.<kind>.gradientStop<n>.<field>`);
  kind, add and remove are one step each. Moving a stop past a neighbour re-sorts the list. "GPU
  performance" is an opt-in Mac bench (Release-like timing of a full-screen gradient layer, recorded as
  not device evidence, never asserted) plus a `{device}` task for D1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fade a layer with a gradient (Priority: P1) 🎯 MVP

A scene author gives a layer a gradient mask: linear (from a start point to an end point) or radial
(from a centre outwards to a radius). The gradient has between two and eight stops; each stop has a
position along the gradient and an alpha. The layer's visibility follows the gradient: at each stop
it shows with that stop's alpha, between two stops it changes evenly, and before the first or after
the last stop it keeps that stop's alpha.

**Why this priority**: It is the row's observable behavior and its acceptance criterion.

**Independent Test**: Composite a solid opaque layer with a linear and a radial gradient, read the
pixels back densely along the gradient's axis, and check that alpha never moves against the
direction of the two neighbouring stops' alphas and equals each stop's alpha at its position.

**Acceptance Scenarios**:

1. **Given** a linear gradient with stops whose alphas rise and fall, **When** composited, **Then**
   alpha along the axis is non-decreasing between stops whose alpha rises, non-increasing between
   stops whose alpha falls (within 1/255), and equals the reference at every sample.
2. **Given** a radial gradient, **When** composited, **Then** the same holds along any ray from the
   centre, and every pixel at the same distance from the centre has the same alpha.
3. **Given** positions before the first or after the last stop, **When** composited, **Then** alpha
   is that stop's alpha.
4. **Given** a layer with both a shape mask and a gradient, **When** composited, **Then** its alpha
   is the shape's coverage times the gradient's alpha (outside the shape still exactly 0).

---

### User Story 2 - Edit the stops (Priority: P1)

In the layer inspector, the author picks a gradient (None, Linear, Radial), sets its direction or
radius, and edits the stops: add a stop, remove a stop (never below two), move a stop's position and
change its alpha. Every control has help, is adjustable with VoiceOver and is one undo step per drag.

**Why this priority**: The row says the stops are editable.

**Independent Test**: UI test: choose Linear, add a stop, move it and change its alpha, then undo;
unit tests of the edit rules (sorting, limits, add and remove).

**Acceptance Scenarios**:

1. **Given** a layer without a gradient, **When** the author picks Linear, **Then** a left-to-right
   gradient from alpha 1 to alpha 0 appears with two stops.
2. **Given** a gradient with two stops, **When** the author taps Add Stop, **Then** a third stop
   appears at the middle of the widest gap, with the alpha the gradient has there (the picture is unchanged).
3. **Given** eight stops, **Then** Add Stop is disabled; **given** two stops, **then** remove is
   disabled.
4. **Given** a stop moved past its neighbour, **Then** the stops are kept in position order.
5. **Given** a stop edit, **When** the author undoes, **Then** the previous gradient returns.

---

### User Story 3 - Scenes keep the gradient (Priority: P1)

A scene stores each layer's gradient (kind, geometry, stops). Opening and saving keeps it exactly; a
gradient kind from a newer version is kept, reported and not drawn.

**Why this priority**: Without persistence, the edit is lost on relaunch.

**Independent Test**: Decode → encode, and decode → load → capture → encode, of scenes with a linear
and a radial gradient (with and without a shape mask); compare bytes.

**Acceptance Scenarios**:

1. **Given** a scene with a gradient, **When** decoded and encoded, **Then** the bytes are identical.
2. **Given** the same scene, **When** loaded and captured, **Then** the gradient is unchanged.
3. **Given** an unknown gradient kind, **When** loaded, **Then** the repair report lists it as a note,
   capture writes it back verbatim and the layer is drawn without a gradient.
4. **Given** out-of-range values, too few or too many stops, **When** decoded, **Then** values are
   clamped with `valueClamped`, and an unusable stop list drops the gradient with `droppedField`.
5. **Given** a scene written before this feature, **When** decoded and encoded, **Then** the bytes and
   the format version are unchanged.

### Edge Cases

- Two stops at the same position: a hard step at that position (no interpolation across it).
- A linear gradient whose start equals its end (closer than 1e-6): refused by the live model; in a
  file, dropped with `droppedField`.
- A radial radius at its minimum: still finite; everything beyond the last stop keeps its alpha.
- A gradient on an inverted shape mask: the product of both.
- A transformed layer (CMP-005): the gradient moves with the layer, as a shape mask does.
- An output size change: a radial gradient stays round; a linear one keeps its relative endpoints.
- All stops at alpha 1: the layer is drawn exactly as without a gradient.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-008-R1**: The layer contract MUST offer an optional gradient mask per layer, independent of
  the CMP-007 shape mask, with two kinds: linear (start and end point) and radial (centre and radius).
- **CMP-008-R2**: A gradient MUST have 2 to 8 stops, each with a position 0…1 and an alpha 0…1, kept
  sorted by position (stable for equal positions).
- **CMP-008-R3**: The gradient's alpha at a parameter t MUST be the first stop's alpha for t at or
  before the first stop, the last stop's alpha at or after the last stop, and the linear
  interpolation of the two neighbouring stops in between; hence monotonic between adjacent stops.
- **CMP-008-R4**: A plain reference calculation (no GPU, every platform) MUST give the gradient alpha
  of any layer pixel, matching the GPU within 1/255.
- **CMP-008-R5**: The gradient MUST be evaluated in the layer's own space (as CMP-007), so it moves
  with the layer's transform; it MUST combine with a shape mask by multiplication and work with every
  blend mode and opacity.
- **CMP-008-R6**: Gradients MUST NOT add a render pass for normal-mode layers, and layers without a
  gradient MUST be drawn exactly as before.
- **CMP-008-R7**: The scene format MUST store the gradient as an optional value written only when set,
  with the format version unchanged; scenes without it MUST encode byte-identically and a gradient
  MUST round-trip byte for byte.
- **CMP-008-R8**: An unknown gradient kind MUST be kept verbatim through decode, encode, load and
  capture, warned about by validation, listed by SCN-012's repair report as a note, and not drawn.
- **CMP-008-R9**: Out-of-range values MUST be clamped on decode with `valueClamped`; a stop list with
  fewer than 2 or more than 8 stops, or a linear gradient of zero length, MUST drop the gradient with
  `droppedField` naming the reason.
- **CMP-008-R10**: The layer inspector MUST edit the gradient's kind, direction (linear) or radius
  (radial) and its stops (add, remove, position, alpha) within the limits of R2, with help, VoiceOver
  adjustable controls and one undo step per drag or choice.
- **CMP-008-R11**: A gradient change applied to the stack MUST show from the next frame without
  re-creating the layer or its pictures.
- **CMP-008-R12**: Geometry MUST use layer fractions for points and the layer's shorter side for the
  radial radius, so a radial gradient stays round on any output aspect.

### Key Entities

- **Gradient stop**: position 0…1 along the gradient, alpha 0…1.
- **Gradient mask**: kind (linear or radial), its geometry, and 2…8 sorted stops.
- **Gradient alpha**: 0…1 per pixel, multiplying the layer's colour and alpha (with the shape
  coverage when both are set).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-008-S1**: In GPU read-backs of a linear and a radial test gradient, sampled at every pixel
  along the gradient axis, 0 samples move against the direction of their segment's stop alphas by
  more than 1/255, and every sample matches the reference within 1/255.
- **CMP-008-S2**: The reference gives each stop's alpha exactly at its position, and 0 monotonicity
  violations over a dense sweep of several stop lists (rising, falling, mixed, equal positions).
- **CMP-008-S3**: One linear and one radial golden image match on the Mac host and the iOS simulator
  under QA-002's rule.
- **CMP-008-S4**: 100 % of gradient scene round trips are byte-identical; scenes without gradients and
  existing goldens are unchanged; QA-004's meta-test passes with no new version.
- **CMP-008-S5**: The GPU time of a full-screen gradient layer is measured on the Mac and recorded as
  "not device evidence"; the device measurement on D1 is a `{device}` task.
- **CMP-008-S6**: In the UI test, adding, moving and re-weighting a stop and one undo complete in under
  30 s, with the stop count and values shown as expected.

## Assumptions

- The gradient is a separate optional field (`composite.gradientMask`) beside the shape mask (see
  Clarifications), not another shape kind, so it can combine with any shape.
- Older app versions drop the new field with `droppedField` (format version 1 tolerates unknown
  keys) and draw the layer without a gradient, accepted as for any newer optional value.
- Polygon masks stay file-only in the inspector, as in CMP-015.
