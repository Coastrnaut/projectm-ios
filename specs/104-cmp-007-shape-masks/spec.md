# Feature Specification: CMP-007 Shape Masks

**Feature Branch**: `feature/cmp-007` (spec directory `104-cmp-007-shape-masks`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-007 (Shape masks) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Mask layers with circle, rectangle and polygon shapes." Acceptance,
verbatim: "Outside pixels have alpha zero and mask transforms persist." Verification: unit tests,
snapshots and GPU performance. Depends on CMP-001 (unified layer protocol, integrated); works with
CMP-003 (opacity), CMP-004 (blend modes), CMP-005 (transforms), CMP-006 (aspect fitting) and SCN-001
(scene format)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-007-R1…`, success criteria `CMP-007-S1…`, tasks `CMP-007-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `804f3937`)

The row's gap status is "Gap candidate". The audit confirms a full gap: no layer can be masked.

| Area | Today | Gap for this row |
|---|---|---|
| Layer composite settings (CMP-001, `LayerCompositeSettings`) | opacity (CMP-003), blend mode (CMP-004), transform (CMP-005), fit (CMP-006). `LayerStack.swift` notes that "masks … will add fields". | No mask. |
| Compositor draw paths | Normal identity layers: per-pixel premultiplied "over" (fixed-function blending, one open pass). Normal transformed layers: inverse-matrix bilinear sample, same pass. Other blend modes: one full-screen pass each into a ping-pong composite. Every path sanitizes and multiplies by opacity. | No coverage term; masking would need a place in all three paths without adding a pass for normal layers. |
| Transforms (CMP-005) | The compositor maps each output pixel to a layer pixel; outside the picture reads transparent. | Masks need to know which layer pixel they evaluate. |
| Fit (CMP-006) | Photo and video fit their content inside their own output-sized picture. | The mask's relation to fitted content must be stated. |
| Flash guard (FX-019) | Runs on the finished composite; masking reduces brightness only. | None. |
| Scene format (SCN-001, ADR-0028) | `composite` is a closed object: `opacity`, `blend`, `transform`, `fit` (optional, CMP-006); other keys are dropped with `droppedField`. | No place for a mask. |
| Gradient masks (CMP-008, later) | Not started; depends on this row. | Leave room for more mask kinds. |
| UI | No screen edits a layer's opacity, transform, blend, fit or mask; stacks come from code, scenes and show cues (CMP-006 confirmed). | None required. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: In which space is a mask evaluated, and does it cut the fitted picture or the layer's
  rectangle? → A: In **layer space**: the layer's own output-sized picture, before the CMP-005
  transform, so the mask moves, scales and rotates with the layer (CMP-007-R6). For photo and
  video, CMP-006 fits the content inside that picture, so the mask cuts the **layer rectangle**,
  not the content rectangle: a centred circle stays centred on the layer whatever the content's
  size or fit mode, and fit bars stay transparent (mask × transparent = transparent). Rejected:
  output space (a mask that stays put while the layer moves is a different feature, a "window");
  content space (the compositor does not know each layer's content placement, and it would make
  masks behave differently per layer kind).
- Q: In what units are shapes and the mask transform measured, so that a circle stays a circle?
  → A: Shapes live in a local unit box (−0.5…0.5 on each axis). The mask transform places that box
  on the layer: **centre** in layer fractions (default (0.5, 0.5); clamped −10…10), **scale** per
  axis in units of the layer's **shorter side** (default (1, 1); clamped 0.01…20), **rotation** in
  radians, positive clockwise on screen like CMP-005 (any finite value). Because both axes use the
  shorter side and rotation is rigid in pixels, an ellipse with equal scales is a true circle on
  any output aspect and stays round when the output turns landscape. Corner radius is a fraction of
  the rectangle's shorter side (0…0.5; 0.5 gives a stadium), and polygon points are given in the
  same local box (each coordinate clamped −10…10; the box is a reference, not a limit). Feather is
  a fraction of the layer's shorter side (0…1); the edge band is feather plus one pixel, so even a
  zero feather is anti-aliased. Rejected: per-axis layer fractions (a circle becomes an ellipse on
  a non-square output and changes shape on rotation).
- Q: What is the polygon point cap, the fill rule, and what happens to an unusable polygon?
  → A: At most **32 points** (CMP-007-R8): one fixed-size shader parameter block (32 × 8 bytes),
  enough for hand-drawn cut-outs. Fill rule **even-odd** (as SVG `evenodd`; a self-intersecting
  star has a hole in the middle). A polygon with fewer than 3 points, more than 32 points or zero
  area is **unusable**: the scene decoder **drops the whole mask** with a `droppedField` warning
  that names the reason (SCN-012 lists it under "values adjusted"), and the live model refuses it
  with a typed error. Truncating to 32 points was rejected: it would silently draw a different
  shape. Drawing nothing was rejected: one bad value would hide a whole layer.
