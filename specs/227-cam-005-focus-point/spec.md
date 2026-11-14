# Feature Specification: CAM-005 Camera Focus Point

**Feature Branch**: `feature/cam-005` (spec directory `227-cam-005-focus-point`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-005-T01-T11, T13, T15 verified on the Mac with the stand-in camera; T12 code done, VoiceOver action unverified; device task T14 `{device}` open)

**Input**: User description: "Implement CAM-005 (Camera focus point) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Set tap-to-focus location on
supported camera device." Acceptance, verbatim: "Tap maps view coordinates to camera focus point
correctly." P2, depends on CAM-001 (integrated); builds on CAM-002 (front camera, mirror), CAM-003
(lenses), CAM-004 (exposure lock) and CAM-007 (crop: Fill/Fit, anchor, zoom)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-005-R1…`, success criteria `CAM-005-S1…`, tasks `CAM-005-T01…`. Requirements
of other features are cited by their own IDs: CAM-001-R7, R9; CAM-002-R3; CAM-003-R6, R10;
CAM-004-R6, R7; CAM-007-R2 to R4; CAM-012 (badge, Stop camera).

The constitution's Privacy section requires a specification and a privacy review for a sensor.
Focusing changes where an already running camera focuses; it adds no sensor, no capture and no
stored data. This specification extends CAM-001's to CAM-004's review (section "Privacy review").

## Baseline: what exists today (audit of 2026-11-14, commit `95142688`)

| Area | Today | Gap for this row |
|---|---|---|
| Camera visual | Settings › Visual › "Camera" shows the chosen camera full screen under a circular spectrum, with the user's crop (Fill/Fit, anchor, zoom; CAM-007) and mirror (CAM-002). | The camera always focuses automatically on the middle of its picture. |
| Picture geometry | One platform-free geometry maps a point of the layer picture to the camera picture (crop, anchor, zoom, mirror, rotation); the shader repeats it. | Nothing maps a touch on the screen to the camera. |
| Camera device seam | CAM-004 changes the running camera's exposure through a platform-free seam that the stand-in and the real camera share. | No focus controls in the seam. |
| Visualization gestures | A single tap on the visualization shows or hides the controls. | No focus gesture. |
| Stand-in camera | Positions, lenses, exposure capability, failures. | No focus capability or focus state. |

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which gesture sets the focus point, given that a single tap already shows and hides the controls? → A: A double-tap on the Camera visual, only while the camera runs; the single tap keeps toggling the controls (CAM-005-R1, R10). The double-tap gesture exists only while the Camera visual is shown and is recognised alongside the single tap, so the single tap is never delayed; the double-tap's two taps toggle the controls twice, leaving them as they were (a first version that made the single tap wait for a possible second tap raced with existing UI tests' tap helpers and slowed the controls). Rejected: single tap (it would break the controls toggle that every user relies on) and long press (slower, and conflicts with nothing but is less discoverable than the camera-app double-tap habit).
- Q: How is the touch turned into the camera's focus point? → A: One pure mapping: the touch's position inside the picture's on-screen rect → the same platform-free picture geometry the camera layer draws with (crop mode, anchor, zoom, mirror, rotation for the interface orientation) → the camera picture point, which is the sensor's unrotated, unmirrored picture in 0…1, AVFoundation's point-of-interest space (landscape, home button on the right). Touches in Fit's bars or outside the rect are ignored; results are clamped to 0…1 (CAM-005-R2, R3). Rejected: AVCaptureVideoPreviewLayer conversion (the app draws the camera itself; there is no preview layer).
- Q: Which focus mode does a tap set, and what happens on unsupported cameras? → A: Single-shot automatic focus at the point when supported, else continuous automatic focus at the point; a camera without point-of-interest support is never configured and "This camera can't focus on a point." is shown as a short caption and spoken on the camera announcement lane, and also shown in Settings › Camera (CAM-005-R4, R5). Exposure point is not changed (CAM-004 owns exposure).
- Q: What feedback does a tap give, including for VoiceOver and Reduce Motion? → A: A 64-point ring at the touch for 1 s; it fades in and out, or appears and disappears at once with Reduce Motion. VoiceOver users get an accessibility action "Focus at centre" on the visualization (focuses at the centre of the visible picture) and the announcement "Focusing at centre" (CAM-005-R6, R7).
- Q: Is the focus point kept across lens or camera switches, stops or launches? → A: No: before a lens or position switch and on every stop the camera is returned to continuous automatic focus at the centre (0.5, 0.5); nothing is stored, so there is no new settings key (CAM-005-R8, R9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Focus where I touch (Priority: P1)

A performer points the camera at a guitarist's hands near the lens while the background is far away.
The camera keeps focusing on the background. They double-tap the hands on the screen; the camera
focuses there, and a small ring shows where.

**Why this priority**: This is the row's observable behavior.

**Independent Test**: With a camera that supports a focus point, running: a double-tap at a screen
point sets the camera's focus point to the camera-picture point shown under the finger, and a ring
appears there.

**Acceptance Scenarios**:

1. **Given** the Camera visual runs on a camera that supports a focus point, **When** the user
   double-taps a point of the picture, **Then** the camera focuses at the camera point shown under
   that screen point, whatever the crop, anchor, zoom, mirror and device orientation.
2. **Given** Fit leaves bars beside the picture, **When** the user double-taps a bar, **Then**
   nothing happens (no focus change, no ring).
3. **Given** the controls are hidden, **When** the user single-taps, **Then** the controls appear as
   before (the double-tap does not replace the single tap).

---

### User Story 2 - Unsupported camera explains its limit (Priority: P1)

A user whose camera cannot focus on a point double-taps the picture. Nothing is attempted on the
camera; the explanation "This camera can't focus on a point." is shown briefly and spoken by
VoiceOver. Settings › Camera shows the same explanation.

**Independent Test**: With a camera that has no focus point: a double-tap makes no camera
configuration and shows the explanation.

**Acceptance Scenarios**:

1. **Given** the camera cannot focus on a point, **When** the user double-taps the picture, **Then**
   no configuration of the camera is made and the explanation is shown.

---

### User Story 3 - Focus without seeing the screen (Priority: P2)

A VoiceOver user on the visualization chooses the action "Focus at centre"; the camera focuses on
the middle of the visible picture and VoiceOver says "Focusing at centre".

**Acceptance Scenarios**:

1. **Given** VoiceOver and a camera that can focus on a point, **When** the user picks the
   "Focus at centre" action, **Then** the camera focuses on the camera point shown at the centre of
   the screen and the announcement is spoken.

---

### User Story 4 - A focus point never outlives its camera (Priority: P2)

After focusing on a point, the user changes lens or camera, or the camera stops. The new camera
focuses automatically and continuously on the middle again; nothing is remembered.

**Acceptance Scenarios**:

1. **Given** a focus point is set, **When** the lens or position changes or the camera stops,
   **Then** the camera is returned to continuous automatic focus at the centre.

### Edge Cases

- No picture drawn yet (starting): a double-tap does nothing.
- The camera is busy (configuration cannot be taken): the state is unchanged, no ring, no crash.
- A camera that supports a point but not single-shot automatic focus: the point is set with
  continuous automatic focus.
- A tap exactly on a corner of the picture maps to a corner of the camera picture (0 or 1); points
  never leave 0…1.
- Reduce Motion: the ring appears and disappears without animation.
- The iPad split editor scales the output: the tap is mapped against the picture's on-screen rect.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-005-R1**: A double-tap on the Camera visual while the camera runs MUST set the camera's focus
  point to the camera-picture point shown under the touch.
- **CAM-005-R2**: The mapping MUST account for the picture's on-screen rect, the crop mode (Fill
  crops; Fit letterboxes), anchor and zoom (CAM-007), the mirror (CAM-002) and the picture's rotation
  for the device orientation; touches outside the picture (Fit's bars, outside the rect) MUST be
  ignored.
- **CAM-005-R3**: The focus point MUST be given in the camera's own coordinate space (0…1, the
  sensor's unrotated, unmirrored picture), clamped to 0…1.
- **CAM-005-R4**: Setting a point MUST happen inside one configuration of the running camera, with
  single-shot automatic focus when supported, else continuous automatic focus.
- **CAM-005-R5**: When the camera cannot focus on a point, no configuration MUST be attempted and the
  explanation "This camera can't focus on a point." MUST be shown and announced.
- **CAM-005-R6**: A small ring MUST mark the focused point on screen for about one second; with
  Reduce Motion it appears and disappears without animation.
- **CAM-005-R7**: The visualization MUST offer the accessibility action "Focus at centre" while the
  camera can focus on a point; it focuses at the centre of the screen's picture and announces
  "Focusing at centre".
- **CAM-005-R8**: Before a lens or position switch replaces the camera, and when the camera stops, a
  set focus point MUST be returned to continuous automatic focus at the centre.
- **CAM-005-R9**: The focus point MUST NOT be stored; focusing MUST NOT start, stop or restart the
  camera, change the frame loop or the audio source, or ask for permission.
- **CAM-005-R10**: The single tap MUST keep showing and hiding the controls.
- **CAM-005-R11**: The stand-in camera MUST simulate cameras with and without a focus point through
  the same focus code the real camera uses, for tests, the simulator and DEBUG UI tests.
- **CAM-005-R12**: The state shown (focus point and mode) MUST be read back from the camera.

### Key Entities

- **Focus capability**: whether the current camera can focus on a point, and which automatic focus
  modes it has.
- **Focus state**: capability, running, the mode and the point the camera reports; session state.
- **Focus tap mapping**: screen point + picture rect + picture size and rotation + crop + mirror →
  camera point or nothing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-005-S1**: For every tested combination of orientation, crop mode, anchor, zoom and mirror,
  the mapped point equals the camera point drawn under the touch within 0.001.
- **CAM-005-S2**: 100% of touches in Fit's bars or outside the picture change nothing.
- **CAM-005-S3**: On a camera without a focus point, 0 configuration attempts; the explanation shown.
- **CAM-005-S4**: After any lens switch, position switch or stop, 0 cameras keep a user focus point.
- **CAM-005-S5**: 0 new stored settings; 0 new permission prompts.

## Privacy review *(Constitution, Privacy; extends CAM-001's to CAM-004's review)*

- Sensor: the camera already in use; no new sensor.
- Focus changes only on the running camera, only by the user's gesture or action; it cannot start
  the camera. iOS's indicator and the app's camera badge are unchanged (CAM-012).
- The touch location is used once and not stored, sent, logged or analysed.

## Assumptions

- "Supported camera device" means a camera that reports focus point of interest support.
- Exposure point of interest is out of scope (CAM-004 owns exposure).
- Device verification on D1 is a `{device}` task; simulator results are never device evidence.
