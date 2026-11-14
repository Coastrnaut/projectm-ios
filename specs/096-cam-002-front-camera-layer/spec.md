# Feature Specification: CAM-002 Front Camera Layer

**Feature Branch**: `feature/cam-002` (spec directory `096-cam-002-front-camera-layer`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CAM-002-T01-T20 verified on the Mac with the stand-in camera; device tasks T21-T23 `{device}` open)

**Input**: User description: "Implement CAM-002 (Front camera layer) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Display live front camera feed
with mirror toggle." Acceptance, verbatim: "Mirror toggle changes preview and saved output
consistently." Depends on CMP-001 (integrated); builds on CAM-001 (rear camera layer, integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-002-R1…`, success criteria `CAM-002-S1…`, tasks `CAM-002-T01…`.

The front camera is the same sensor class as CAM-001's rear camera, pointed at the viewer. The
constitution's Privacy section requires a specification and a privacy review for a sensor; this
specification extends CAM-001's review (section "Privacy review" below).

## Baseline: what exists today (audit of 2026-11-14, commit `3db86f2`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Camera visual | Settings › Visual › "Camera" (CAM-001, session only) shows the back wide-angle camera under a circular spectrum, in its own compositor. The camera starts only on that choice and runs only while the visual is shown, running and in the foreground. | Only the rear camera can be shown. |
| Mirroring | None. The camera picture is made upright and scaled to fill (aspect fill, equal crop). | No mirror, no setting. |
| Saved output | Save Frame (REC-001) captures the compositor's next composite; Record (REC-003) encodes each composite through the compositor's output pass; an external display (OUT-001) shows the same host view. All three read the one composite. | Nothing to change in the outputs, provided the mirror is part of the composite. |
| Indicator | CAM-012's "Camera on" badge with Stop camera, shown while the feed is starting or running; the status bar is never hidden while Camera is shown. | The badge does not say which camera runs. |
| Permission | One iOS camera permission covers every camera. FILE-013's catalog, notice view and `NSCameraUsageDescription` say "rear camera". | The usage text does not cover the front camera. |
| Scenes and cues | Camera is never recorded in scenes or show cues (the visual chosen before Camera is recorded). | Nothing: the camera position and mirror follow the same rule. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Is the front camera a new visual or a choice on the Camera visual? → A: A choice on the Camera visual: when Camera is the chosen visual, Settings shows "Camera: Back / Front" (CAM-002-R1). One camera visual, one capture session at most (the camera layer kind allows one instance), one badge and one Stop camera. Rejected: a fifth visual "Front Camera" (duplicates every CAM-001 and CAM-012 rule and lets two camera visuals compete).
- Q: What does the mirror toggle default to? → A: On for the front camera, off for the rear camera, each remembered separately (CAM-002-R3). A front camera that is not mirrored feels wrong to most people (the selfie convention); a mirrored rear camera turns text backwards.
- Q: What does "saved output" show when the mirror is on? → A: Exactly what the screen shows. Save Frame, Record and the external display all show the picture as mirrored or not on screen (CAM-002-R4). The roadmap's "consistently" rules out the camera-app habit of saving an unmirrored picture behind a mirrored preview.
- Q: Are the camera position and the mirror settings remembered across launches? → A: Yes, as ordinary settings; they never start the camera (CAM-002-R6). The Camera choice itself stays session only (CAM-001-R11), so a remembered "Front" only decides which camera runs the next time the user chooses Camera.
- Q: Are the position and mirror stored in scenes or show cues? → A: No. Camera is session only and never recorded in scenes or cues (CAM-001, SCN-001 rules); its position and mirror follow it (CAM-002-R6).
- Q: What happens while the camera is switched? → A: The picture goes to the visual's fallback (the spectrum on black) until the first picture from the newly chosen camera arrives; a picture from the old camera is never drawn after the switch, and the audio source keeps running (CAM-002-R7). The "Camera on" badge stays, because a camera is still being used. Rejected: holding the old camera's last picture (a stale, possibly differently mirrored picture presented as live).
- Q: Does the usage description change? → A: Yes: "The Camera visual shows the live view from the front or rear camera you choose, behind the visualization. The picture stays on your device: it is never sent, and it is saved only when you save a frame or record the visualization yourself." (CAM-002-R9). It names both cameras and corrects "never recorded", which REC-001 and REC-003 made inaccurate for a user's own saves.
- Q: Does the badge name the camera? → A: Yes: "Camera on" for the rear camera (unchanged), "Front camera on" for the front camera; Stop camera is unchanged (CAM-002-R8).

### Session 2026-11-14 (speckit-clarify)

- Q: Does Mirror flip the whole visual or only the camera picture? → A: Only the camera picture. The spectrum and anything else drawn over it keep their orientation, so the spectrum still runs low to high clockwise from the top (CAM-002-R3). Flipping the whole composite would reverse the spectrum and any Text visual words.
- Q: Where are the camera choice and Mirror offered: in Settings only, or also in the visualizer's controls? → A: In Settings only, in a "Camera" section shown while Camera is the chosen visual (CAM-002-R1). The visualizer keeps CAM-012's badge with Stop camera; a quick switch in the controls can come with CMP-015 or CAM-003 (lens selection), which also add camera controls.
- Q: How long may the fallback last after a camera switch before the user is told something is wrong? → A: The badge stays "starting" until the new camera delivers; if it does not start, the usual unavailable or "paused by the system" notice appears (CAM-002-R7). No extra timer: the camera's own failure reports end the wait, and the device stage measures the switch time on D1-D3 (CAM-002-S7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The front camera behind the music, mirrored like a mirror (Priority: P1)

