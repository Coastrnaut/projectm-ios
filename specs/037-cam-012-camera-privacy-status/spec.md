# Feature Specification: CAM-012 Camera Privacy Status

**Feature Branch**: `feature/cam-012` (spec directory `037-cam-012-camera-privacy-status`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement CAM-012 (Camera privacy status) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Show persistent camera-active
indicator in app and explicit stop." Acceptance, verbatim: "Stop releases session and returns to
fallback visual without freeze." Depends on CAM-001 (integrated: the session-only Camera visual,
`specs/033-cam-001-rear-camera-layer`, ADR-0017)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-012-R1…`, success criteria `CAM-012-S1…`, tasks `CAM-012-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `79ecdbf`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today (CAM-001) | Gap for this row |
|---|---|---|
| Knowing the camera is on | iOS's own camera-in-use indicator (the status bar is never hidden while Camera is shown, CAM-001-R10). The visual's VoiceOver value says "Live". | No indicator of the app's own; nothing visible says "the camera is on" inside the visualization. |
| Turning the camera off | Pause, Stop (audio), backgrounding, or opening Settings and choosing another visual. | No one-tap control that turns the camera off. |
| After the camera stops | The Camera visual keeps drawing the spectrum over the camera layer's transparent fallback. | No defined return to a non-camera visual. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which visual does Stop camera return to? → A: The visual chosen before Camera: the stored visual choice, which Camera never overwrites (CAM-001-R11), so projectM when none was ever chosen (CAM-012-R5). Rejected: always the circular spectrum (it would overwrite the user's stored choice, a new persisted state against R8) and staying on the Camera visual with the camera off (Settings would show Camera chosen while it is off, and choosing it again would not be a change).
- Q: Is the indicator shown while the camera is starting, or only once pictures arrive? → A: Starting and running (value "Starting" or "Live"). The capture hardware may already be on while the session starts, so the privacy-conservative answer shows it then too; while iOS's permission prompt is up, no indicator (the camera is not on) (CAM-012-R1).
- Q: Where is Stop camera offered? → A: On the indicator itself, a "Stop camera" button inside the badge, so it is reachable in one tap whenever the camera is on, controls shown or not (CAM-012-R3). No second copy in the controls panel: one place to look, and nothing for the controls' hide timer to hide.
- Q: Does Stop camera wait for the camera hardware to finish shutting down? → A: No main-thread wait. Stop returns only after the camera feed refuses new pictures, the held picture is dropped and the feed reports idle; the capture session's own shutdown is sent to its queue at once (CAM-001's provider), because blocking the main thread for it could freeze the picture. A device task (CAM-012-S5) checks that iOS's indicator turns off within a second (CAM-012-R4).
- Q: After Stop camera, can pause/resume or returning from the background start the camera again? → A: No. Stop camera leaves the Camera visual; only choosing Camera again in Settings starts it (CAM-012-R6), the same rule as CAM-001-R4 and R11.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See at a glance that the camera is on (Priority: P1)

A viewer has chosen the Camera visual. While the camera actually delivers pictures, a small
"Camera on" badge with a camera symbol stays on screen over the visualization, whether or not the
controls are shown. When the camera stops for any reason (pause, the app going to the background,
another app taking the camera), the badge disappears; it comes back only when the camera runs again.

**Why this priority**: It is the "persistent camera-active indicator" half of the row: the viewer
always knows when the app uses the camera.

**Independent Test**: With the stand-in camera, the badge is present exactly while the camera feed
is running, and absent while it is idle, denied, interrupted or paused.

**Acceptance Scenarios**:

1. **Given** Camera is chosen and access is allowed, **When** camera pictures arrive, **Then** the
   "Camera on" badge is shown and stays when the controls hide.
2. **Given** the badge is shown, **When** the user pauses, the app goes to the background, or the
   system interrupts the camera, **Then** the badge disappears; **When** the camera runs again,
   **Then** it reappears.