- Q: How is a mask saved, and what does an unknown shape kind do? → A: As an optional
  `composite.mask` object: `{"shape": "ellipse" | "rectangle" | "polygon", "cornerRadius" (rectangle),
  "points": [{"x", "y"}…] (polygon), "feather", "inverted", "transform": {"center": {"x", "y"},
  "scale": {"x", "y"}, "rotation"}}`, written only when set, every field written in full (so a
  decode → encode is byte-identical); the format version stays 1, so QA-004's matrix gains no row.
  Missing fields read defaults; out-of-range values are clamped with `valueClamped` (CMP-007-R11);
  unknown keys of a known shape are dropped with `droppedField`. An **unknown shape kind** keeps the
  whole mask object verbatim (decode, encode, load and capture), gives the new warning
  `unsupportedMaskShape` (a note in SCN-012's repair report), and the layer is drawn **unmasked**,
  as an unknown blend mode is drawn normal and an unknown fit as the default (CMP-007-R10).
- Q: Is there a mask editor in the UI, and what does "GPU performance" cover? → A: No editor: no
  screen edits a layer's composite settings today (CMP-006 confirmed); the inspector row that edits
  a stack adds one. "GPU performance" is a Mac measurement of a masked full-screen layer per shape
  (Release, GPU start/end times), recorded as not device evidence and never asserted (CMP-007-S5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mask a layer with a shape (Priority: P1) 🎯 MVP

A scene author (or a show cue, or code) gives a layer a mask shape: an ellipse (a circle when its
width equals its height), a rectangle with optional rounded corners, or a polygon of up to a capped
number of points. Only the part of the layer inside the shape is shown; everything outside is fully
transparent. The mask can be inverted (show only outside) and can have a soft, feathered edge.

**Why this priority**: It is the row's observable behavior and the first half of its acceptance
criterion.

**Independent Test**: Composite a solid opaque layer over nothing with each shape and read the
pixels back: outside the shape and its feather every pixel's alpha is exactly zero; inside, pixels
equal the unmasked layer; along the edge, coverage matches a plain reference calculation.

**Acceptance Scenarios**:

1. **Given** a solid layer with a circle mask, **When** composited, **Then** every pixel farther
   from the circle than its edge band has alpha exactly 0 and every pixel well inside equals the
   unmasked layer.
2. **Given** a rounded rectangle, a convex polygon and a concave (L-shaped) polygon, **When**
   composited, **Then** the same holds, including the notch of the concave polygon (transparent).
3. **Given** an inverted circle mask, **When** composited, **Then** the inside of the circle is
   exactly transparent and the far outside equals the unmasked layer.
4. **Given** a feathered mask, **When** composited, **Then** alpha falls smoothly and monotonically
   across the feather and is exactly 0 beyond it.

---

### User Story 2 - Masks work with every other layer setting (Priority: P1)

A masked layer can also be moved, scaled and rotated (CMP-005), fitted (CMP-006), faded (CMP-003)
and blended with any mode (CMP-004). The mask stays attached to the layer: when the layer moves,
its mask moves with it.

**Why this priority**: Masks are useless if they break the settings that already exist.

**Independent Test**: GPU read-back of a masked layer with a transform, with a fit, and with a
non-normal blend mode, compared with the reference.

**Acceptance Scenarios**:

1. **Given** a masked layer moved right by a quarter of the output, **When** composited, **Then**
   the visible shape is moved by the same amount and is still exactly transparent outside.
2. **Given** a masked layer with the screen blend mode over a backdrop, **When** composited,
   **Then** the backdrop outside the shape is unchanged and inside matches the screen equation.
3. **Given** a masked photo in fit mode, **When** composited, **Then** the mask cuts the layer's
   rectangle (not the fitted content rectangle) and fit bars stay transparent.
4. **Given** a normal-mode masked layer, **When** composited, **Then** no extra render pass is
   added for it.

---

### User Story 3 - Scenes keep the mask and its transform (Priority: P1)

A scene stores each layer's mask: shape, its parameters, feather, invert and the mask's own
transform (centre, scale, rotation). Opening and saving a scene keeps them exactly; a shape kind
from a newer version is kept, reported, and not drawn.

**Why this priority**: It is the second half of the acceptance criterion ("mask transforms
persist").

**Independent Test**: Decode → encode, and decode → load → capture → encode, of scenes with each
shape; compare bytes.

**Acceptance Scenarios**:

1. **Given** a scene with a rotated, scaled, off-centre polygon mask, **When** decoded and encoded,
   **Then** the bytes are identical.
2. **Given** the same scene, **When** loaded into the live state and captured again, **Then** the
   mask and its transform are unchanged.
3. **Given** a mask with an unknown shape kind, **When** loaded, **Then** the repair report lists
   it as a note, and capture writes it back verbatim.
4. **Given** out-of-range values or an unusable polygon, **When** decoded, **Then** values are
   clamped with a `valueClamped` warning, and a mask with an unusable polygon is dropped with a
   `droppedField` warning naming the reason.
5. **Given** a scene written before this feature, **When** decoded and encoded, **Then** the bytes
   are unchanged and the scene format version is unchanged.

### Edge Cases

- A mask on a layer whose picture is not shown (opacity 0, unavailable): nothing drawn, as today.
- A zero-width feather: the edge still gets a one-pixel anti-aliased band; beyond it alpha is 0.
- A corner radius larger than half the rectangle's shorter side: limited to half (a stadium shape).
- A polygon with fewer than three points, zero area, non-finite points or more points than the cap.
- A self-intersecting polygon: filled by the even-odd rule.
- A fit (CMP-006) on a masked photo: the mask cuts the layer rectangle; bars stay transparent.
- An inverted mask with a feather: the band is mirrored; deep inside the shape alpha is exactly 0.
- An output size change (device rotation): the mask keeps its shape (a circle stays round) and its
  relative position.
- A mask scaled so it covers nothing: the layer is fully transparent (inverted: fully shown).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-007-R1**: The layer contract MUST offer an optional mask per layer with three shape kinds:
  ellipse, rectangle (with a corner radius) and polygon (an ordered list of points, capped).
- **CMP-007-R2**: A mask MUST have its own transform (centre, scale per axis, rotation) placing the
  shape on the layer, an optional feather width and an invert flag.
- **CMP-007-R3**: Every pixel whose signed distance from the shape is at least half the edge band
  (feather plus one pixel of anti-aliasing) MUST be drawn with alpha exactly 0 for that layer (for
  an inverted mask: every pixel at least half the band inside the shape).
- **CMP-007-R4**: Pixels at least half the band inside the shape (inverted: outside) MUST be drawn
  exactly as without a mask; coverage in the band MUST rise monotonically from 0 to 1.
- **CMP-007-R5**: A plain reference calculation (no GPU, every platform) MUST give the coverage of
  any pixel for any mask, matching the GPU within a stated tolerance.
- **CMP-007-R6**: The mask MUST be evaluated in the layer's own space (its output-sized picture,
  before the CMP-005 transform), so it moves with the layer's transform and cuts the layer rectangle
  of a CMP-006-fitted layer; it MUST work with every CMP-004 blend mode and CMP-003 opacity.
- **CMP-007-R13**: Shape sizes MUST be measured in units of the layer's shorter side, so an ellipse
  with equal scales is a circle on any output aspect; the mask transform's centre is in layer
  fractions and its rotation is clockwise in radians, as CMP-005.
- **CMP-007-R7**: Masking MUST NOT add a render pass for normal-mode layers, and layers without a
  mask MUST be drawn exactly as before (bit-identical; existing goldens unchanged).
- **CMP-007-R8**: Polygons MUST have 3 to 32 points and non-zero area, filled by the even-odd rule;
  the live model MUST refuse other polygons with a typed error, and the scene decoder MUST drop a
  mask with such a polygon with a `droppedField` warning naming the reason.
- **CMP-007-R9**: The scene format MUST store a layer's mask as an optional `composite.mask` value,
  written only when set, with the format version unchanged; scenes without it MUST encode
  byte-identically, and a mask MUST round-trip byte for byte.
- **CMP-007-R10**: An unknown shape kind MUST be kept verbatim through decode, encode, load and
  capture, warned about by validation (`unsupportedMaskShape`), listed by SCN-012's repair report
  as a note, and drawn unmasked.
- **CMP-007-R11**: Out-of-range mask values MUST be clamped on decode with a `valueClamped` warning.
- **CMP-007-R12**: A mask change applied to the stack MUST show from the next frame without
  re-creating the layer or its pictures.

### Key Entities

- **Mask shape**: ellipse; rectangle with corner radius; polygon with points.
- **Mask transform**: centre (layer fractions), scale per axis, rotation.
- **Layer mask**: a shape, a mask transform, a feather width and an invert flag, per layer.
- **Coverage**: 0…1 per pixel, multiplying the layer's colour and alpha.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-007-S1**: For each shape (circle, rounded rectangle, convex polygon, concave polygon,
  inverted circle, feathered ellipse), 0 pixels outside the shape plus its band have non-zero alpha
  in a GPU read-back.
- **CMP-007-S2**: In the same read-backs, every pixel inside the shape minus its band equals the
  unmasked layer, and edge pixels match the reference coverage within 0.01.
- **CMP-007-S3**: The same holds (0 outside violations) for a masked layer with a CMP-005
  transform, with a CMP-006 fit, and with a non-normal blend mode.
- **CMP-007-S4**: 100 % of mask scene round trips (decode → encode; load → capture) are
  byte-identical; scenes without masks and existing golden renders are unchanged; QA-004's
  migration matrix meta-test still passes with no new version.
- **CMP-007-S5**: The GPU time of a masked full-screen layer is measured on the Mac and recorded as
  "not device evidence"; normal-mode masking adds no render pass.

## Assumptions

- No layer-editing screen exists, so no UI is added.
- Older app versions read a scene with `composite.mask` and drop it with `droppedField` (version 1
  tolerates unknown keys); the older app then shows the layer unmasked, which is accepted as for
  any newer optional value.
- Gradient masks (CMP-008) will add another mask kind to the same field later.