A viewer chooses Camera, then "Front" under Camera in Settings. The visualizer shows the live view
from the front camera, mirrored by default so that raising the right hand moves the picture's
right side, with the circular spectrum on top. The badge says "Front camera on".

**Why this priority**: It is the row's observable behavior.

**Independent Test**: With a deterministic stand-in camera, choosing Camera › Front shows the
stand-in picture, the badge reads "Front camera on", and the shown-frame count grows.

**Acceptance Scenarios**:

1. **Given** Camera is chosen and camera access is allowed, **When** the user picks Front, **Then**
   the front camera's picture is shown mirrored, filling the screen without distortion, with the
   spectrum over it, and the badge reads "Front camera on".
2. **Given** the front camera is shown, **When** the user rotates the device, **Then** the picture
   stays upright, fills the screen and stays mirrored.
3. **Given** camera access was never decided, **When** the user chooses Camera with Front picked,
   **Then** iOS's prompt appears only then, exactly as for the rear camera.

---

### User Story 2 - The mirror toggle, and saved output that matches the screen (Priority: P1)

The viewer turns Mirror off and on. The picture flips left to right at once. A frame saved with
Save Frame, a video made with Record and an external display all show the same orientation as the
screen at that moment.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: With a stand-in picture that has a marker in its top-left corner, for each
mirror setting the marker is on the same side in the composed screen picture, in a saved frame
and in the frame a recording encodes, read from pixels.

**Acceptance Scenarios**:

1. **Given** the front camera is shown with Mirror on, **When** the user turns Mirror off, **Then**
   the picture flips left to right from the next frame, without a restart of the camera or the
   audio source.
2. **Given** any camera and mirror setting, **When** the user saves a frame, records or shows the
   visual on an external display, **Then** the saved, recorded or external picture has the same
   left-right orientation as the screen.
3. **Given** the user set Mirror for the front camera, **When** they switch to Back and then to
   Front again, **Then** each camera shows its own remembered mirror setting.

---

### User Story 3 - Switching cameras safely (Priority: P1)

The viewer switches between Back and Front while the Camera visual runs, or opens the app on a
device that has only one of the cameras.

**Why this priority**: Switching must never show a wrong picture, crash or restart the audio; a
missing camera must never block the app.

**Independent Test**: With the stand-in camera, switching position while running shows only
pictures from the chosen camera, keeps the source running (started once), and a missing front
camera shows the "no front camera" notice.

**Acceptance Scenarios**:

1. **Given** the Camera visual runs, **When** the user switches between Back and Front, **Then** no
   picture from the previous camera is shown after the switch, the spectrum keeps drawing, the
   badge stays, and the audio source is not restarted.
2. **Given** the device has no front camera, **When** the user picks Front, **Then** no permission
   is asked for it, the spectrum keeps drawing and a notice says no front camera is available.
3. **Given** camera access is denied or restricted, **When** the user picks Front, **Then** the
   same denied or restricted notice as for the rear camera (FILE-013's catalog notice, with Open
   Settings) is shown.

### Edge Cases

- Position or mirror changed while the visual is paused, in the background or not shown: only the
  setting changes; the camera starts with it when it next runs.
- Position changed while the camera is interrupted or failed: the new camera is tried when the
  visual runs; the notice follows the new attempt.
- Position changed during the permission prompt: the answer applies to the camera chosen last.
- Stop camera (CAM-012) while the front camera runs: the camera stops before the action returns,
  as for the rear camera.
- Reduce flashing: the composite flash guard applies to the whole picture, either camera.
- The front camera delivers a different size or frame rate than the rear: aspect fill and the
  newest-picture rule apply unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-002-R1**: When Camera is the chosen visual, Settings MUST offer, in a "Camera" section, a
  camera choice "Back" or "Front" (default Back) and a "Mirror" switch for the chosen camera. The
  choice applies to the Camera visual; there is no separate front camera visual.
- **CAM-002-R2**: With Front chosen, the Camera visual MUST show the front camera's live picture
  under the circular spectrum with every CAM-001 rule (layer contract, linear color, aspect fill,
  upright for the device orientation, transparent fallback, run only while shown, never stored,
  sent or analysed).
- **CAM-002-R3**: Mirror MUST flip the camera picture left to right about its vertical center
  line, after it is made upright and before it is scaled to fill, so that the crop stays centered.
  Only the camera picture is flipped; layers drawn over it (the spectrum) are not. Its default MUST be on for the front camera and off for the rear camera, and each camera MUST
  keep its own setting.