3. **Given** camera access is denied or there is no rear camera, **When** Camera is chosen,
   **Then** no badge is shown (only CAM-001's notice).

---

### User Story 2 - Stop the camera with one tap (Priority: P1)

The badge carries a "Stop camera" button. Tapping it turns the camera off at once, the badge
disappears, and the visualizer goes back to the visual the viewer had before choosing Camera. The
music keeps playing and the picture keeps moving; nothing freezes. The camera stays off until the
viewer chooses Camera again in Settings.

**Why this priority**: It is the "explicit stop" half of the row and its acceptance criterion.

**Independent Test**: With the stand-in camera, tapping Stop camera stops the feed exactly once,
drops the last camera picture, removes the badge, shows the previous visual, keeps rendering and
does not restart the audio source.

**Acceptance Scenarios**:

1. **Given** the badge is shown, **When** the user taps Stop camera, **Then** the camera is stopped
   before the badge disappears, the last camera picture is dropped, and the previous visual is
   shown and keeps animating.
2. **Given** the camera was stopped with Stop camera, **When** the user pauses and resumes, or the
   app returns from the background, **Then** the camera does not start again.
3. **Given** the camera was stopped with Stop camera, **When** the user chooses Camera again in
   Settings, **Then** the camera starts and the badge returns.
4. **Given** audio is playing, **When** the user taps Stop camera, **Then** the audio source is not
   restarted or interrupted.

### Edge Cases

- Stop camera is tapped while the camera is starting: it stops the same way; nothing restarts it.
- The visual chosen before Camera is projectM (or nothing was ever chosen): Stop camera returns to
  projectM, the default.
- The previous visual cannot be created on this device: the existing "not available, showing
  projectM" notice applies (VIS-001-R16); the camera stays off.
- Stop camera tapped twice quickly: the second tap does nothing (the badge is already gone).
- The visualizer is paused: the camera is already off, so no badge and no Stop camera are shown.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-012-R1**: While the camera feed is starting or running, the visualizer MUST show a "Camera
  on" indicator with a camera symbol. It MUST be driven by the camera feed's actual state, not by
  the visual choice, and MUST stay visible when the controls hide.
- **CAM-012-R2**: The indicator MUST disappear as soon as the feed stops running for any reason
  (Stop camera, pause, audio stop, background, scene disconnect, presentation loss, interruption,
  failure, leaving Camera) and MUST reappear only when the feed runs again.
- **CAM-012-R3**: The indicator MUST offer a "Stop camera" button.
- **CAM-012-R4**: Stop camera MUST stop the camera feed before the indicator is removed, drop the
  last camera picture, and release the Camera visual.
- **CAM-012-R5**: After Stop camera the visualizer MUST show the fallback visual: the visual chosen
  before Camera (projectM when none), and it MUST keep rendering with no frozen picture.
- **CAM-012-R6**: After Stop camera the camera MUST NOT start again until the user chooses Camera
  again in Settings.
- **CAM-012-R7**: Stop camera MUST NOT restart, stop or change the audio source.
- **CAM-012-R8**: Stop camera MUST NOT write any new stored state (the Camera choice stays
  session-only, CAM-001-R11).
- **CAM-012-R9**: VoiceOver MUST read the indicator as "Camera on" with its state as the value
  ("Live" or "Starting"), the Stop camera button MUST be reachable and labelled "Stop camera", and
  stopping MUST be announced ("Camera off").
- **CAM-012-R10**: The indicator and Stop camera MUST be testable without a camera, with the
  CAM-001 stand-in camera.

### Key Entities

- **Camera indicator**: shown or not, derived only from the camera feed state (starting or running
  → shown).
- **Fallback visual**: the visual chosen before Camera (the stored visual choice, which Camera never
  overwrites); projectM when none.

## Privacy review *(Constitution, Privacy: change to a sensor's behaviour)*

| Question | Answer |
|---|---|
| What changes? | The app shows its own camera indicator and a one-tap Stop camera. Capture itself is unchanged (CAM-001). |
| Is anything new captured, stored, sent or analysed? | No. Stop drops the last picture; no new setting is stored (R8). |
| Does it hide iOS's indicator? | No. iOS's indicator stays (CAM-001-R10); the app's badge is in addition. |

Result: the change only reduces camera use. The review passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-012-S1**: In 100 % of the tested feed changes (start, Stop camera, pause, background,
  interruption and its end, denial), the indicator is shown exactly when the feed is starting or
  running.
- **CAM-012-S2**: Stop camera stops the camera feed exactly once, before the indicator disappears,
  and leaves no camera picture held.
- **CAM-012-S3**: After Stop camera the fallback visual is shown and keeps producing new frames;
  the audio source has been started exactly once in the session.
- **CAM-012-S4**: After Stop camera, pause/resume and background/foreground round trips never start
  the camera.
- **CAM-012-S5** (device): on a physical device, iOS's camera indicator turns off within one second
  of tapping Stop camera, and the visualizer keeps animating.

## Assumptions

- The CAM-001 stand-in camera and its Debug launch flags are the test surface; simulator results
  are not device evidence (Constitution X). S5 is a `{device}` task left to the owner.
- The badge sits at the top of the visualizer, over the picture, inside the safe area; it never
  hides behind the controls.
- Releasing the camera hardware is the camera provider's job (CAM-001): its stop refuses further
  pictures and drops the held one at once and ends the capture session without blocking the main
  thread; S5 checks the hardware side on a device.
