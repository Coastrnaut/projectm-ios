# Feature Specification: CMP-005 Transform Controls

**Feature Branch**: `feature/cmp-005` (spec directory `046-cmp-005-transform-controls`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement CMP-005 (Transform controls) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Move, scale and rotate layers
around editable anchor points." Acceptance, verbatim: "Saving and reloading reproduces a test
transform matrix." Depends on CMP-002 (integrated: `LayerStack`, `Compositor.apply`, ADR-0013 and
its CMP-002 and CMP-003 amendments). Implement only CMP-005; blend modes (CMP-004) stay refused."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-005-R1…`, success criteria `CMP-005-S1…`, tasks `CMP-005-T01…`. Requirements
of other features are cited by their own IDs: CMP-001-R9 (no per-frame allocation), CMP-001-R10
(composite flash guard), CMP-002-R7 to R11 (apply semantics), CMP-003-R1 to R4 (opacity).

## Baseline: what exists today (audit of 2026-11-13, commit `95c5f22`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Composite settings | Each stack entry carries a `transform`: six raw numbers (a 2 × 3 matrix in output pixels) with an identity value. | No move, scale, rotate or anchor controls; the raw matrix depends on the output's pixel size, so it cannot be saved and reused on another output; it cannot be saved at all. |
| Compositor | Draws every shown picture pixel for pixel over the layers below (opacity from CMP-003). | Refuses any non-identity transform (CMP-002-R11, CMP-003-R11). |
| Scenes | No scene file yet (SCN-001 is a later row). | A transform needs a stable saved form that a scene file can embed later. |
| App | The Camera visual uses identity transforms. | Nothing to change; a user-facing transform editor belongs to the layer inspector (CMP-015). |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A saved transform reloads to the same matrix (Priority: P1)

A caller (later: a layer inspector, a scene document) sets a layer's move, scale, rotation and
anchor point, saves the transform, and loads it again later. The reloaded transform describes
exactly the same placement: its matrix is identical, number for number, to the one before saving.

**Why this priority**: It is the row's acceptance.

**Independent Test**: Build a test transform (a move, a non-uniform scale and a rotation about an
anchor that is not the centre), take its matrix for an output, save it, load it and compare the
matrix bit for bit. Runs on every host including Linux.

**Acceptance Scenarios**:

1. **Given** a test transform (move (0.125, −0.25), scale (1.5, 0.75), rotation 0.3 rad about anchor
   (0.2, 0.8)), **When** it is saved and loaded, **Then** the loaded transform equals the original
   and its matrix for a 64 × 32 output equals the original's in every element bit for bit.
2. **Given** many transforms with arbitrary in-range values, **When** each is saved and loaded,
   **Then** every value and every matrix element is bit-identical.
3. **Given** a saved transform, **When** it is read, **Then** its fields have documented names and
   units and a format version, so a later scene file can embed it unchanged.

---

### User Story 2 - Layers are moved, scaled and rotated on screen (Priority: P1)

A caller gives a layer a transform and applies the stack. The layer's picture is drawn moved,
scaled and rotated about its anchor point; parts of the output the transformed picture does not
cover show what is below. A layer without a transform looks exactly as before.

**Why this priority**: It is the observable behavior; a saved matrix is useless if nothing draws it.

**Independent Test**: GPU tests at 64 × 64: a red layer scaled to half size with its top-left
anchor and moved to the output's centre covers exactly the bottom-right quarter; an asymmetric
pattern rotated a quarter turn lands where expected; an identity transform is bit-identical to the
output before this row.

**Acceptance Scenarios**:

