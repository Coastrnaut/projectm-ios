# Feature Specification: CAM-013 Camera Failure Recovery

**Feature Branch**: `feature/cam-013` (spec directory `102-cam-013-camera-failure-recovery`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CAM-013 (Camera failure recovery) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Handle interruption, route
contention and permission revocation." Acceptance, verbatim: "Injected interruption clears last
frame and offers retry." Depends on CAM-001 (integrated); builds on CAM-002 (front camera),
CAM-007 (crop) and CAM-012 (camera badge), all integrated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-013-R1…`, success criteria `CAM-013-S1…`, tasks `CAM-013-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `0ee7468c`)

The row's gap status is "Gap candidate". The audit confirms a partial gap: the picture is already
cleared, but the user is never told why, is never offered a way back, and a runtime error never
recovers.

| Event (system name) | Picture today | What the user sees today | Retry today | Recovers today |
|---|---|---|---|---|
| Interruption: app in the background (`videoDeviceNotAvailableInBackground`) | Cleared (the visual also stops the camera on entering the background) | Nothing (the app is not on screen); on return the camera starts again | No | Yes, on return to the foreground |
| Interruption: camera used by another app, e.g. FaceTime (`videoDeviceInUseByAnotherClient`) | Cleared at once (feed `interrupted`, newest picture dropped, the layer draws only while running) | Generic notice "The camera is paused by the system. It comes back when the camera is free." | No | Yes, when the system reports the end |
| Interruption: microphone used by another app (`audioDeviceInUseByAnotherClient`) | Cleared (same path) | Same generic notice | No | Yes, on end. The camera session has no microphone input, so this reason is not expected |
| Interruption: iPad multitasking (`videoDeviceNotAvailableWithMultipleForegroundApps`) | Cleared | Same generic notice | No | Yes, on end |
| Interruption: system pressure, e.g. heat (`videoDeviceNotAvailableDueToSystemPressure`) | Cleared | Same generic notice | No | Yes, on end |
| Interruption ended (`interruptionEnded`) | Pictures return | Notice goes, "Camera on" badge returns | n/a | n/a |
| Runtime error, including a media services reset (`runtimeErrorNotification`, `mediaServicesWereReset`) | Cleared (feed `failed`) | The same generic notice, which wrongly promises that the camera comes back | No | **Never**: the feed stays `failed` and the stopped session object is kept until the visual is left |
| Permission revoked in Settings while running | iOS ends the app (see Clarifications) | On the next launch and choice of Camera: the denied notice with Open Settings (FILE-013) | No (Open Settings) | n/a |
| Thermal state (`thermalStateDidChange`) | Unchanged: the visual lowers its frame rate and scale (FR-049); the camera is not touched | Nothing | n/a | n/a; at critical pressure the system interrupts the camera (row above) |
| "Camera on" badge (CAM-012) while interrupted or failed | n/a | Hidden (it shows only while starting or running) | n/a | Returns when the camera runs |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What does "permission revocation" mean on iOS? → A: When the user turns camera access off in Settings while the app runs, iOS ends the app (Springboard terminates it); an Apple engineer on the Apple Developer Forums calls this expected behaviour (threads 720006 and 64740), and the authorization status a running process reads would not change anyway. So revocation is seen at the next start: the next launch, a Retry or a camera switch finds access denied and shows FILE-013's denied notice with Open Settings (CAM-013-R8). The termination itself is verified on a device (CAM-013-S7); nothing in the app can or should survive it.
- Q: What does "clears last frame" mean? → A: From the first frame after the event, no camera picture is drawn: the camera layer is transparent, so the Camera visual shows the spectrum over its black background (CAM-013-R1). A stale camera image is misleading (it looks live) and a privacy concern (it keeps showing a room the camera no longer sees). Rejected: freezing the last picture, a blurred last picture.
- Q: What does "offers retry" look like? → A: The existing non-blocking camera notice (FILE-013's notice style) names the reason in plain words and carries a **Retry** button (CAM-013-R2, R3). It never blocks the visualizer, the controls or the audio source.
- Q: Does the camera come back by itself? → A: Yes, whenever the system reports that the interruption ended, for every interruption reason, including another app using the camera (CAM-013-R4). The system resumes a capture session by itself when the camera is free, so refusing to resume after contention would mean a camera session that runs while its picture is hidden; resuming keeps the badge, the system indicator and the picture in agreement. The user chose the Camera visual and has not left it. Rejected: waiting for Retry after contention.
- Q: What does Retry do, and what if it keeps failing? → A: Retry stops the camera completely and starts it again, re-checking permission (CAM-013-R5). Attempts in a row back off: the first runs at once, then each waits 2, 4, 8, 16 and at most 30 seconds after the previous attempt; while a retry waits, the button reads "Retrying…" and is disabled (CAM-013-R6). The count resets once the camera has run for 10 seconds, or when the camera is stopped by the user or the app.
- Q: Is anything retried automatically? → A: Only a media services reset, once, through the same backoff (CAM-013-R7), as Apple's own camera sample restarts the session after a reset. Other runtime errors wait for Retry, so a broken camera never loops.
- Q: What does the badge say while interrupted? → A: Nothing: the "Camera on" badge is hidden whenever the camera is not starting or running (CAM-012, unchanged; CAM-013-R9). The notice is the status.
- Q: Is anything counted? → A: Each interruption reason, each runtime error kind and each retry is counted for diagnostics, as numbers only: no picture, no time of day, nothing stored or sent (CAM-013-R10).
- Q: What about the background (AUD-015)? → A: Unchanged: the camera never runs in the background. The visual stops it on entering the background and starts it on return; a waiting retry is cancelled by the stop, and the notice of an earlier interruption is gone after the return because the camera starts fresh (CAM-013-R11). AUD-015 keeps only the audio source running.
- Q: What about heat? → A: The visual keeps lowering its own frame rate and scale on thermal pressure (FR-049); the camera's configuration is not changed by this feature. When the system stops the camera for pressure, the interruption path applies (CAM-013-R4). Rejected for this row: lowering the camera's frame rate on pressure (a configuration change that needs device measurement).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Another app takes the camera, and I get it back (Priority: P1)

A performer runs the Camera visual. A FaceTime call (or another camera app in Split View) takes the
camera. The camera picture disappears at once instead of freezing, a notice says another app is
using the camera and offers Retry; the spectrum and the music keep going. When the other app lets
go, the picture comes back by itself; Retry also brings it back.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: With a stand-in camera, inject an interruption: the next composed frame
contains no camera pixels (read from pixels), the notice with Retry appears; Retry restarts the
camera and camera pixels return.

**Acceptance Scenarios**:

1. **Given** the Camera visual shows camera pictures, **When** the camera is interrupted for any
   reason, **Then** the next frame shows no camera picture and the badge "Camera on" is hidden.
2. **Given** an interruption, **When** it is shown, **Then** a non-blocking notice names the reason
   and offers Retry.
3. **Given** an interruption, **When** the system reports its end, **Then** pictures return, the
   notice goes and the badge returns, without any tap.
4. **Given** an interruption, **When** the user taps Retry, **Then** the camera is stopped and
   started again, and pictures return if the camera is free.

---

### User Story 2 - The camera breaks, and I can restart it (Priority: P1)

The camera stops with an error (for example after a system media reset). The picture disappears,
the notice says the camera stopped and offers Retry; after a reset the app tries once by itself.
Repeated taps never hammer a broken camera.

**Why this priority**: Today a runtime error never recovers until the user leaves the visual.

**Independent Test**: Inject a runtime error: no camera pixels, notice with Retry; Retry restarts
and pictures return. With a fake clock, attempts in a row wait 0, 2, 4, 8, 16 and 30 seconds.

**Acceptance Scenarios**:

1. **Given** a running camera, **When** a runtime error occurs, **Then** the picture is cleared and
   the notice offers Retry; the camera's session is released.
2. **Given** a media services reset, **When** it occurs the first time in a row, **Then** the app
   retries once by itself.
3. **Given** failures in a row, **When** the user taps Retry repeatedly, **Then** attempts wait
   by the backoff and the button reads "Retrying…" while waiting.

---

### User Story 3 - Access was turned off (Priority: P2)

The user turned camera access off in Settings. iOS ended the app; on the next launch, choosing
Camera (or tapping Retry, or switching cameras) shows the denied notice with Open Settings, and the
spectrum keeps running.

**Why this priority**: It is how revocation really reaches the app.

**Independent Test**: A stand-in camera whose access is denied at start shows FILE-013's denied
notice with Open Settings and no Retry; a stand-in whose access is withdrawn shows the denied
notice on the next Retry.

**Acceptance Scenarios**:

1. **Given** access is denied, **When** Camera is chosen, **Then** the denied notice with Open
   Settings is shown, without Retry, and no camera picture is drawn.
2. **Given** an interruption and access withdrawn meanwhile, **When** the user taps Retry, **Then**
   the denied notice replaces the interruption notice.

### Edge Cases

- An interruption while the camera is starting: the same as while running.
- An interruption end after the user stopped the camera (CAM-012) or left the visual: ignored.
- A runtime error during an interruption: the error wins (the session must be rebuilt).
- Background during an interruption or a waiting retry: the stop clears both; the return starts
  fresh.
- Retry while access is not determined: iOS's prompt may appear, as on a first start.
- A camera switch during an interruption: starts the new camera at once (no backoff).
- An unknown, future interruption reason: the generic interruption text, with Retry and the
  automatic return.
- Reduce flashing and Reduce Motion: the notice appears without animation of its own; the picture
  is simply absent.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-013-R1**: From the first frame after an interruption or a runtime error, the Camera visual
  MUST draw no camera picture (the camera layer is transparent), and no picture captured before
  the event MAY be drawn again until the camera runs again.
- **CAM-013-R2**: While the camera is interrupted or stopped by a runtime error, the Camera visual
  MUST show the non-blocking camera notice with a Retry button; it MUST NOT block the visual, the
  controls or the audio source.
- **CAM-013-R3**: The notice MUST name the reason with the fixed texts of Clarifications
  (another app, multitasking, system pressure, background, other interruption, media services
  reset, other error). The Retry button's VoiceOver label MUST be "Retry camera" ("Retrying
  camera" while waiting).
- **CAM-013-R4**: When the system reports that an interruption ended, the camera MUST resume
  without user action for every interruption reason, and the notice MUST go.
- **CAM-013-R5**: Retry MUST stop the camera completely (no picture kept, session released) and
  start it again, re-checking permission; the result (running, denied, restricted, unavailable,
  interrupted or failed) MUST be shown as for a first start.
- **CAM-013-R6**: Attempts in a row MUST back off: the first at once, then at least 2, 4, 8, 16
  and 30 seconds (cap) after the previous attempt. A Retry inside the wait MUST be held and run
  when the wait ends, and the button MUST read "Retrying…" and be disabled meanwhile. The count
  MUST reset after 10 seconds of running, and when the camera is stopped by the user or the app.
- **CAM-013-R7**: A media services reset MUST be retried automatically once per run of failures,
  through the backoff; no other runtime error MAY be retried without a tap.
- **CAM-013-R8**: A start (launch, Retry or camera switch) that finds access denied or restricted
  MUST show FILE-013's notice with Open Settings and without Retry.
- **CAM-013-R9**: The "Camera on" badge MUST be hidden whenever the camera is not starting or
  running (CAM-012), and the camera's session MUST be released after a runtime error so the
  system's indicator matches.
- **CAM-013-R10**: Each interruption reason, each runtime error kind and each retry MUST be
  counted, as numbers only, readable by tests and the DEBUG diagnostics; nothing about the
  picture is recorded and nothing is stored or sent.
- **CAM-013-R11**: The camera MUST NOT run in the background (AUD-015 unchanged); entering the
  background MUST cancel a waiting retry, and the return MUST start the camera afresh.
- **CAM-013-R12**: Each change of the notice MUST be announced to VoiceOver with its text through
  the app's shared announcement path.
- **CAM-013-R13**: The stand-in camera MUST be able to inject each interruption reason, its end, a
  runtime error of each kind, access denied at start and access withdrawn, in tests, on the
  simulator and in DEBUG UI tests.
- **CAM-013-R14**: The recovery rules (reason texts, automatic return, backoff, counts) MUST be a
  pure calculation on an injected clock, testable without a graphics device on every platform the
  packages' tests run on.

### Key Entities

- **Camera stop reason**: why the camera is not delivering: one of five interruption kinds (another
  app, multitasking, system pressure, background, other) or two error kinds (media services
  reset, other); its notice text, whether the system brings the camera back, whether the app
  retries by itself.
- **Camera recovery**: attempts in a row, time of the last attempt, how long the camera has run,
  a waiting retry, and the counts per reason and of retries.

## Privacy review *(Constitution, Privacy; extends CAM-001's review)*

| Question | Answer |
|---|---|
| What is captured? | Unchanged: the chosen camera's live picture while the Camera visual is shown. |
| Is anything stored? | No. The counts live in memory for the session; no picture is kept after an event. |
| Is anything sent or analysed? | No. |
| Does recovery start the camera without the user? | Only where the user's camera was already running and the system interruption ends, or once after a media reset; never after the user stopped it, left the visual or the app went to the background. |
| App Store privacy label | Unchanged: Data Not Collected. |

Result: a stale picture is never shown; no new collection, storage or transmission. The review
passes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-013-S1**: For each interruption reason and each runtime error kind injected into a running
  stand-in camera, the next composed frame contains zero camera pixels (read from pixels), and
  the notice with Retry is present.
- **CAM-013-S2**: After Retry (or the injected end of an interruption), camera pixels are present
  again within one frame of the camera running.
- **CAM-013-S3**: A table over every reason gives the expected notice text, automatic-return rule,
  automatic-retry rule and badge state (hidden), with no reason missing.
- **CAM-013-S4**: With a fake clock, ten Retry taps in one second start the camera at most once,
  and attempts in a row are spaced 0, 2, 4, 8, 16, 30, 30 seconds.
- **CAM-013-S5**: Access denied at start shows the denied notice with Open Settings and no Retry.
- **CAM-013-S6**: In a DEBUG UI test on the simulator, an injected interruption stops new camera
  frames, shows the notice with Retry, and Retry brings frames back, within 30 seconds of test
  time.
- **CAM-013-S7** (device stage): on D1 and D2, a FaceTime call or another camera app clears the
  picture with the "Another app" notice and the camera returns after the call; Retry recovers; on
  D2 Split View shows the multitasking notice; turning access off in Settings ends the app and the
  next choice of Camera shows the denied notice.

## Assumptions

- The system reports interruption reasons and their ends as documented; unknown reasons fall back
  to the generic text.
- Lowering the camera's frame rate under pressure, multitasking camera access on iPad and capture
  in the background are out of scope.
- Device behaviour is verified only in the final device stage.
