# Feature Specification: CAM-008 Person Silhouette Mask

**Feature Branch**: `feature/cam-008` (spec directory `241-cam-008-person-silhouette-mask`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-008-T01-T15, T17 verified on the Mac with the stand-in camera and a fixture segmenter; device task T16 `{device}` open)

**Input**: User description: "Implement CAM-008 (Person silhouette mask) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Use on-device segmentation where
supported for compositing." Acceptance, verbatim: "Supported device masks a person; unsupported path
remains usable." P2, effort XL, depends on CAM-001 (integrated)."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`CAM-008-R1…`, success criteria `CAM-008-S1…`, research decisions `CAM-008-D1…`, tasks `CAM-008-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `fda100be`)

| Area | Today | Gap for this row |
|---|---|---|
| Camera layer | `CameraLayerSource` draws the newest camera picture (`CameraFrameProvider`: the AVFoundation provider on devices, the deterministic stand-in in tests and the Simulator) with one geometry (`CameraPictureGeometry`: rotation, CAM-002 mirror, CAM-007 Fill/Fit, anchor, zoom). The picture is opaque (alpha 1), Fit's bars transparent. | No per-pixel coverage: the whole camera picture is always drawn. |
| Compositor masks | CMP-007 shape, CMP-008 gradient, CMP-009 luma and CMP-010 colour keys are coverage terms of the generic `CMPMask` block, computed from layer-picture coordinates or the layer's own colours. | None of them knows where a person is; a person mask is aligned with the *camera picture*, not with the layer picture. |
| Performance | PERF-008 power budgets and the thermal/Low Power `QualityGovernor` set the frame rate and render scale of the camera visual. | Nothing bounds an extra per-frame analysis. |
| Privacy | Camera pictures stay in memory, the newest only; nothing is written, sent or analysed (CAM-001-R9). The privacy manifest and permission catalog list the camera use. | A segmentation is an on-device analysis of the picture: it must follow the same rules. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement); each answer is
the conservative, local-first option.

- Q: What does "masks a person" mean on screen? → A: A user choice "Person mask" with three values
  (CAM-008-R1): **Off** (default; the camera picture exactly as today), **Person** (only the people
  in the camera picture are drawn; everything else in the camera layer is transparent, so the visual
  behind it shows through) and **Background** (the inverse: the people are cut out). In the Camera
  visual the layer under the camera is black, and the spectrum stays on top.
- Q: Where does the segmentation run? → A: On the device only, with the system's own person
  segmentation (public API), on the camera's pictures in memory. Nothing is sent, stored, exported
  or logged: no mask in saved frames other than its effect on the composite, never a mask file,
  never a mask in diagnostics or scenes (CAM-008-R7).
- Q: What happens where segmentation is not available? → A: The Person mask control is shown but
  disabled, with a note naming why (not supported on this device, paused while the device is warm,
  or stopped after an error), and the camera layer draws exactly as with the mask Off (CAM-008-R5).
  The stored choice is kept, so it applies again when segmentation becomes available.
- Q: Is the choice remembered? → A: Yes, as one setting for both cameras (like the CAM-007 framing),
  restored after a relaunch and included in the settings backup (FILE-005). It never starts the
  camera.
- Q: Does it follow the framing? → A: Yes: the mask is aligned with the camera picture, so the same
  rotation, mirror, Fill/Fit, anchor and zoom apply to it (CAM-008-R3).

### Session 2026-11-14 (speckit-clarify)

- Q: What does the layer show before the first mask is ready (start, camera switch)? → A: The camera
  picture unmasked (as Off), for at most the few frames before the first mask arrives. Rejected:
  showing nothing until a mask exists, which makes a start look broken when segmentation is slow.
- Q: How fresh must the mask be? → A: It may lag the picture by a bounded amount: segmentation runs
  at most on every second camera picture (every third under a power-saving budget or Low Power Mode),
  one analysis at a time, and the newest mask is reused between analyses (CAM-008-R4). A late mask is
  never waited for.
- Q: How does the device's heat count? → A: At thermal state serious or critical segmentation pauses
  (CAM-008-R6); the note says it is paused while the device is warm, the picture is drawn unmasked,
  and the mask comes back by itself when the device cools.
- Q: Are mask edges soft? → A: The mask is used as a coverage value between 0 and 1 (soft edges as
  segmentation returns them, interpolated when scaled). No extra feathering or edge controls in this
  row.
- Q: What does VoiceOver read? → A: Label "Person mask", values "Off", "Person" or "Background"; when
  disabled, the hint is the note (CAM-008-R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Only the performer over the visual (Priority: P1)

A performer turns on the Camera visual and chooses Person mask › Person. The background of the room
disappears; only the performer is drawn, over black, with the spectrum on top. Turning the device,
switching camera, mirroring or reframing keeps the silhouette aligned with the performer.

**Why this priority**: It is the row's acceptance ("supported device masks a person").

**Independent Test**: With a stand-in segmentation that returns a fixture mask, the composited
camera layer is transparent outside the masked region and equal to the unmasked picture inside it,
for several rotations, mirror and crop choices; read back from the GPU.

**Acceptance Scenarios**:

1. **Given** Camera is shown with Person mask Person on a supported device, **When** a person is in
   view, **Then** only the person is drawn from the camera picture; elsewhere the layer is
   transparent.
2. **Given** Person mask Background, **When** a person is in view, **Then** the person is cut out and
   the rest of the camera picture is drawn.
3. **Given** any mirror, rotation, Fill/Fit, anchor and zoom, **When** the mask is applied, **Then**
   the mask lines up with the picture as drawn.

---

### User Story 2 - Unsupported or paused segmentation stays usable (Priority: P1)

On a device or in a state where segmentation cannot run, the Camera visual keeps working: the
picture is drawn normally and Settings explains why the Person mask is unavailable.

**Why this priority**: It is the row's second acceptance ("unsupported path remains usable").

**Independent Test**: With a stand-in segmentation that reports "unsupported" or fails, the
composited camera layer equals the layer with the mask Off, and the Settings row is disabled with
its note.

**Acceptance Scenarios**:

1. **Given** segmentation is unsupported, **When** the user opens Settings › Camera, **Then** Person
   mask is disabled with "Person mask isn't supported on this device."
2. **Given** segmentation fails while running, **When** the next frame is drawn, **Then** the picture
   is drawn unmasked and the note says the mask stopped after an error.
3. **Given** the device is warm (thermal serious or critical), **Then** segmentation pauses, the
   picture is drawn unmasked, and the note says so; when it cools, the mask returns.

---

### User Story 3 - The choice is kept and private (Priority: P2)

The choice survives a relaunch, applies to both cameras, and never leaves the device in any form
other than the composite the user chose to save or record.

**Independent Test**: The setting round-trips through a relaunch and the settings backup; no file is
written while masking; the privacy manifest check passes.

### Edge Cases

- Camera stopped, switched or interrupted: the held mask is dropped with the picture; the next
  picture is drawn unmasked until its mask arrives.
- No person in view with Person: the camera layer is fully transparent (the visual behind shows).
- Mask size differs from the picture size: it is scaled with the picture (coverage interpolated).
- Fit's bars: still transparent whatever the mask.
- Reduce flashing: unchanged; the flash guard sees the composite.
- The stand-in camera (Simulator, UI tests): masking runs with a stand-in segmentation; the system
  segmentation may or may not run in the Simulator, and Simulator output is never device evidence.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-008-R1**: The Camera visual MUST offer a Person mask choice: Off (default), Person,
  Background. Off MUST draw exactly what the camera layer draws without this feature.
- **CAM-008-R2**: With Person, the camera layer's coverage at each point MUST be the mask's person
  coverage there (0 outside a person, 1 inside, soft between) and its colour the unmasked colour
  scaled by that coverage (premultiplied); with Background, the coverage MUST be one minus it.
- **CAM-008-R3**: The mask MUST be aligned with the camera picture and pass through the same
  rotation, mirror, Fill/Fit, anchor and zoom as the picture; Fit's bars stay transparent.
- **CAM-008-R4**: Segmentation MUST run on the device, off the drawing thread, at most one analysis
  at a time, at most on every second camera picture (every third under a reduced power budget or Low
  Power Mode); drawing MUST never wait for it and reuses the newest mask.
- **CAM-008-R5**: When segmentation is unsupported, has failed, or is paused, the camera layer MUST
  draw exactly as with Off, and the control MUST be disabled with a note naming the reason.
- **CAM-008-R6**: Segmentation MUST pause at thermal state serious or critical and resume when it
  falls below serious.
- **CAM-008-R7**: Masks MUST stay in memory only: never written to disk, exported, logged, put in
  scenes or diagnostics, or sent anywhere. Stopping or switching the camera MUST drop the held mask.
- **CAM-008-R8**: The control MUST have the accessibility label "Person mask", values "Off",
  "Person", "Background", and its note as hint when disabled.
- **CAM-008-R9**: The choice MUST be stored once for both cameras, restored after a relaunch,
  included in the settings backup, and never start the camera.

### Key Entities

- **Person mask mode**: Off, Person or Background (a setting).
- **Person mask**: a coverage bitmap aligned with one camera picture (memory only).
- **Segmentation availability**: available, unsupported, failed, or paused (warm).

## Success Criteria *(mandatory)*

- **CAM-008-S1**: With a fixture mask, every pixel of the composited camera layer outside the
  person region has coverage 0 and every pixel inside equals the unmasked picture within 1/255, for
  at least three framing cases (rotation, mirror, Fill/Fit with anchor and zoom).
- **CAM-008-S2**: With segmentation unsupported or failing, the composited camera layer equals the
  Off result within 1/255 at every pixel, and Settings shows the disabled control with its note.
- **CAM-008-S3**: Drawing never waits for segmentation; at most one analysis is in flight and at
  most one per two pictures is started (one per three when power-saving).
- **CAM-008-S4**: No file is written by masking; the privacy manifest check passes unchanged.
- **CAM-008-S5** `{device}`: On D1 with a person in view, Person shows the person and hides the
  room; the frame rate stays at or above the Camera visual's floor (30 fps).

## Assumptions

- The system's person segmentation is the only segmenter; no model is bundled.
- The Simulator has no camera; the stand-in camera and a stand-in segmentation carry the automated
  acceptance. Device behaviour is a `{device}` task.
- The mask applies to the Camera visual's camera layer; other visuals are unchanged.
