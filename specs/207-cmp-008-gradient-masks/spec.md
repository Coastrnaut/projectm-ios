# Feature Specification: CMP-008 Gradient Masks

**Feature Branch**: `feature/cmp-008` (spec directory `207-cmp-008-gradient-masks`)

**Created**: 2026-11-14

**Status**: Draft

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
   appears between the widest gap, with the alpha the gradient has there (the picture is unchanged).
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
- A linear gradient whose start equals its end: refused by the live model; in a file, dropped with a
  warning.
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

- The gradient is a separate optional field beside the shape mask (see Clarifications), not another
  shape kind, so it can combine with any shape.
- Older app versions drop the new field with `droppedField` (format version 1 tolerates unknown
  keys) and draw the layer without a gradient, accepted as for any newer optional value.
- Polygon masks stay file-only in the inspector, as in CMP-015.
