# Feature Specification: SHD-008 Vector Path Editor

**Feature Branch**: `feature/shd-008` (spec directory `279-shd-008-vector-path-editor`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHD-008-T01-T17 verified on the Mac host, the Linux shape and the iOS 27.2
simulator; no device run, T18 open; report `docs/test-reports/vector-path-editor.md`)

**Input**: User description: "SHD-008 Vector path editor. Roadmap row: "Create closed paths for masks and
particle emitters." P2, size L, depends on CMP-007. Acceptance, verbatim: "Saved path restores points and
rejects self-intersecting invalid mask cases.""

Identifiers carry the roadmap ID: requirements `SHD-008-R1…`, success criteria `SHD-008-S1…`, tasks
`SHD-008-T01…`, research decisions `SHD-008-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `704a1ec5`)

| Area | Today | Gap for this row |
|---|---|---|
| Shape masks (CMP-007, `LayerMask`) | Ellipse, rounded rectangle and polygon (3…32 points, local box −0.5…0.5, even-odd fill, no self-intersection check: a star has a hole). Polygons come only from scene files; the inspector offers ellipse and rectangle. Saved as `composite.mask`; an unusable polygon drops the mask with `droppedField`; an unknown shape kind is kept verbatim and drawn unmasked. | No way to draw a path; no "simple polygon" guarantee. |
| Mask rasteriser (CMP-007 shader) | Polygon kind 3: signed distance with even-odd sign, one fixed 32-point parameter block. | Reusable as is for a validated path. |
| Particle emitter (SHD-007, `ParticleEmitterSettings`) | Spawn shapes point, line, circle, rectangle sized by width/height (R); seeded RNG; exact spawn accumulator; stored in `settings.particleFountain.emitter`. | No free-form spawn area. |
| Handle editors (OUT-007 corner pin, CMP-002) | Draggable 44 pt handles, VoiceOver element per handle with Move left/right/up/down actions, nudge buttons, refuse-and-keep-last-valid model (`CornerPin.moving`). | Pattern to reuse for path points. |
| SHD-011 policy | Parameters only; no user code or shaders. | A path is data (points) only. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: Should a path allow curves (quadratic/cubic Bézier segments) or only straight segments? → A:
  **Straight segments only (polygon)** in this row. The mask shader and the validation are exact for
  polygons; curves would need flattening with a tolerance, would multiply the point count past CMP-007's
  32-point shader block and add a second validation surface. Curves can be a later row that flattens into
  the same polygon model. Rejected: cubic segments flattened to polylines (more code and tests, no row
  requirement).
- Q: What are the point cap, the coordinate space and the minimum area? → A: **3…32 points** (CMP-007's
  polygon cap, so path masks reuse the shader's fixed 32-point block unchanged; the brief's 64 would need a
  shader change), coordinates in the **unit square 0…1, y down** (as on screen), minimum absolute area
  **1e-4** of the unit square (a 1 % × 1 % square; anything smaller is refused as "too small"), and
  consecutive points closer than **1e-6** are "duplicate". Mask: the unit square maps onto the mask's local
  box (local = point − 0.5), so the CMP-007 mask transform, feather and invert apply unchanged. Emitter: the
  unit square spans the emitter's shape width × height (R) centred on the emitter point, y flipped to
  the fountain's y up.
- Q: What exactly counts as self-intersecting? → A: Any two **non-adjacent** edges that intersect or touch
  (proper crossing, a vertex lying on another edge, or a shared point between non-adjacent edges), and any
  **collinear overlap** of two edges, adjacent ones included (a spike that doubles back). Adjacent edges
  may only share their common endpoint. Tests use exact orientation signs with a small tolerance
  (|cross| ≤ 1e-12 treated as collinear). Even-odd and non-zero fill agree for every path that passes.
- Q: What happens to a saved invalid path, in a scene and in the emitter settings? → A: **Scene**: the
  path mask is **dropped** with a `droppedField` warning naming the reason (the layer draws unmasked; the
  scene opens; SCN-012 lists it), exactly as CMP-007 drops an unusable polygon. Rejected: keep-but-disabled
  (a second "disabled mask" state every mask consumer would need to learn). **Emitter settings**: lenient
  like every other emitter field: an invalid or missing path reads as the **default path** (a diamond of 4
  points: (0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)). Nothing ever crashes.
- Q: How does the path emitter spawn particles: inside the area or along the outline? → A: **Uniformly
  inside the area**: the validated polygon is triangulated once (ear clipping), a triangle is picked by
  area with one seeded draw and a point inside it with two more (two uniform numbers, reflected when their sum
  exceeds 1), so every path spawn uses exactly three draws, then direction, speed and lifetime as SHD-007.
  The triangulation is computed when the path is created, so spawning allocates nothing (Constitution VII).
  Rejected: outline spawning (the line shape already covers thin emitters) and rejection sampling (a
  variable number of draws).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Draw a valid closed path (Priority: P1) 🎯 MVP

A user opens the path editor, taps to place points, drags points to adjust them, deletes points and closes
the path. While editing, an inline message says whether the path can be closed; a path that would cross
itself, has repeated points, too few points or almost no area cannot be closed. Once closed, any edit that
would make the path invalid is refused and the last valid path stays.

**Why this priority**: It is the row's observable behaviour and half of its acceptance criterion
("rejects self-intersecting invalid cases").

**Independent Test**: Pure validation tests on representative shapes and an editor-model test; a short UI
test adds points, sees the invalid message for a bow-tie and closes a valid path.

**Acceptance Scenarios**:

1. **Given** four points placed in bow-tie order, **When** the user tries to close, **Then** closing is
   refused and the message says the path crosses itself.
2. **Given** a concave (L-shaped or arrow) set of points, **When** closed, **Then** it is accepted.
3. **Given** a closed valid path, **When** the user drags a point across an opposite edge, **Then** the move
   is refused and the last valid path is kept.
4. **Given** a figure-8 of five points, a path where one vertex touches another edge, or two collinear
   edges that overlap, **When** validated, **Then** each is rejected as self-intersecting.
5. **Given** three nearly collinear points (area under the minimum), or two equal consecutive points,
   **When** validated, **Then** each is rejected with its own reason.

### User Story 2 - Use a path as a layer mask (Priority: P1)

In the layer inspector the mask shape picker offers "Path". Choosing it gives the layer a default path mask
that the user edits in the path editor; the layer is shown only inside the path, with the mask's existing
feather, invert and size controls. The scene stores the path's points and restores them exactly.

**Why this priority**: It is the other half of the acceptance criterion ("saved path restores points") and
the row's first use.

**Independent Test**: Scene decode → encode and decode → load → capture → encode of a path mask compare
equal; a GPU read-back through the real compositor counts covered pixels inside and outside the path.

**Acceptance Scenarios**:

1. **Given** a scene with a path mask, **When** saved and opened, **Then** every point is restored exactly
   and the bytes are identical.
2. **Given** a saved path mask that crosses itself (edited by hand or from a damaged file), **When** the
   scene is opened, **Then** the mask is dropped with a warning naming the reason, the layer draws
   unmasked, and nothing crashes.
3. **Given** a path mask on a solid layer, **When** composited, **Then** pixels clearly inside the path are
   opaque, pixels clearly outside have alpha 0, and the covered pixel count matches the polygon's area
   within tolerance.

### User Story 3 - Use a path as a particle spawn area (Priority: P2)

In the particle emitter editor the spawn shape picker offers "Path". The user edits the path in the same
editor; particles are born uniformly inside the closed path, sized by the existing shape width and height.

**Why this priority**: The row's second use; it builds on Story 1's editor.

**Independent Test**: A seeded 10 s simulation with a concave path: every spawned particle starts inside the
polygon, the spawn count equals the SHD-007 formula, two runs are identical.

**Acceptance Scenarios**:

1. **Given** the path shape with a concave path, **When** the fountain runs 10 s, **Then** every particle's
   birth position lies inside the polygon and none lies in its notch.
2. **Given** the path shape, **When** run at 60 Hz or with jittery frames, **Then** the spawn attempts are
   exactly ⌊rate·steps⌋ as in SHD-007.
3. **Given** stored emitter settings with an invalid path, **When** read, **Then** the default path is used.

### Edge Cases

- Points outside 0…1 or non-finite: refused (editor) and rejected (validation).
- More than the point cap: adding is refused with a message.
- Deleting a point of a triangle: refused (would leave fewer than 3).
- A path shape kind unknown to an older app version: CMP-007 keeps it verbatim and draws the layer unmasked.
- Very thin but valid sliver: accepted if its area is above the minimum.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-008-R1**: A vector path is a closed polygon of 3 to 32 points in a unit square (0…1 on both axes,
  y down); it carries only numbers (SHD-011: parameters only).
- **SHD-008-R2**: Validation rejects, each with a distinct reason: non-finite or out-of-range coordinates;
  fewer than 3 or more than 32 points; equal consecutive points (including last→first); absolute area at or
  below the minimum; any intersection between two non-adjacent edges, any touch of a vertex on a
  non-adjacent edge, and any collinear overlap of edges (adjacent edges included).
- **SHD-008-R3**: Editing: add a point (tap, while drawing only), move a point (drag or nudge), delete a
  point, close the path, and start over (a new drawing; the last closed path stays in use until the new one
  closes). Before closing, the draft may be invalid and an inline message states the reason; Close is
  available only for a valid draft. After closing, an edit that would make the path invalid is refused, the
  last valid path is kept and the message states why.
- **SHD-008-R4**: Accessibility: every point is one VoiceOver element ("Point 2", value with its position)
  with Move left/right/up/down and Delete actions; visible nudge buttons move the selected point; the
  inline message is announced through the existing announcer lanes.
- **SHD-008-R5**: Mask use: a "path" mask shape on a layer, drawn by the existing mask pipeline (filled
  inside, feather, invert and mask transform apply as CMP-007), with the path's unit square mapped onto the
  mask's local box.
- **SHD-008-R6**: Mask persistence: the scene saves the path's points in full and restores them exactly
  (decode → encode byte-identical); no format version change. An invalid saved path drops the mask with a
  `droppedField` warning naming the reason; the scene still opens.
- **SHD-008-R7**: Emitter use: a "path" spawn shape spawns uniformly inside the polygon (area-weighted),
  with the seeded generator in a fixed draw order; the path spans the shape width × height around the
  emitter point. SHD-007's spawn count rules are unchanged.
- **SHD-008-R8**: Emitter persistence: the path is stored inside the existing emitter settings value (no
  new stored key); an invalid or missing stored path reads as the default path.
- **SHD-008-R9**: The editor opens from the layer inspector's mask section and from the particle emitter
  editor's spawn section.

### Key Entities

- **Vector path**: ordered points (x, y) in 0…1, implicitly closed; valid by construction.
- **Path validation outcome**: valid, or one reason (too few/many points, out of range, duplicate point,
  too small, crosses itself).
- **Path draft**: the editor's working points, a closed flag, the selected point and the last message.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-008-S1**: A saved path (mask in a scene, emitter in settings) restores every point exactly in 100%
  of the round-trip tests.
- **SHD-008-S2**: All four self-intersecting families (bow-tie, 5-point figure-8, touching vertex, collinear
  overlap) are rejected, and the representative concave shapes are accepted.
- **SHD-008-S3**: A path mask composited on the GPU has 0 non-transparent pixels farther than the edge band
  outside the path and a covered count within 2% of the polygon's area.
- **SHD-008-S4**: In a seeded 10 s run, 100% of particles spawned from a concave path start inside it, and
  the spawn count equals the SHD-007 formula.
- **SHD-008-S5**: A user can draw and close a valid path in the editor in under 30 s (UI test budget).

## Assumptions

- Polygon segments only (no curves), 3…32 points; see Clarifications.
- Undo for mask edits comes from the existing scene history (each committed path change is one step).
- No device evidence is needed for acceptance; one `{device}` look on D1 is left open.
