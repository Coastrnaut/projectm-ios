# Feature Specification: OUT-008 Grid Warp

**Feature Branch**: `feature/out-008` (spec directory `309-out-008-grid-warp`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement OUT-008 (Grid warp) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior,
verbatim: "Adjust a bounded mesh for curved projection surfaces." Acceptance, verbatim: "Identity mesh is exact
pass-through and invalid meshes are rejected." P3, size XL, depends on OUT-007 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-008-R1…`, success criteria `OUT-008-S1…`, tasks
`OUT-008-T01…`, research decisions `OUT-008-D1…`. Other features are cited by their own IDs: OUT-001 (external display
scene), OUT-002 (hot-plug and recording hold), OUT-003 (output resolution), OUT-004 (aspect correction), OUT-007 (corner
pin), OUT-009 (display colour calibration), OUT-010 (output blackout), OUT-012 (rehearsal preview), OUT-014 (output
profile files), REC-001 (still capture), REC-003 (recording), FILE-005 (library backup), FILE-011 (erase), FX-019 (flash
safety envelope).

## Baseline: what exists today (audit of 2026-11-15, commit `0b6c3696`)

| Area | Today | Gap for this row |
|---|---|---|
| Corner pin (OUT-007) | One projective (four-corner) correction of the whole external output, composited as a transform of the external slot; strictly convex quads only; editor with handles, nudges, Reset; one device-local key; in OUT-014 profiles. | A projective map keeps straight lines straight, so it cannot follow a curved or uneven surface. |
| Final output passes (OUT-009) | projectM's FX-019 output step and the compositor's screen pass already apply a per-display property (the colour calibration) to external output only; recordings and captures stay content. The native spectra have no shared final pass (not covered). | No geometric (mesh) step in those passes. |
| Settings | Settings › External Display: Fit, Shape, Pixel aspect, Resolution, Output, Rehearse output…, Corner pin…, Color calibration…; device-local `settings.externalDisplay.*` keys, excluded from backup, erased with Settings. | A grid-warp editor and its stored mesh. |
| Output profiles (OUT-014) | A `.pmoutput` file carries every output transform; strict validation on import. | The mesh is not carried. |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human interaction); each
answer is the conservative, local-first option.

- Q: What is the "bounded mesh"? → A: A grid of control points laid over the visual's picture, from 3 × 3 up to 9 × 9
  points (columns and rows each 3…9), each point given in picture-relative coordinates (0…1 across and down). The
  identity grid places the points evenly on the picture (0, 1/(n−1), …, 1). Moving a point drags the picture with it;
  between the points the picture follows a smooth curve (OUT-008-R1, R2).
- Q: How is the picture interpolated between control points? → A: A smooth interpolating curve (Catmull-Rom in both
  directions) that passes exactly through every control point and reproduces evenly spaced and straight-line (affine)
  grids exactly, so the identity grid maps every point to itself; bilinear interpolation was rejected because it shows
  visible creases at every grid line on a curved surface (OUT-008-R2; research OUT-008-D2).
