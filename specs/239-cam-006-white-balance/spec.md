# Feature Specification: CAM-006 Camera White Balance

**Feature Branch**: `feature/cam-006` (spec directory `239-cam-006-white-balance`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CAM-006 (Camera white balance) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose supported automatic and
locked white balance." Acceptance, verbatim: "Lock/unlock persists during session without invalid
device configuration." P2, depends on CAM-001 (integrated); follows CAM-004 (exposure lock) and
CAM-005 (focus point), both integrated."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CAM-006-R1…`, success criteria `CAM-006-S1…`, tasks `CAM-006-T01…`. Requirements
of other features are cited by their own IDs: CAM-001-R7, R9; CAM-003-R10; CAM-004-R1 to R11;
CAM-005-R8; CAM-012 (badge, Stop camera); CAM-013 (interruptions, failures); FILE-005 (settings backup).

The constitution's Privacy section requires a specification and a privacy review for a sensor.
White balance changes how an already running camera renders color; it adds no sensor, no capture and
no stored data. This specification extends the CAM-001 to CAM-005 reviews (section "Privacy review").

## Baseline: what exists today (audit of 2026-11-14, commit `c035898f`)

| Area | Today | Gap for this row |
|---|---|---|
| Camera visual | Settings › Visual › "Camera" shows the chosen camera (Back/Front, CAM-002; back lens, CAM-003) under a circular spectrum; it runs only while the visual is shown and the app is in the foreground (CAM-001-R7). | The camera always adjusts its white balance automatically and continuously. |
| Exposure and focus | CAM-004 locks and releases exposure, CAM-005 focuses on a point, both through platform-free device seams shared by the stand-in and the real camera; every lens or position switch and every stop release them. | No white balance seam, state or control. |
| Stand-in camera | Simulates permission scenarios, both positions, lenses, interruptions, failures, exposure lock and focus capability. | No white balance capability, no gains. |
| Settings | Section "Camera": Camera Back/Front, Lens, Lock exposure, focus note, Mirror, Crop, Anchor, Zoom. | No white balance row. |
| Permission | One iOS camera permission covers the camera; the badge and iOS's indicator show while it runs. | Nothing new. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold the colors steady (Priority: P1)

A performer films a stage with the Camera visual. Colored lights make the camera shift the picture's
colors all the time. In Settings › Camera they turn on "Lock white balance"; the camera keeps its
current color balance, and the colors no longer drift with the lights. Turning it off returns the
camera to automatic white balance.

**Why this priority**: This is the row's observable behavior; without it nothing is delivered.

**Independent Test**: With a camera that supports locking, running: turn the switch on → the camera
reports locked white balance and the switch shows on; turn it off → the camera reports automatic
white balance and the switch shows off.

**Acceptance Scenarios**:

1. **Given** the Camera visual runs on a camera that supports white balance lock, **When** the user
   turns "Lock white balance" on, **Then** the camera's white balance becomes locked at its current
   color balance and the switch shows on.
2. **Given** white balance is locked, **When** the user turns the switch off, **Then** the camera
   returns to continuous automatic white balance and the switch shows off.
3. **Given** the camera refuses the change (it cannot be configured at that moment, or its current
   color balance cannot be held validly), **When** the user turns the switch on, **Then** nothing
   invalid is applied and the switch shows the camera's real state.

---

### User Story 2 - The lock lasts for the session, and only for it (Priority: P1)

A user locks white balance, then a phone call interrupts the camera. When the camera comes back, the
lock is still in place and the switch shows on. When they switch lens or camera, stop the camera or
leave the app, the lock is released on the camera it was set on and the next camera starts in
automatic white balance. Nothing is remembered across launches.

**Why this priority**: The row's acceptance ("Lock/unlock persists during session").

**Independent Test**: Lock, interrupt, end the interruption: still locked. Lock, switch lens: the
previous lens is back on automatic, the new one runs on automatic, the switch is off.

**Acceptance Scenarios**:

1. **Given** white balance is locked, **When** the camera is interrupted and the interruption ends,
   **Then** the camera still reports locked white balance and the switch shows on.
2. **Given** white balance is locked, **When** the lens or camera position changes, **Then** the
   previous camera is returned to automatic white balance before it is removed and the new camera
   runs with automatic white balance.
3. **Given** white balance is locked, **When** the camera stops (Stop camera, another visual,
   background, a failure), **Then** the camera is returned to automatic white balance and the switch
   shows off.
4. **Given** the app is relaunched, **Then** white balance is automatic (the lock is not stored).

---

### User Story 3 - Learn why the control is not available (Priority: P2)

A viewer whose camera cannot lock white balance opens Settings › Camera. The switch is shown but
disabled, with the explanation "This camera can't lock white balance." Nothing is attempted on the
camera.

**Why this priority**: "supported" in the row means unsupported cameras must be handled safely.

**Independent Test**: With a camera that does not support white balance lock: the row is disabled,
the explanation is shown, and no configuration of the camera happens.

**Acceptance Scenarios**:

1. **Given** the chosen camera cannot lock white balance, **When** Settings › Camera is shown,
   **Then** the switch is disabled and "This camera can't lock white balance." is shown and spoken
   by VoiceOver with the switch.
2. **Given** the camera is not running, **When** the camera can lock white balance, **Then** the
   switch is disabled with "White balance can be locked while the camera is running."

### Edge Cases

- The camera reports a current color balance outside the range it accepts (a known camera quirk):
  the values are brought into range before the lock; values that are not numbers are refused and
  nothing is configured (CAM-006-R5).
- The camera can hold its white balance but not at given values: it is locked in place without
  passing values (CAM-006-R4).
- A camera that supports locked but not continuous automatic white balance: unlocking leaves the
  mode the camera reports; the switch shows the reported state.
- The camera is busy (configuration cannot be taken): the state is unchanged; no crash, no notice.
- No camera at all (simulator, `unavailable`): the row is disabled with the "while the camera is
  running" note; nothing is asked.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-006-R1**: Settings › Camera MUST show a "Lock white balance" switch while the Camera visual is
  chosen, for both positions and every lens.
- **CAM-006-R2**: The switch MUST be enabled only while the camera runs and the current camera reports
  that it supports locked white balance.
- **CAM-006-R3**: When the current camera does not support locked white balance, the switch MUST be
  disabled and the row MUST explain "This camera can't lock white balance."; no configuration of the
  camera may be attempted.
- **CAM-006-R4**: Turning the switch on MUST lock the running camera's white balance at its current
  color balance inside one configuration of that camera; turning it off MUST return it to continuous
  automatic white balance when the camera supports that, inside one configuration.
- **CAM-006-R5**: The app MUST never apply a color balance the camera does not accept: every value
  passed to the camera lies within the camera's accepted range; values that are not finite numbers
  are refused and nothing is configured.
- **CAM-006-R6**: The switch MUST show the white balance state read back from the camera after each
  change, never the requested state.
- **CAM-006-R7**: A lock MUST persist while the same camera stays in use during the session,
  including across interruptions; it is shown again when the camera runs again.
- **CAM-006-R8**: Before a lens or position switch replaces a locked camera, it MUST be returned to
  continuous automatic white balance; the new camera runs with automatic white balance.
- **CAM-006-R9**: Stopping the camera for any reason (Stop camera, another visual, background, a
  runtime failure) MUST return a locked camera to automatic white balance; the switch shows off.
- **CAM-006-R10**: The lock MUST NOT be stored (no settings key, not in backups, scenes or cues).
- **CAM-006-R11**: Changing white balance MUST NOT start, stop or restart the camera, change the frame
  loop or the audio source, or ask for permission.
- **CAM-006-R12**: The stand-in camera MUST simulate cameras that support locking and that do not,
  including out-of-range and non-numeric reported color balances, through the same white balance
  code the real camera uses, for tests, the simulator and DEBUG UI tests.
- **CAM-006-R13**: The switch MUST be accessible: label "Lock white balance", its on/off value, and
  the explanation read with it when disabled.

### Key Entities

- **White balance capability**: whether the current camera supports locked and continuous automatic
  white balance, whether it can be locked at given values, and its accepted range.
- **White balance state**: the capability plus the mode the camera reports (locked, continuous
  automatic, other); session state only.
- **Color balance (gains)**: the three per-channel values the camera uses; read from the camera,
  brought into range before being passed back.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-006-S1**: On a camera that supports it, 100% of lock and unlock choices end with the camera
  reporting the chosen mode and the switch showing it, without a camera restart.
- **CAM-006-S2**: 0 invalid color balances are ever applied, including for every out-of-range or
  non-numeric value the stand-in reports; 0 configuration attempts on unsupported cameras.
- **CAM-006-S3**: A lock survives 100% of interruptions that end with the same camera; after any lens
  switch, position switch or stop, 0 cameras are left locked.
- **CAM-006-S4**: 0 new stored settings; 0 new permission prompts.

## Privacy review *(Constitution, Privacy; extends the CAM-001 to CAM-005 reviews)*

- Sensor: the camera already in use; no new sensor, no microphone.
- White balance is changed only on the running camera, only by the user's switch; it cannot start the
  camera. iOS's indicator and the app's camera badge are unchanged (CAM-012).
- Nothing is stored, sent, logged or analysed; pictures stay as CAM-001-R9 describes.

## Assumptions

- "Supported automatic and locked white balance" means the camera's continuous automatic and locked
  modes; manual temperature/tint and presets are out of scope (see Clarifications).
- The capability can be read without running the camera; changes are made only while it runs.
- Device verification (a real lock on D1) is a `{device}` task; simulator results are never device
  evidence.