1. **Given** an opaque red layer scaled to half its size about its top-left corner and moved by half
   the output, **When** a frame is composited, **Then** the bottom-right quarter is red and the rest
   is transparent (one pixel of tolerance at the square's edges).
2. **Given** a pattern with a red top-left quarter and a green top-right quarter, **When** it is
   rotated by a quarter turn clockwise (as seen on screen) about its centre, **Then** red is in the
   top-right quarter, green in the bottom-right quarter and the left half is transparent.
3. **Given** a layer with the identity transform (any anchor), **When** a frame is composited,
   **Then** the output is bit-identical to the output before this row.
4. **Given** a non-square output, **When** a layer is rotated, **Then** its picture is not skewed: a
   quarter turn maps a horizontal span of n pixels to a vertical span of n pixels.

---

### User Story 3 - Transforms are safe and cheap (Priority: P1)

Invalid input never reaches the screen, and changing a transform never re-creates or re-prepares a
layer.

**Why this priority**: A transform edit must not stutter, leak GPU memory or poison the composite.

**Independent Test**: Unit tests of refused and clamped values; counts of preparations and picture
creations across transform-only applies and steady frames.

**Acceptance Scenarios**:

1. **Given** a non-finite move, scale, rotation or anchor, **When** a transform is made, **Then** it
   is refused with a typed reason; a finite value outside its range is clamped.
2. **Given** an applied stack, **When** a stack differing only in transforms is applied, **Then** no
   layer is created, prepared or released.
3. **Given** a transformed layer at a steady size, **When** 30 frames are composited, **Then** no
   picture is created.

### Edge Cases

- A scale near zero would collapse the picture and make its inverse undefined: scale is bounded.
- Mirroring (negative scale) is not part of this row; a negative scale is clamped to the minimum.
- Rotations of any finite size are kept as given (several turns are allowed and saved as given).
- An anchor point may lie outside the layer's picture (rotate about a point beside it).
- A transform moving the picture entirely off the output shows nothing of the layer, without error.
- Output pixels outside the transformed picture read transparent, never a smeared edge colour.
- A transform with no move, unit scale and no rotation is the identity whatever its anchor, and is
  drawn exactly as before this row.
- A saved transform from a newer, unknown format version is refused with a typed reason.
- A saved transform missing optional fields reads their defaults (identity values).
- Non-finite values cannot be saved (they are refused before they are ever stored).
- Layer opacity (CMP-003) and the composite flash guard apply to transformed layers as to others.
- Blend modes other than normal are still refused (CMP-004).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-005-R1**: A layer transform MUST consist of a move (in output units: fractions of the
  output's width and height), a scale per axis, a rotation angle and an anchor point (in the
  layer's own units: fractions of its picture, the centre by default).
- **CMP-005-R2**: The transform MUST define one exact placement matrix for a given output size, in a
  documented order: scale and rotate about the anchor point, then move. The anchor point MUST land at
  its own position plus the move. Rotation MUST be measured in square output pixels, so a rotation
  never skews on a non-square output.
- **CMP-005-R3**: A transform with no move, unit scale and no rotation MUST be the identity
  whatever its anchor point.
- **CMP-005-R4**: Non-finite values MUST be refused with a typed reason and change nothing; finite
  values outside their documented ranges MUST be clamped (move and anchor −10…10, scale 0.05…20 per
  axis; rotation unbounded).
- **CMP-005-R5**: A transform MUST be savable in a stable, versioned form with documented field
  names, units and defaults, and loading the saved form MUST reproduce the transform and its matrix
  bit for bit. An unknown format version MUST be refused; missing fields read their identity
  defaults; out-of-range loaded values are clamped as in CMP-005-R4.
- **CMP-005-R6**: The compositor MUST accept transforms for stack entries and for layers given to it
  directly, and draw each transformed layer's picture placed by its matrix, sampled smoothly, with
  output pixels outside the placed picture contributing nothing.
- **CMP-005-R7**: A layer with the identity transform MUST be drawn bit-identically to the output
  before this row (CMP-003).
- **CMP-005-R8**: Applying a stack that differs only in transforms MUST create, prepare and release
  nothing, and frames at a steady size MUST create no pictures (CMP-001-R9).
- **CMP-005-R9**: Opacity (CMP-003) MUST apply to transformed layers unchanged, and transforms MUST
  be applied before the composite flash guard (CMP-001-R10).
- **CMP-005-R10**: The transform values, matrix and saved form MUST build and be tested on Linux.
- **CMP-005-R11**: Blend modes other than normal MUST still be refused at apply (until CMP-004).

### Key Entities

- **Layer transform**: move, per-axis scale, rotation and anchor point of one layer; part of the
  stack entry's composite settings.
- **Placement matrix**: the 3 × 3 affine matrix that maps a point of the layer's picture to the
  output for a given output size.
- **Saved transform**: the versioned, named-field form a scene file embeds.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-005-S1**: The test transform's matrix after saving and loading equals the original in 9 of
  9 elements bit for bit, and 100% of 1,000 arbitrary transforms round-trip bit for bit (the
  acceptance).
- **CMP-005-S2**: Matrix rules hold exactly or within 1e-12: identity, documented order, anchor
  invariance, and equal pixel lengths for a quarter turn on a 2:1 output.
- **CMP-005-S3**: The moved quarter-size red square and the quarter-turn pattern read as expected
  in 100% of pixels outside a one-pixel edge band (64 × 64).
- **CMP-005-S4**: An identity transform's output is bit-identical to the unmodified output in 100%
  of pixels.
- **CMP-005-S5**: 0 layer preparations for transform-only edits and 0 pictures created over 30
  transformed frames at a steady size.
- **CMP-005-S6**: The composite cost of transforms is covered by the per-layer frame-cost
  measurement on D1-D3 already open as CMP-002-T15 (device stage); no separate device task.

## Assumptions

- A user-facing transform editor (handles, gestures) belongs to the layer inspector (CMP-015) and
  the editing UI rows; modulation and OSC targets belong to the MOD and UIX rows. This row exposes
  transforms to code only and changes nothing a user sees.
- The scene file (SCN-001) will embed the saved transform as one field of a layer entry; this row
  defines only the transform's own saved form.
- Aspect fitting (CMP-006) and group transforms (CMP-011) build on this matrix later; layer
  pictures stay the output's size (ADR-0013 decision 2).
- The extra sampling work is small next to a layer's own render; it is measured with the per-layer
  frame cost of CMP-002-T15.