- Q: What makes a mesh invalid? → A: A mesh is accepted only when (1) it has 3…9 columns and 3…9 rows and exactly
  columns × rows points; (2) every coordinate is a finite number within −0.5…1.5 of the picture; (3) every control cell
  is a strictly convex quadrilateral with the identity grid's orientation and no corner turning by less than about 2°
  (no folded, crossed, mirrored or degenerate cell); (4) the smooth surface drawn between the points never folds (every
  drawn triangle keeps the identity's orientation with a positive area) and its outline does not cross itself; and
  (5) it covers at least 5 % of the picture. Anything else is rejected with a reason, and the last valid mesh (or the
  identity) stays (OUT-008-R3, R4).
- Q: How does grid warp combine with the corner pin? → A: Both may be active. The grid warp bends the visual's picture
  inside its own frame first; the corner pin then maps the whole external output (picture, bars, cards, cover) as
  before. A user keystones with the corner pin and then fine-tunes curvature with the grid (OUT-008-R6).
- Q: Which visuals and outputs are warped? → A: Only the external display output, like OUT-009: projectM and the
  compositor visuals (Camera, Photo, Video, Text) apply the mesh in their final pass; the native spectra have no shared
  final pass and are shown unwarped (reported as not covered). The device's own visualizer, recordings, still captures
  and the rehearsal preview are never warped (OUT-008-R7, R8).

### Session 2026-11-15 (speckit-clarify)

- Q: How does the projector show where the grid is while editing? → A: While the editor is open, the warp pass draws
  thin white guide lines along the control grid (through the control points) on top of the warped picture on the
  connected display, so the lines can be aligned with the surface's features; closing the editor removes them. The
  guides run even for the identity grid (OUT-008-R5).
- Q: What happens to the grid when its size changes in the editor? → A: The current surface is sampled at the new
  grid's points; when that mesh is valid it replaces the old one (the shape is kept as closely as the new size allows),
  otherwise the new size starts from the identity. Sizes offered: 3 × 3, 5 × 5 and 9 × 9 (an imported file may use any
  size within 3…9 per axis) (OUT-008-R5).
- Q: How large is one nudge step and what does a refused edit show? → A: 0.5 % of the picture (0.005), the corner pin's
  step. A refused drag or nudge leaves the point where it was and the editor shows the reason in words ("This would fold
  the picture", "Points must stay near the picture", …); VoiceOver announces it once through the accessibility
  announcer (OUT-008-R4, R5).
- Q: Is the mesh part of scenes, presets, OSC or MIDI? → A: No; it follows the corner pin's precedent: one device-local
  value (a property of the projector and surface, not of the content), carried by OUT-014 output profile files (optional,
  absent = identity) and validated there, and not wired to scenes, presets, OSC or MIDI (OUT-008-R9, R10).
- Q: Where does the mesh apply when the visual is letterboxed (Fit)? → A: Within the visual's picture (its frame as laid
  out by OUT-004); the black bars stay as OUT-004 lays them, and areas the bent picture no longer covers are black. With
  Fill or Stretch the picture is the whole display (OUT-008-R2).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fit the picture to a curved screen (Priority: P1)

A performer projects onto a gently curved wall. With the display connected they open Settings › External Display › Grid
warp…, pick a 5 × 5 grid, and the projector shows guide lines along the grid. They drag the middle points until the
guide lines follow the wall's seams; the live visual then follows the curved shape smoothly.

**Why this priority**: It is the row's new behaviour.

**Independent Test**: Apply a known mesh and check that the displayed picture is the source picture moved as the mesh
says (within a small tolerance), with nothing sampled from outside the picture.

**Acceptance Scenarios**:

1. **Given** the identity mesh, **When** the display shows the visual, **Then** every displayed pixel is exactly the
   pixel shown without grid warp.
2. **Given** a valid non-identity mesh, **When** the display shows the visual, **Then** each control point's picture
   position appears at its target and the picture between points follows the smooth surface; uncovered areas are black.
3. **Given** the editor is open with a display connected, **When** the user looks at the display, **Then** guide lines
   along the grid are drawn through the warp; closing the editor removes them.

---

### User Story 2 - Invalid meshes never reach the projector (Priority: P1)

A drag that would fold the picture, a stored value that is damaged, or an imported profile with a crossed grid is
rejected; the last valid mesh stays and the editor says why.

**Why this priority**: It is the second half of the acceptance criterion; a folded mesh shows a mirrored, overlapping
picture.

**Independent Test**: Feed the validator each class of invalid mesh and random meshes; apply invalid edits and stored
values and check the applied mesh did not change.

**Acceptance Scenarios**:

1. **Given** a valid mesh, **When** a point is dragged across its neighbour, **Then** the edit is refused, the point
   stays and the reason is shown.
2. **Given** a stored value that is malformed, out of range or folded, **When** the app launches, **Then** the identity
   applies.
3. **Given** an output profile file whose mesh is invalid, **When** it is imported, **Then** the import is refused with
   the field named and nothing changes.

---

### User Story 3 - Adjust precisely and accessibly (Priority: P2)

A user with VoiceOver (or anyone needing fine control) picks a point by row and column and nudges it left, right, up
or down in small steps, or resets the whole grid.

**Acceptance Scenarios**:

1. **Given** a selected point, **When** a nudge is applied, **Then** it moves one step unless the result is invalid.
2. **Given** any mesh, **When** Reset is chosen, **Then** the identity grid of the current size applies.

---

### User Story 4 - The correction is kept (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a warped grid, **When** the app relaunches, **Then** the same grid applies; it is left out of the library
   backup, erased with Settings and removed by the UI-test reset; an output profile export and import round-trips it.

### Edge Cases

- No display connected: the editor still works on the last known display shape (else 16:9); the mesh applies when a
  display connects.
- A recording is running (OUT-002 hold): the mesh changes no picture size and is not recorded, so it applies live.
- Blackout (OUT-010): the whole display stays black whatever the mesh.
- Corner pin also set: the grid-warped picture is then corner-pinned (both apply).
- A native spectrum is shown: the mesh is not applied (reported as not covered); the editor footer says so.
- The rehearsal preview (OUT-012) shows placement only, unwarped.
- Grid size change: the surface is resampled, else the identity of the new size.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-008-R1**: The app MUST hold one grid warp for the external output: columns and rows (each 3…9) and that many
  control points in picture-relative coordinates; the default is the 3 × 3 identity.
- **OUT-008-R2**: The external output MUST show the visual's picture deformed by the smooth interpolating surface
  through the control points (every control point's picture position lands on it; evenly spaced grids are the identity),
  within the visual's picture frame; areas not covered are black.
- **OUT-008-R3**: A mesh MUST be accepted only when its size, finiteness, range (−0.5…1.5), per-cell convexity and
  orientation (minimum turn ≈ 2°), surface non-folding (every drawn triangle positively oriented with positive area, the
  outline not self-crossing) and coverage (≥ 5 %) rules all hold; the validator MUST name the first failing rule.
- **OUT-008-R4**: Every input path (editor drag or nudge, stored setting, output profile import, grid size change) MUST
  pass through the validator; an invalid result MUST be refused and the last valid mesh (else the identity) kept; the
  editor MUST show and announce the reason of a refused edit.
- **OUT-008-R5**: Settings › External Display MUST offer "Grid warp…", opening an editor with the display's shape, the
  warped grid, draggable point handles, a grid-size picker (3 × 3, 5 × 5, 9 × 9), a row/column point picker with four
  nudge buttons, VoiceOver adjustable handles with spoken values, Reset and Done. While it is open, a connected display
  shows guide lines along the grid through the warp.
- **OUT-008-R6**: The grid warp MUST compose with the corner pin: grid warp inside the visual's frame first, then the
  corner pin on the whole output.
- **OUT-008-R7**: With the identity mesh and no guides, the output MUST be bit-identical to the output without grid
  warp (no extra pass runs); the warp pass itself, given the identity mesh, MUST also reproduce its input exactly.
- **OUT-008-R8**: The warp MUST apply only to external display output of projectM and the compositor visuals: never to
  the device's visualizer, recordings, still captures, the rehearsal preview; the native spectra are reported as not
  covered.
- **OUT-008-R9**: The mesh MUST persist as one device-local value (missing, malformed or invalid reads as the identity;
  the identity is stored as absent), left out of the library backup, erased with Settings, removed by the UI-test reset.
- **OUT-008-R10**: OUT-014 output profiles MUST carry a non-identity mesh as an optional field (absent = identity) and
  refuse an invalid one on import.
- **OUT-008-R11**: The warp MUST apply live, also while a recording holds the placement, and never move the visual
  between displays or touch the audio source.
- **OUT-008-R12**: A DEBUG probe MUST report the applied mesh kind, size, guides and whether the shown visual applies it.

### Key Entities

- **Grid warp**: columns, rows and control points (picture-relative); valid or not by OUT-008-R3, with a reason.
- **Warp surface**: the smooth map from the picture's unit square to the output given by the control points, drawn as a
  fine tessellated mesh.

## Success Criteria *(mandatory)*

- **OUT-008-S1**: With the identity mesh, 100 % of output pixels are identical to the output without grid warp, both
  when no pass runs and when the warp pass is forced on.
- **OUT-008-S2**: For a known warp, displayed pixels match an independent reference within 2 % of full scale at ≥ 99 %
  of covered pixels, and no pixel shows content from outside the picture.
- **OUT-008-S3**: 100 % of invalid meshes (each rule's examples and every invalid random mesh) are refused, and 100 %
  of the random meshes the validator accepts have a non-folding surface.
- **OUT-008-S4**: The device visualizer and recordings are identical with and without a mesh.
- **OUT-008-S5**: The mesh survives a relaunch and an output profile round trip in 100 % of runs.

## Assumptions

- One projector at a time (OUT-001); one stored mesh for the app (OUT-007's precedent: not per display).
- No edge blending or multi-projector setups (other rows).
- Device evidence (a real projector and curved surface) is a `{device}` task done last; simulator results are never
  device evidence.
