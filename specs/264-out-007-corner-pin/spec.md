# Feature Specification: OUT-007 Corner-Pin Warp

**Feature Branch**: `feature/out-007` (spec directory `264-out-007-corner-pin`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-007 (Corner-pin warp) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Map four output corners for simple single-projector correction."
Acceptance, verbatim: "Four reference points map to specified quadrilateral with no foldover." P2, size L,
depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-007-R1…`, success criteria
`OUT-007-S1…`, tasks `OUT-007-T01…`. Other features are cited by their own IDs: OUT-001 (external display
scene), OUT-002 (hot-plug, recording hold), OUT-003 (output resolution), OUT-004 (aspect correction),
OUT-005 (safe-area guides), OUT-006 (output mode), OUT-010 (output blackout), OUT-012 (output rehearsal and
its test card), REC-003 (recording), FILE-005 (library backup), FILE-011 (erase), ACC-005 (accessible
parameters).

## Baseline: what exists today (audit of 2026-11-14, commit `98623bee`)

| Area | Today | Gap for this row |
|---|---|---|
| External output (OUT-001) | The one visual view (projectM's ANGLE view, a native spectrum, Camera, Photo, Video or Text host: GLES, Metal and compositor layers) moves into the external window's slot. Nothing is drawn twice. | No geometric correction for a projector that is not square to the screen. |
| Placement (OUT-004, OUT-003) | The slot lays the visual out by bounds, centre and a horizontal 1/PAR scale (Fit, Fill, Stretch; Display or Device shape); OUT-003 changes only the visual's drawable pixel count. Changes are deferred while a recording holds the placement. | Only rectangles; no keystone or corner mapping. |
| Overlays (OUT-005, OUT-006) | Guides are device-only; the output mode decides whether the logo layer is routed to the display. | None. |
| Blackout (OUT-010) | Every slot has a black cover above the visual. | The cover must keep blacking out the whole display whatever the warp. |
| Rehearsal (OUT-012) | A test card (edges, 3 × 3 circles, centre circle, crosshair) previews a display that is not connected. | No pattern is shown on a real display for calibration. |
| Recording (REC-003) | The recorder encodes the frame as rendered (compositor output or drawable blit), never the screen. | Must stay unwarped. |
| Settings | Settings › External Display (Output, Fit, Shape, Pixel aspect, Resolution, Rehearse output); device-local `settings.externalDisplay.*` keys, left out of the backup and erased with Settings. | A corner-pin editor and its stored corners. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What do the "four output corners" map? → A: The four corners of the whole external output (the
  display's picture area, bars included) are moved to four user-chosen points; everything shown on the
  display follows the same projective (perspective) mapping, so straight lines stay straight. Corners are
  given in output-relative coordinates (0…1 across and down the display), so a resolution or mode change
  keeps the correction. The default is the identity (corners at the corners) (OUT-007-R1, R2).
- Q: What is "foldover" and how is it prevented? → A: Foldover is any part of the picture being mirrored or
  overlapping itself (a concave, self-intersecting or degenerate quadrilateral). Only quadrilaterals that
  are strictly convex, keep the corners' order and orientation (no mirroring), have no three corners in a
  line, cover at least a minimum share of the display and stay within a bounded range around it are
  accepted; an edit that would leave that set is refused and the last valid corners stay (OUT-007-R3, R4).
- Q: Does the warp reach the device screen or recordings? → A: No. It corrects one projector's geometry, so
  it applies only to the external display output. The device's own visualizer and every recording or saved
  frame are the unwarped content (a recording is content; the warp is a property of the projector's
  placement) (OUT-007-R6).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Square the picture on a tilted projector (Priority: P1)

A performer's projector sits off-axis, so the picture on the wall is a trapezoid. With the display connected
they open Settings › External Display › Corner pin…, the projector shows a test card, and they drag each of
the four corner handles until the card's edges line up with the screen. The live visual then fills the
corrected shape.

**Why this priority**: It is the row's new behaviour.

**Independent Test**: Set four target corners and check that the display output's corners land on them and
that the picture is not folded anywhere.

**Acceptance Scenarios**:

1. **Given** four valid target corners, **When** they are applied, **Then** the four output corners appear
   exactly at those points on the display and every point inside the picture stays inside the quadrilateral.
2. **Given** the editor is open with a display connected, **When** the user looks at the display, **Then**
   it shows the test card through the current warp; closing the editor shows the visual again.
3. **Given** a drag that would make the shape concave, crossed, collinear or too small, **When** it is
   attempted, **Then** the edit is refused and the last valid corners stay.

---

### User Story 2 - Adjust precisely without dragging (Priority: P1)

A user with VoiceOver, or anyone needing fine control, selects a corner and nudges it left, right, up or
down in small steps, or resets all corners.

**Why this priority**: Accessibility is part of every control in this app.

**Independent Test**: Nudge a corner with the buttons and the accessibility actions; check the stored
corners and the spoken value.

**Acceptance Scenarios**:

1. **Given** a corner, **When** a nudge is applied, **Then** it moves by one step in that direction unless
   the result is invalid (then it stays).
2. **Given** any corners, **When** Reset is chosen, **Then** all four return to the display's corners.

---

### User Story 3 - The correction is kept (Priority: P2)

**Acceptance Scenarios**:

1. **Given** corrected corners, **When** the app relaunches, **Then** the same correction applies; stored
   values that are missing, malformed or invalid read as the identity.

### Edge Cases

- No display connected: the editor still works (on the display's last known shape, else 16:9); the
  correction applies when a display connects.
- A recording is running (OUT-002 hold): the warp changes no picture size and is not part of the recording,
  so it applies live.
- Blackout (OUT-010): the whole display goes black, inside and outside the quadrilateral.
- Areas of the display outside the quadrilateral are black.
- The display changes resolution or the user changes Fit, Shape, Pixel aspect, Resolution or Output: the
  corners stay in output-relative coordinates and the warp follows.
- The rehearsal preview (OUT-012) shows placement only, unwarped.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-007-R1**: The app MUST hold one corner-pin correction for the external output: four target points
  (top-left, top-right, bottom-right, bottom-left) in output-relative coordinates; the default is the
  identity.
- **OUT-007-R2**: The external output MUST be shown through the projective mapping that takes the output's
  four corners to the four target points (straight lines stay straight), for every kind of visual, with no
  extra rendering of the visual.
- **OUT-007-R3**: A correction MUST be accepted only when its quadrilateral is strictly convex, keeps the
  corners' order and orientation, has no three nearly collinear corners, covers at least 5 % of the output
  and keeps every corner within −0.5…1.5 of the output; such a mapping has no foldover (orientation
  preserved at every point of the picture).
- **OUT-007-R4**: An edit (drag or nudge) MUST clamp the moved corner to the allowed range and MUST be
  refused when the result is invalid; the last valid correction stays in effect.
- **OUT-007-R5**: Settings › External Display MUST offer "Corner pin…", opening an editor that shows the
  output's shape with four draggable handles, per-corner nudge buttons and VoiceOver adjustable actions, a
  spoken value per corner, and Reset. While it is open, a connected display shows the OUT-012 test card
  through the current warp.
- **OUT-007-R6**: The warp MUST apply only to external display output: never to the device's visualizer,
  recordings, saved frames or the rehearsal preview.
- **OUT-007-R7**: The warp MUST apply live, inside the change, also while a recording holds the placement;
  it never moves the visual between displays or touches the audio source.
- **OUT-007-R8**: The blackout (OUT-010) MUST keep the whole display black whatever the warp; areas outside
  the quadrilateral are black.
- **OUT-007-R9**: The correction MUST persist on the device as one device-local value (missing, malformed or
  invalid reads as the identity). Like the other external display settings it is left out of the library
  backup, erased with Settings and removed by the UI-test reset.
- **OUT-007-R10**: A DEBUG probe MUST report the applied corners and whether the test card is shown (UI
  tests).

### Key Entities

- **Corner pin**: four target points in output-relative coordinates; valid or not by OUT-007-R3.
- **Projective mapping**: the 8-parameter mapping from the output's unit square to the corner pin.

## Success Criteria *(mandatory)*

- **OUT-007-S1**: The four output corners land on the four specified points within 1e-9 of the output's
  size, for every accepted correction tested.
- **OUT-007-S2**: For every accepted correction, every sampled point of the picture keeps its orientation
  (no foldover), and every interior point lands inside the quadrilateral.
- **OUT-007-S3**: 100 % of concave, crossed, collinear, too-small or out-of-range corner sets are refused.
- **OUT-007-S4**: The device visualizer and recordings are identical with and without a correction.
- **OUT-007-S5**: The correction survives a relaunch in 100 % of runs.

## Assumptions

- One projector at a time (OUT-001 shows the visual on one external display); one stored correction.
- Simple single-projector correction only: no edge blending, mesh warps or multi-projector setups.
- Device evidence (a real projector and wall) is a `{device}` task; simulator results are never device
  evidence.
