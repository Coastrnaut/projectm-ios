# Feature Specification: CAM-004 Camera Exposure Lock

**Feature Branch**: `feature/cam-004` (spec directory `217-cam-004-exposure-lock`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CAM-004 (Camera exposure lock) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Lock and release supported
exposure controls." Acceptance, verbatim: "Supported device changes exposure state; unsupported
device explains limit." P2, depends on CAM-001 (integrated); builds on CAM-002 (front camera),
CAM-003 (lens selection) and CAM-013 (failure recovery)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-004-R1…`, success criteria `CAM-004-S1…`, tasks `CAM-004-T01…`. Requirements
of other features are cited by their own IDs: CAM-001-R7, R9, R13; CAM-002-R7; CAM-003-R6, R10;
CAM-012 (badge, Stop camera); CAM-013 (interruptions, failures); FILE-005 (settings backup).

The constitution's Privacy section requires a specification and a privacy review for a sensor.
Exposure lock changes how an already running camera meters light; it adds no sensor, no capture and
no stored data. This specification extends CAM-001's to CAM-003's review (section "Privacy review").

## Baseline: what exists today (audit of 2026-11-14, commit `cd89f309`)

| Area | Today | Gap for this row |
|---|---|---|
| Camera visual | Settings › Visual › "Camera" shows the chosen camera (Back/Front, CAM-002; back lens, CAM-003) under a circular spectrum; it runs only while the visual is shown and the app is in the foreground (CAM-001-R7). | The camera always adjusts its exposure automatically and continuously. |
| Camera session | Inputs are replaced on a running session through a platform-free seam (CAM-003's input switch), so the stand-in camera and the real camera share the switch code. | No access to the camera device's exposure controls; no seam for them. |
| Stand-in camera | Simulates permission scenarios, both positions, lenses, failing lenses, interruptions and failures for tests, the simulator and DEBUG UI tests. | No exposure capability, no exposure state. |
| Settings | Section "Camera": Camera Back/Front, Lens (two or more lenses), Mirror, Crop, Anchor, Zoom. | No exposure row. |
| Permission | One iOS camera permission covers the camera; the badge and iOS's indicator show while it runs. | Nothing new. |

## Clarifications

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which exposure controls does "lock and release supported exposure controls" cover? → A: The camera's locked exposure mode only: lock holds the current exposure, release returns to continuous automatic exposure (CAM-004-R4). Exposure bias and manual (custom) shutter/ISO are out of scope; they need a slider whose range differs per camera and can follow in a later row. Rejected: a bias slider now (more surface, no acceptance need) and custom exposure (manual shutter speed can strobe; a flashing risk under Constitution's photosensitivity rules).
- Q: How does an unsupported camera explain its limit? → A: The "Lock exposure" switch stays visible but disabled, with the text "This camera can't lock exposure." under it, read by VoiceOver with the switch (CAM-004-R3, R11). Rejected: hiding the row (CAM-003 hides unavailable lenses, but this row's acceptance explicitly asks for an explanation).
- Q: What happens to a lock when the lens or camera changes? → A: The lock is released on the previous camera before its input is removed, and the new camera starts in continuous automatic exposure; it is not re-applied (CAM-004-R6). Rejected: re-locking the new camera at once (it would freeze whatever exposure the new camera has in its first instant, usually wrong).
- Q: Is the lock remembered? → A: No: it is session state of the running camera, released on every stop (Stop camera, another visual, background, failure) and never stored; no new settings key, nothing in backups, scenes or cues (CAM-004-R7, R8). Rejected: a stored preference (a lock only makes sense for the light of the moment).
- Q: What does the switch show: the user's choice or the camera's state? → A: The camera's state, read back after each change; a refused change (configuration cannot be taken) leaves the switch showing the real state, with no notice (CAM-004-R5). While the camera is not running the switch is off and disabled with "Exposure can be locked while the camera is running." (User Story 2 scenario 2). Rejected: an optimistic switch (it could show "locked" while the camera still adjusts).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold the exposure steady (Priority: P1)

A performer films a stage with the Camera visual. Moving lights make the camera brighten and darken
the picture all the time. In Settings › Camera they turn on "Lock exposure"; the camera keeps its
current exposure, and the picture no longer pumps with the lights. Turning it off returns the camera
to automatic exposure.

**Why this priority**: This is the row's observable behavior; without it nothing is delivered.

**Independent Test**: With a camera that supports locking, running: turn the switch on → the camera
reports locked exposure and the switch shows on; turn it off → the camera reports automatic exposure
and the switch shows off.

**Acceptance Scenarios**:

1. **Given** the Camera visual runs on a camera that supports exposure lock, **When** the user turns
   "Lock exposure" on, **Then** the camera's exposure state becomes locked and the switch shows on.
2. **Given** exposure is locked, **When** the user turns the switch off, **Then** the camera returns
   to continuous automatic exposure and the switch shows off.
3. **Given** the camera refuses the change (it cannot be configured at that moment), **When** the
   user turns the switch on, **Then** the switch returns to off, showing the camera's real state.

---

### User Story 2 - Learn why the control is not available (Priority: P1)

A viewer whose camera cannot lock exposure opens Settings › Camera. The "Lock exposure" switch is
shown but disabled, with the explanation "This camera can't lock exposure." Nothing is attempted on
the camera.

**Why this priority**: The second half of the row's acceptance ("unsupported device explains
limit").

**Independent Test**: With a camera that does not support exposure lock: the row is disabled, the
explanation is shown, and no configuration of the camera happens when the row is touched.

**Acceptance Scenarios**:

1. **Given** the chosen camera cannot lock exposure, **When** Settings › Camera is shown, **Then**
   the switch is disabled and the text "This camera can't lock exposure." is shown and spoken by
   VoiceOver with the switch.
2. **Given** the camera is not running (idle, asking, denied, unavailable, interrupted, failed),
   **When** the camera can lock exposure, **Then** the switch is disabled with "Exposure can be
   locked while the camera is running."

---

### User Story 3 - The lock never outlives its camera (Priority: P2)

A user locks exposure, then switches to the ultra wide lens, the front camera, stops the camera,
or leaves the app. The lock is released on the camera it was set on, and the newly opened camera
starts with automatic exposure; the switch shows off. Nothing about exposure is remembered.

**Why this priority**: A lock made for one lens or one scene is wrong for another; a forgotten lock
would leave a camera dark or blown out with no visible reason.

**Independent Test**: Lock on the wide lens, switch to ultra wide: the wide lens is back on automatic
exposure, the ultra wide lens runs on automatic exposure, the switch is off.

**Acceptance Scenarios**:

1. **Given** exposure is locked, **When** the lens or camera position changes, **Then** the previous
   camera is returned to automatic exposure before it is removed and the new camera runs with
   automatic exposure.
2. **Given** exposure is locked, **When** the camera stops (Stop camera, another visual, background,
   a failure), **Then** the camera is returned to automatic exposure and the switch shows off.
3. **Given** the app is relaunched, **Then** exposure is automatic (the lock is not stored).

### Edge Cases

- A camera that supports locked but not continuous automatic exposure: unlocking leaves whatever
  automatic mode the camera reports; the switch shows the reported state (CAM-004-R5).
- The camera is busy (configuration cannot be taken): the state is unchanged and the switch shows
  the real state; no crash, no notice.
- An interruption while locked: the session is kept by the system; the lock stays on the camera; the
  switch is disabled while interrupted (the camera is not running) and shows the camera's state again
  when the interruption ends.
- The front camera: governed by the same rules; on many devices it supports locking.
- No camera at all (simulator, `unavailable`): the row is disabled with "Exposure can be locked while
  the camera is running."; nothing is asked.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-004-R1**: Settings › Camera MUST show a "Lock exposure" switch while the Camera visual is
  chosen, for both positions and every lens.
- **CAM-004-R2**: The switch MUST be enabled only while the camera runs and the current camera
  reports that it supports locked exposure.
- **CAM-004-R3**: When the current camera does not support locked exposure, the switch MUST be
  disabled and the row MUST explain "This camera can't lock exposure."; no configuration of the
  camera may be attempted.
- **CAM-004-R4**: Turning the switch on MUST set the running camera to locked exposure inside one
  configuration of that camera; turning it off MUST set it to continuous automatic exposure when the
  camera supports that.
- **CAM-004-R5**: The switch MUST show the exposure state read back from the camera after each change,
  never the requested state; a refused change leaves the switch showing the camera's real state.
- **CAM-004-R6**: Before a lens or position switch replaces a locked camera, it MUST be returned to
  continuous automatic exposure; the new camera runs with automatic exposure and the switch shows
  off.
- **CAM-004-R7**: Stopping the camera for any reason (Stop camera, another visual, background,
  presentation loss, a runtime failure) MUST return a locked camera to automatic exposure; the
  switch shows off.
- **CAM-004-R8**: The exposure lock MUST NOT be stored (no settings key, not in backups, scenes or
  cues); every start begins with automatic exposure.
- **CAM-004-R9**: Changing exposure MUST NOT start, stop or restart the camera, change the frame
  loop or the audio source, or ask for permission.
- **CAM-004-R10**: The stand-in camera MUST simulate a camera that supports locking and one that does
  not, through the same exposure code the real camera uses (as CAM-003-R10), for tests, the simulator
  and DEBUG UI tests.
- **CAM-004-R11**: The switch MUST be accessible: label "Lock exposure", its on/off value, and the
  explanation read with it when disabled.

### Key Entities

- **Exposure capability**: whether the current camera supports locked exposure and continuous
  automatic exposure.
- **Exposure state**: the capability plus the mode the camera reports (locked, continuous automatic,
  other); session state only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-004-S1**: On a camera that supports it, 100% of lock and unlock choices end with the camera
  reporting the chosen mode, and the switch showing it, without a camera restart.
- **CAM-004-S2**: On a camera that does not support it, the explanation is shown and 0 configuration
  attempts are made.
- **CAM-004-S3**: After any lens switch, position switch or stop, 0 cameras are left locked.
- **CAM-004-S4**: 0 new stored settings; 0 new permission prompts.

## Privacy review *(Constitution, Privacy; extends CAM-001's to CAM-003's review)*

- Sensor: the camera already in use; no new sensor, no microphone.
- Exposure is changed only on the running camera, only by the user's switch; it cannot start the
  camera. iOS's indicator and the app's camera badge are unchanged (CAM-012).
- Nothing is stored, sent, logged or analysed; pictures stay as CAM-001-R9 describes.

## Assumptions

- "Supported exposure controls" means the camera's locked exposure mode; exposure bias and manual
  (custom) exposure are out of scope for this row (see Clarifications).
- The real camera's exposure capability can be read without running it, but changes are made only
  while it runs.
- Device verification (a real lock on D1) is a `{device}` task; simulator results are never device
  evidence.