- **CAM-002-R4**: The mirror MUST be applied in one place, the camera layer, so that the screen,
  a saved frame (REC-001), a recording (REC-003) and an external display (OUT-001) all show the
  same left-right orientation for the same moment.
- **CAM-002-R5**: Changing Mirror MUST take effect from the next frame without stopping the camera,
  asking for permission or touching the audio source.
- **CAM-002-R6**: The camera position and the two mirror settings MUST be stored as user settings
  (cleared with the other settings by the UI-test reset) and MUST NOT start the camera; they MUST
  NOT be recorded in scenes or show cues (Camera is never recorded there).
- **CAM-002-R7**: Switching the camera while the visual runs MUST NOT restart the audio source, MUST
  NOT draw any picture from the previously chosen camera after the switch, and MUST show the
  layer's fallback until the newly chosen camera delivers a picture. If the new camera cannot
  start, the usual unavailable or paused notice MUST appear (CAM-001-R6, R8).
- **CAM-002-R8**: While the front camera is starting or running, the in-app badge MUST read "Front
  camera on" (the rear camera keeps "Camera on"), keep Stop camera, and the status bar MUST NOT be
  hidden (CAM-001-R10, CAM-012).
- **CAM-002-R9**: The camera usage description, the permission catalog and the privacy policy MUST
  describe both cameras and the user's own saves accurately (text in Clarifications), and the
  permission catalog check MUST pass.
- **CAM-002-R10**: With no front camera, no permission MUST be asked and the notice MUST say "No
  front camera is available. Showing the spectrum only."; denied and restricted MUST show FILE-013's
  catalog notices unchanged.
- **CAM-002-R11**: VoiceOver MUST read the camera choice ("Camera", value "Back" or "Front"), the
  Mirror switch ("Mirror", on or off) and the badge ("Front camera on" or "Camera on", value Live or
  Starting).
- **CAM-002-R12**: The stand-in camera MUST support both positions, a missing front camera and an
  asymmetric test picture, so every requirement above is testable without a camera.

### Key Entities

- **Camera position**: back or front; a stored setting; decides which camera the Camera visual
  uses.
- **Mirror setting**: on or off, one per position; a stored setting; decides whether the camera
  layer flips the upright picture.
- **Camera picture**: CAM-001's newest picture, now also marked with the position it came from, so
  a picture from the other camera is never drawn.

## Privacy review *(Constitution, Privacy; extends CAM-001's review)*

| Question | Answer |
|---|---|
| What is captured? | The chosen camera's live picture (front or rear), only while the Camera visual is on screen in the foreground (CAM-001-R7). The front camera usually shows the viewer's face; that changes nothing below. |
| When does capture start? | Only after the user chooses Camera in this session and iOS's camera permission is allowed. A stored "Front" never starts the camera by itself (R6). |
| Who sees it? | The person at the screen, and anyone watching an external display the user connected. iOS's indicator and the app's "Front camera on" badge are shown (R8). |
| Is anything stored? | Pictures stay in memory. They reach a file only when the user saves a frame or records, exactly as shown (R4, REC-001, REC-003). The position and mirror settings are stored; they hold no picture. |
| Is anything sent? | No. No network use is added. |
| Is anything analysed? | No. No face or person detection; the picture is only flipped, scaled and drawn. Face landmarks are CAM-009, with their own consent gate. |
| What if the user says no? | The visual keeps running with the spectrum and the catalog notice (R10). |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: no new data collection, storage or transmission; the usage text becomes more accurate
(R9). The review passes, conditional on R4, R6 to R8 and R10 being verified and on the device
tasks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-002-S1**: For each of the four combinations (front or rear, mirror on or off) and each of
  the four picture turns, the camera layer shows the expected side of the camera picture at the
  expected place on screen, checked at every corner and the center.
- **CAM-002-S2**: With an asymmetric stand-in picture, in 100 % of the tested settings (mirror on
  and off), the marker is on the same side in the screen's composed picture, a saved frame and the
  frame a recording encodes.
- **CAM-002-S3**: Turning Mirror changes the shown side from the next frame; the camera's start
  count and the audio source's start count do not change.
- **CAM-002-S4**: Switching cameras while running shows no picture from the previous camera in any
  later frame, and the source is started exactly once.
- **CAM-002-S5**: Choosing Camera › Front and toggling Mirror in Settings shows the badge "Front
  camera on" and the controls' values (Front; Mirror on, then off) within 5 seconds each.
- **CAM-002-S6**: The permission catalog check, the compliance check and the privacy manifest
  check pass; no file writing, network or image analysis is added to the camera path.
- **CAM-002-S7** (device stage): on D1-D3 the real front camera shows an upright, mirrored
  picture in portrait and landscape, a saved frame and a recording match the screen, and a switch
  between cameras shows the new camera within 2 seconds.

## Assumptions

- The front camera is the front wide-angle camera; lens choice is CAM-003, exposure, focus and
  white balance CAM-004 to CAM-006, crop behaviour on rotation CAM-007, face landmarks CAM-009.
- One camera runs at a time; there is no picture-in-picture of both cameras.
- Device behaviour (the real front camera, its orientation on D1-D3, switching on hardware, iOS's
  indicator) is verified only in the final device stage.
