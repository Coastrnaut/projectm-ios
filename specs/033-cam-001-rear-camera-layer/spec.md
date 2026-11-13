# Feature Specification: CAM-001 Rear Camera Layer

**Feature Branch**: `feature/cam-001` (spec directory `033-cam-001-rear-camera-layer`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement CAM-001 (Rear camera layer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Display live rear camera feed as
selectable visual layer." Acceptance, verbatim: "User grant shows frames; denial shows nonblocking
fallback." Depends on CMP-001 (integrated: Packages/Compositor, ADR-0013, the layer contract)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-001-R1…`, success criteria `CAM-001-S1…`, tasks `CAM-001-T01…`.

The camera is a new sensor. The constitution's Privacy section requires a separate specification
and a privacy review for it; this specification is that document, and its privacy review is the
section "Privacy review" below.

## Baseline: what exists today (audit of 2026-11-13, commit `61c926c`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Camera | Nothing. The app opens no camera, declares no camera usage description and asks for no camera permission. CaptureKit handles audio only. | Everything: a camera feed, its permission, its lifecycle. |
| Layers | CMP-001 defines the layer contract (a layer draws a whole picture per frame, linear premultiplied; transparent or last-good fallback) and a compositor, with the native spectra as layers. | No camera layer. |
| Choosing a visual | Settings › Visual chooses projectM, Circular Spectrum or Linear Spectrum. The app does not render through the compositor yet (CMP-001 left the wiring to a later row). | No way to choose a camera picture. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- (filled by /speckit-clarify)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The live rear camera behind the music (Priority: P1)

A viewer chooses "Camera" as the visual in Settings. The first time, iOS asks for camera access;
the viewer allows it. The visualizer now shows the live view from the rear camera, filling the
screen, with the circular spectrum drawn on top of it and moving with the music.

**Why this priority**: It is the row's observable behavior and the "grant shows frames" half of the
acceptance.

**Independent Test**: With a deterministic stand-in camera that delivers a solid-color picture,
choosing Camera shows that color on screen under the spectrum, and the count of shown camera frames
keeps growing.

**Acceptance Scenarios**:

1. **Given** the camera permission has never been asked, **When** the user chooses Camera in
   Settings, **Then** iOS's camera permission prompt appears (only then, never earlier), and after
   the user allows it the live camera picture appears.
2. **Given** camera access is allowed, **When** the Camera visual is on screen, **Then** each new
   camera picture is shown, scaled to fill the screen without distortion (cropped at the edges as
   needed), and the spectrum is drawn over it.
3. **Given** the Camera visual runs, **When** the user rotates the device, **Then** the picture
   stays upright and fills the screen.

---

### User Story 2 - Denied or unavailable camera never blocks the app (Priority: P1)

A viewer who denies camera access (or whose access is restricted, or whose device has no rear
camera) chooses Camera. The visualizer keeps running: the spectrum is still drawn, on black, and a
small notice says the camera is off and how to allow it in Settings. Nothing waits for an answer.

**Why this priority**: It is the "denial shows nonblocking fallback" half of the acceptance.

**Independent Test**: With a stand-in camera whose access is denied, choosing Camera shows the
spectrum and a notice; the controls, Settings and the audio source keep working and the source is
not restarted.

**Acceptance Scenarios**:

1. **Given** camera access is denied or restricted, **When** the user chooses Camera, **Then** no
   camera picture is shown, the spectrum keeps drawing, and a notice explains that camera access is
   off and that it can be allowed in Settings, with a button that opens the app's page in Settings.
2. **Given** the device has no usable rear camera, **When** the user chooses Camera, **Then** no
   permission is asked, and a notice says no rear camera is available while the spectrum keeps
   drawing.
3. **Given** the notice is shown, **When** the user taps the controls, opens Settings, pauses or
   stops, **Then** each works as before; the notice never takes focus or needs to be dismissed.
4. **Given** camera access was allowed, **When** the user revokes it in iOS Settings while the app
   is in the background and returns, **Then** the denied fallback and notice appear; the app does
   not crash.

---

### User Story 3 - The camera runs only while it is shown (Priority: P1)

The camera is a sensitive sensor. It runs only while the Camera visual is on screen in the
foreground, and iOS's camera indicator is the honest signal of that.

**Why this priority**: The constitution's privacy rules; a camera that keeps running is a defect,
not a degraded feature.

**Independent Test**: With the stand-in camera, the camera is running while the Camera visual is
shown and stops when the user picks another visual, pauses, stops, or the app goes to the
background; it starts again when the Camera visual is shown again in the foreground.

**Acceptance Scenarios**:

1. **Given** the Camera visual is shown, **When** the user chooses another visual, pauses, stops
   (back to the chooser) or the app leaves the foreground, or the window's scene disconnects,
   **Then** the camera stops at once.
2. **Given** the camera stopped because of pause or background, **When** the user resumes or
   returns to the foreground with the Camera visual chosen, **Then** the camera starts again
   without a new permission prompt.
3. **Given** another app or the system takes the camera (a call, a camera app in Split View,
   thermal pressure), **When** the camera is interrupted, **Then** the camera picture disappears
   (no frozen picture is shown as if live), the spectrum keeps drawing, a notice says the camera is
   paused by the system, and the picture returns when the interruption ends.

### Edge Cases

- The Camera visual cannot be built at all (no GPU path): the app falls back to projectM with the
  same notice the native visuals use (VIS-001-R16), naming Camera.
- The user denies the prompt that Camera triggered: the denied fallback appears in the same
  session without a relaunch.
- The app is launched again: the Camera choice is not restored; the visual chosen before Camera is
  shown, and the camera starts only when the user chooses Camera again.
- A runtime camera error: treated like an interruption (fallback and notice); never a crash.
- Reduce flashing on: the composite flash guard (CMP-001, FX-019's envelope) applies to the whole
  picture, camera included, so a flickering scene in front of the camera is limited like any other
  visual.
- The camera delivers pictures slower than the display: the newest picture is shown again; late
  pictures are dropped, never queued.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-001-R1**: Settings › Visual MUST offer "Camera" beside projectM, Circular Spectrum and
  Linear Spectrum. Choosing it shows the camera layer with the circular spectrum layer over it.
- **CAM-001-R2**: The camera layer MUST follow the CMP-001 layer contract: it draws a whole picture
  per frame in the contract's format (linear light, premultiplied, opaque where the camera picture
  is), from the newest camera picture, scaled to fill the output while keeping its aspect ratio and
  cropping the overflow equally on both sides, upright for the device orientation.
- **CAM-001-R3**: The camera picture's color MUST be converted from the camera's display encoding
  to the contract's linear light, so a known camera color reads back as the matching linear value.
- **CAM-001-R4**: The camera permission MUST be asked only when the user chooses Camera and the
  permission has never been decided, never at launch or on any other screen; the usage
  description MUST say in plain words what the camera is for and that the picture stays on the
  device.
- **CAM-001-R5**: With camera access denied or restricted, the camera layer MUST show nothing (its
  transparent fallback), the rest of the visual MUST keep running, and a non-blocking notice MUST
  say that camera access is off and how to allow it, with a button that opens the app's page in
  iOS Settings.
- **CAM-001-R6**: With no usable rear camera, no permission MUST be asked and the layer MUST show
  its fallback with a notice saying no rear camera is available.
- **CAM-001-R7**: The camera MUST run only while all of these hold: Camera is the chosen visual,
  the visualizer screen is shown, the visualization is not paused, and the app can present (in the
  foreground, scene connected). When any stops holding, the camera MUST stop before the triggering
  action returns.
- **CAM-001-R8**: An interruption or runtime error of the camera MUST show the layer's fallback
  (never a frozen picture presented as live) and a notice that the camera is paused by the system;
  the camera picture MUST return when the interruption ends, while R7 still holds.
- **CAM-001-R9**: Camera pictures MUST stay in memory on the device: never written to storage,
  never sent anywhere, never analysed for faces, people or other content, and never kept after
  they are replaced by a newer picture or the camera stops.
- **CAM-001-R10**: The app MUST NOT hide or work around iOS's camera-in-use indicator. While the
  camera runs, the app MUST NOT hide the status bar.
- **CAM-001-R11**: The Camera choice MUST NOT be restored at the next launch (R4, R7: the camera
  starts only from an explicit choice in that session).
- **CAM-001-R12**: Choosing Camera, a denial, an interruption or leaving Camera MUST NOT restart or
  change the audio source.
- **CAM-001-R13**: The camera layer MUST be testable without a camera: a deterministic stand-in
  provides pictures and every permission state (not decided then allowed, not decided then denied,
  allowed, denied, restricted, no camera), and the real permission prompt is never shown by a test.
- **CAM-001-R14**: VoiceOver MUST name the visual ("Camera visualization") and its state (live,
  access off, no camera, paused by the system); the notice MUST be readable and its Settings
  button reachable.
- **CAM-001-R15**: Per frame, the camera layer MUST NOT allocate memory of its own once running,
  wait on a lock without bound, or do I/O (the CMP-001 contract); camera pictures that arrive late
  MUST be dropped rather than queued.
- **CAM-001-R16**: The privacy policy and the App Privacy notes MUST describe the camera: used only
  on the device while the Camera visual is shown, never recorded, stored or sent, so it is not
  "collected".

### Key Entities

- **Camera feed state**: idle, requesting access, running, denied, restricted, unavailable,
  interrupted, failed. Decides whether the layer shows the camera and which notice is shown.
- **Camera picture**: the newest picture from the camera, its size and orientation; held in memory
  only until replaced.
- **Camera layer**: a CMP-001 layer that draws the newest camera picture (aspect fill) or throws
  "not ready" so the compositor shows its transparent fallback.

## Privacy review *(mandatory for a new sensor — Constitution, Privacy)*

| Question | Answer |
|---|---|
| What is captured? | The rear camera's live picture, only while the Camera visual is on screen in the foreground (R7). No audio is captured by this feature. |
| When does capture start? | Only after the user chooses Camera in Settings in this session (R4, R11) and iOS's camera permission is allowed. |
| Who sees it? | Only the person looking at the screen. iOS shows its camera indicator while the camera runs; the app never hides it (R10). |
| Is anything stored? | No. Pictures stay in memory and are replaced by the next one; nothing is written to storage, not even a thumbnail or the last frame (R9). The Camera choice itself is not stored (R11). |
| Is anything sent? | No. The app makes no network connections of its own (FR-068); the camera feature adds none. |
| Is anything analysed? | No. No face, person, text or scene detection (no Vision); pictures are only scaled and drawn (R9). |
| What if the user says no? | The app keeps working with the spectrum; a notice explains how to allow access later (R5). |
| App Store privacy label | Unchanged: Data Not Collected (data used only on the device is not collected). The owner reviews the answers in App Store Connect; this feature only documents them. |

Result: no new data collection, no storage, no transmission; the permission is asked at the point of
use with an accurate description. The review passes, conditional on R4, R7, R9 to R11 being
verified (CAM-001-S3, S4, S6) and on the device tasks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-001-S1**: With access allowed (stand-in camera on the simulator; the real camera on D1, D2
  and D3 in the device stage), the Camera visual shows camera pictures: a solid stand-in color
  reads back within 1/255 of its linear value, and the count of shown camera frames grows while
  the visual is on screen.
- **CAM-001-S2**: With access denied, restricted or no camera, the spectrum keeps drawing, the
  notice appears within 2 seconds of choosing Camera, and the controls and Settings respond with
  no extra step; the audio source is started exactly once.
- **CAM-001-S3**: In 100 % of the tested transitions (other visual, pause, stop, background, scene
  disconnect, presentation loss) the camera is stopped when the action returns, and it restarts
  only on return to the shown, foreground Camera visual.
- **CAM-001-S4**: The permission prompt is never requested by any test and never before the user
  chooses Camera; after a relaunch the camera does not start until Camera is chosen again.
- **CAM-001-S5**: An interruption makes the camera picture disappear within one frame and shows the
  notice; its end brings the picture back.
- **CAM-001-S6**: A scan of the feature's code finds no file writing, network or image-analysis use
  on the camera path; the compliance check passes.

## Assumptions

- The rear camera is the back wide-angle camera; lens choice is CAM-003, front camera and mirror
  CAM-002, exposure, focus and white balance CAM-004 to CAM-006.
- Until CMP-002 (layer stack) exists, Camera is one fixed stack (camera, then circular spectrum)
  hosted by its own compositor; CMP-002 takes over choosing and ordering layers.
- A modest camera resolution is enough for a full-screen background; the feed runs at the camera's
  default rate and the display shows the newest picture.
- Device behaviour (real permission prompt, revocation in Settings, interruption by another app,
  thermal pressure, orientation on D1-D3) is verified only in the final device stage.
