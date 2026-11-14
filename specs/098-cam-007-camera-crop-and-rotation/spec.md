# Feature Specification: CAM-007 Camera Crop and Rotation

**Feature Branch**: `feature/cam-007` (spec directory `098-cam-007-camera-crop-and-rotation`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-007-T01-T14 verified on the Mac with the stand-in camera; device tasks T15-T16 `{device}` open)

**Input**: User description: "Implement CAM-007 (Camera crop and rotation) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Map camera aspect, orientation
and crop to layer transform." Acceptance, verbatim: "Portrait-to-landscape rotation preserves
chosen crop behavior." Depends on CAM-001 (integrated); builds on CAM-002 (front camera and
mirror, integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-007-R1…`, success criteria `CAM-007-S1…`, tasks `CAM-007-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `d964e8d`)

The row's gap status is "Gap candidate". The audit confirms a partial gap.

| Area | Today | Gap for this row |
|---|---|---|
| Fit | The camera layer always fills the layer picture: the upright camera picture is scaled to cover it, keeping its aspect ratio, and the overflow is cropped equally on both sides (CAM-001-R2, `CameraPictureGeometry`). | No choice: the user cannot see the whole picture, nor choose which part a crop keeps. |
| Orientation | The camera's picture rotation (0, 90, 180 or 270 degrees to upright) follows the device through the system's horizon-level rotation angle, stored with each picture; the layer turns the picture upright. | None: rotation already reaches the layer. |
| Rotation of the screen | The layer picture takes the drawable's size every frame, and the fill is recomputed every frame from the picture size, its rotation and the layer size. | Nothing to add for Fill with a centered crop; a user choice must survive the same recomputation. |
| Mirror | CAM-002 flips the upright picture in the same geometry and the same shader arithmetic. | A crop choice must combine with the mirror without distorting either. |
| Outputs | The screen, a saved frame (REC-001), a recording (REC-003) and an external display (OUT-001) read one composite. | Nothing, provided the crop lives in the camera layer. |
| Scenes and cues | Camera, its position and mirror are never recorded in scenes or show cues. | The crop settings follow the same rule. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is the "chosen crop behavior"? → A: A user choice of three parts (CAM-007-R1): **Fit mode** "Fill" (default; today's behavior: the picture covers the screen, the overflow is cropped) or "Fit" (the whole picture is shown, with bars where it does not reach); **Anchor** "Center" (default), "Top" or "Bottom": which part of the picture a crop keeps; **Zoom** 1× (default), 1.5×, 2× or 3×. With the defaults the picture is exactly what CAM-001 and CAM-002 show today.
- Q: What does the anchor mean exactly? → A: The anchor is a point of the upright, possibly mirrored picture: the middle of its top edge (Top), its center (Center) or the middle of its bottom edge (Bottom). That point is always shown at the same relative place of the screen (top middle, center or bottom middle), whatever the screen's shape, the camera's turn, the mode and the zoom (CAM-007-R3). This is how "preserves the chosen crop behavior" is made measurable.
- Q: What do the Fit bars look like? → A: Transparent in the camera layer, so what lies under the camera shows through; in the Camera visual that is the black background, so the bars are black on screen, in saved frames and in recordings (CAM-007-R4). Rejected: a colored or blurred fill (an extra design choice and GPU cost with no request for it).
- Q: Is the choice stored per camera or once for both? → A: Once for both cameras (CAM-007-R6). Framing is about the screen and the show, not about the sensor; the mirror is per camera because of the selfie convention, which does not apply to framing. Switching cameras keeps the framing.
- Q: Does zoom use the camera's optical or digital zoom? → A: No. Zoom is a crop of the camera picture in the layer (CAM-007-R5); the camera's own settings are untouched, so the capture session never restarts and lens choice stays with CAM-003.
- Q: Where is the control? → A: In CAM-002's Settings "Camera" section, shown only while Camera is the chosen visual: a "Crop" mode picker (Fill / Fit), an "Anchor" picker (Center / Top / Bottom) and a "Zoom" picker (1×, 1.5×, 2×, 3×) (CAM-007-R7).

### Session 2026-11-14 (speckit-clarify)

- Q: Do Anchor and Zoom also apply in Fit, or only in Fill? → A: In both modes (CAM-007-R2, R3). In Fit the anchor decides where the whole picture sits (Top: against the top edge, bars below), and a zoom above 1× enlarges it around the anchor. One rule for both modes keeps the controls always meaningful and the acceptance test uniform. Rejected: disabling Anchor and Zoom in Fit (controls that change meaning with the mode).
- Q: Is a change of framing animated? → A: No. A new choice, and a rotation, take effect from the next frame without an animated transition (CAM-007-R5). An animation adds motion that Reduce Motion would have to suppress and hides nothing the user needs; the system's own rotation animation of the view is unchanged.
- Q: What does VoiceOver read for the controls? → A: Labels "Crop", "Anchor" and "Zoom"; values "Fill" or "Fit", "Center", "Top" or "Bottom", and "1 times", "1.5 times", "2 times" or "3 times" (CAM-007-R7). The "×" sign is read inconsistently, so the zoom value is spelled out.
- Q: Does the external display get its own framing? → A: No. The external display shows the same composite as the screen (OUT-001), so it shows the screen's framing; it is computed for the visual's own picture size (CAM-007-R8). A separate framing per output would break the one-composite rule that CAM-002 relies on.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The framing I chose survives turning the device (Priority: P1)

A performer sets the Camera visual to show their face near the top of the picture (Fill, Top,
1.5×), then turns the phone from portrait to landscape on a stand. The picture stays upright,
undistorted, still fills the screen, and the top of the picture is still at the top of the screen
with the same zoom.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: With a deterministic stand-in camera with an asymmetric picture, composing
the Camera visual at a portrait and then a landscape size with each crop choice keeps the
picture's anchor point at the same relative place, with no stretch, and the Fill result covers
the whole output; read from pixels.

**Acceptance Scenarios**:

1. **Given** Camera is shown with Fill, **When** the device turns from portrait to landscape,
   **Then** the picture still covers the screen, is upright, keeps its proportions, and the anchor
   point stays at the same relative place.
2. **Given** Camera is shown with Fit, **When** the device turns, **Then** the whole picture stays
   visible, upright and undistorted, with bars where it does not reach.
3. **Given** a zoom of 2×, **When** the device turns, **Then** the picture is still twice as large
   as the plain Fill (or Fit) picture at the new screen shape.

---

### User Story 2 - Choosing Fill or Fit, an anchor and a zoom (Priority: P1)

The viewer opens Settings › Camera and picks Fit to see the whole camera picture, or Fill with an
anchor and a zoom to frame it.

**Why this priority**: The acceptance speaks of a chosen behavior; the user must be able to choose.

**Independent Test**: In Settings with the stand-in camera, choosing Fit, Top and 2× shows each
value in the controls, the choice is remembered after a relaunch, and the camera never restarts.

**Acceptance Scenarios**:

1. **Given** Camera is the chosen visual, **When** the user opens Settings, **Then** the Camera
   section shows Crop (Fill), Anchor (Center) and Zoom (1×).
2. **Given** the Camera visual runs, **When** the user changes any of them, **Then** the picture
   changes from the next frame without restarting the camera or the audio source.
3. **Given** a crop choice was made, **When** the app is relaunched, **Then** the choice is kept,
   and it applies to both cameras.

---

### User Story 3 - Saved output matches the screen (Priority: P2)

A frame saved, a recording and an external display show the same framing as the screen.

**Why this priority**: The outputs already read one composite; this keeps it that way.

**Independent Test**: The crop is part of the camera layer; the composite, a saved frame and a
recorded frame show the anchor at the same place.

**Acceptance Scenarios**:

1. **Given** any crop choice and mirror, **When** the user saves a frame or records, **Then** the
   saved picture has the same framing as the screen.

### Edge Cases

- Mirror on with any crop: the anchors are on the vertical center line, so the mirror keeps them
  in place; the picture is flipped, not shifted.
- Fit with a zoom above 1×: the picture is enlarged around the anchor and may then be cropped on
  one axis; it is never stretched.
- Fit with Top or Bottom: the whole picture sits against that edge, with the bars on the other
  side.
- Fill when the picture and the screen have the same shape: nothing is cropped at 1×; Top and
  Bottom then look like Center.
- Fill where the overflow is horizontal (a landscape picture on a portrait screen): Top and Bottom
  only matter once the zoom crops vertically too.
- Degenerate sizes (no picture yet, zero-size screen): the whole picture with its rotation, as
  today.
- A camera switch or a stop: the crop choice is a setting; it applies to whichever camera delivers.
- Reduce flashing: unchanged; the guard sees the composite.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-007-R1**: The Camera visual MUST offer a crop choice made of a mode (Fill, default; Fit),
  an anchor (Center, default; Top; Bottom) and a zoom (1×, default; 1.5×; 2×; 3×). With the
  defaults the picture MUST be identical to CAM-001's and CAM-002's aspect fill with a centered
  crop.
- **CAM-007-R2**: The camera picture MUST be made upright by its rotation (0, 90, 180 or 270
  degrees), mirrored when the mirror is on (CAM-002), then scaled by one factor in both
  directions (no stretch): Fill scales it to cover the layer picture, Fit to lie wholly inside it,
  and the zoom multiplies that factor.
- **CAM-007-R3**: The anchor point of the upright picture (middle of the top edge, center, or
  middle of the bottom edge) MUST be shown at the same relative point of the layer picture (top
  middle, center or bottom middle) for every layer size, rotation, mirror, mode and zoom. In Fill
  the shown part MUST never leave the picture (the layer is always covered).
- **CAM-007-R4**: Where Fit leaves part of the layer picture uncovered, the camera layer MUST be
  transparent there.
- **CAM-007-R5**: Changing the crop choice MUST take effect from the next frame without stopping
  the camera, changing its configuration, asking for permission or touching the audio source, and
  without an animated transition.
- **CAM-007-R6**: The crop choice MUST be stored once for both cameras as user settings, cleared
  with the other settings by the UI-test reset, allowed by the device privacy check, never start
  the camera, and never be recorded in scenes or show cues. Unknown stored values MUST read as the
  defaults.
- **CAM-007-R7**: Settings' Camera section (shown only while Camera is the chosen visual) MUST
  offer "Crop" (Fill / Fit), "Anchor" (Center / Top / Bottom) and "Zoom" (1× / 1.5× / 2× / 3×),
  with VoiceOver labels "Crop", "Anchor" and "Zoom" and values as in Clarifications (zoom spelled
  "1.5 times").
- **CAM-007-R8**: The crop MUST be applied in one place, the camera layer, so the screen, a saved
  frame, a recording and an external display show the same framing (the external display shows
  the screen's composite; it has no framing of its own).
- **CAM-007-R9**: The transform from camera picture to layer picture MUST be a pure calculation
  testable without a graphics device, on every platform the packages' tests run on, and the
  layer's drawing MUST follow it exactly.

### Key Entities

- **Crop choice**: mode (Fill or Fit), anchor (Center, Top or Bottom) and zoom (1, 1.5, 2 or 3);
  stored settings; shared by both cameras.
- **Camera picture geometry**: the shown part of the upright camera picture (its fraction of the
  picture's width and height and the position of the layer's top-left corner in it), with the
  rotation and mirror; recomputed every frame from the picture size, the layer size and the crop
  choice.

## Privacy review *(Constitution, Privacy; extends CAM-001's and CAM-002's reviews)*

| Question | Answer |
|---|---|
| What is captured? | Unchanged: the chosen camera's live picture while the Camera visual is shown. |
| Is anything stored? | Three settings (mode, anchor, zoom); no picture. |
| Is anything sent or analysed? | No. The picture is only scaled, cropped and drawn; no detection of faces or people decides the crop. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: no new data collection, storage of pictures or transmission. The review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-007-S1**: For camera pictures 1920×1080 and 1080×1920, each of the four turns, mirror on
  and off, layer shapes of a portrait phone, a landscape phone and a 4:3 tablet, and every mode,
  anchor and zoom: the picture is shown with equal scale in both directions (aspect error below
  0.1 %), Fill covers the whole layer, Fit at 1× shows the whole picture, the anchor point lands
  on its relative layer point, and the scale relative to plain Fill (or Fit) equals the zoom.
- **CAM-007-S2**: With an asymmetric stand-in picture, in the composed frame at a portrait and then
  a landscape size, the picture's anchor point and its center lines are at the predicted relative
  positions (within 2 pixels at 64-pixel sizes) for each mode, read from pixels.
- **CAM-007-S3**: With the default choice the picture is identical to before (the existing camera
  geometry and pixel tests pass unchanged).
- **CAM-007-S4**: Choosing Fit, an anchor and a zoom in Settings shows each value in the controls
  within 5 seconds, and the choice is kept through a relaunch.
- **CAM-007-S5**: Changing the crop choice while the camera runs never changes the camera's start
  count.
- **CAM-007-S6** (device stage): on D1-D3, with each mode, turning the device between portrait and
  landscape keeps the framing as chosen, undistorted and upright, for both cameras; a saved frame
  matches the screen.

## Assumptions

- The rotation angle reaching the layer is correct for the device's orientation (CAM-001, CAM-002;
  device stage). This feature does not change how it is obtained.
- Free pan (dragging the picture) and pinch zoom are out of scope; tap-to-focus is CAM-005, lens
  choice CAM-003, person masks CAM-008.
- Device behavior is verified only in the final device stage.
