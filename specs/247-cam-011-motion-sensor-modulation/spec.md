# Feature Specification: CAM-011 Motion Sensor Modulation

**Feature Branch**: `feature/cam-011` (spec directory `247-cam-011-motion-sensor-modulation`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CAM-011 (Motion sensor modulation) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Map device tilt and acceleration to controls with calibration." Acceptance, verbatim:
"Synthetic motion stream produces bounded normalized values." Priority P2, depends on MOD-001 (typed parameter
registry)."

Identifiers in this feature carry the roadmap ID: requirements `CAM-011-R1…`, success criteria `CAM-011-S1…`,
research decisions `CAM-011-D1…`, tasks `CAM-011-T01…`. Other features are cited by their own IDs: MOD-001
(parameter registry), MOD-002 (audio feature bindings), MOD-005 (binding envelope), MOD-006 (threshold triggers),
MOD-007 (LFOs as binding sources), MOD-011 (layers), MOD-012 (modulation matrix), MOD-013 (stored binding IDs),
MOD-015 (band envelopes), SHD-009 (expressions), PERF-008 (power profile), FILE-005 / FILE-011 (settings backup
and erase), FILE-013 (permission catalog).

## Baseline: what exists today (audit of 2026-11-14, commit `c8dea0e1`)

| Question | Today |
|---|---|
| Binding sources | `AudioFeatureSource` (ParameterGraph) names every bindable source: audio features, LFOs (`audio.lfo.<i>`, MOD-007) and band envelopes (`audio.bandEnvelope.<p>.<b>`, MOD-015). Non-audio sources keep the `audio.` prefix so stored bindings (MOD-013 restore, ID migrations) read them and an older version orphans them instead of dropping them (MOD-007-D4). |
| Frame values | `AudioFeatureFrame` carries one frame's values to the modulator; the native spectrum host (`NativeSpectrumHost.applyModulation`) builds it on the frame clock and only while a binding or trigger exists. |
| Device motion | **None.** No part of the app reads the accelerometer, gyroscope or attitude. |
| Permissions | FILE-013's catalog lists every usage-description key; device motion through the motion manager needs none (only activity/pedometer/altimeter data does). |
| Power | PERF-008's profile caps the frame loop at 30 fps under Battery saver. |
| Route creation | Bindings come from scenes and DEBUG seeds; the modulation matrix edits but does not create routes (MOD-012-D6). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Which motion signals become sources, and under which IDs? → A: Four: **pitch**, **roll** and **yaw** (the device's attitude) and **shake** (the strength of the user's acceleration, gravity removed). IDs `audio.motion.pitch`, `audio.motion.roll`, `audio.motion.yaw`, `audio.motion.shake`, keeping the `audio.` binding-source prefix as MOD-007-D4 did for LFOs, so every stored-binding path reads them and an older version orphans them. Inspector names "Tilt forward" (pitch), "Tilt sideways" (roll), "Turn" (yaw), "Shake". Bindings, layers and threshold triggers accept them; expressions do not (as MOD-007-D4, MOD-015-D5) (CAM-011-R1, R2).
- Q: How is an angle normalized? → A: Relative to a calibrated neutral attitude, over a configurable range: 0.5 at neutral, 0 at −range, 1 at +range, clamped beyond. Range choices Narrow ±20°, Medium ±45° (default), Wide ±90°, one setting for all three axes (CAM-011-R3, R5).
- Q: How is the yaw discontinuity at ±180° handled? → A: Each angle is unwrapped between consecutive samples (a jump larger than 180° between two samples is taken as the wrap, not a turn), so crossing the sensor's ±180° seam never makes the output jump. The unwrapped offset from neutral is kept within ±360° so it cannot grow without bound. After a restart of sampling the first sample is wrapped to within ±180° of neutral (CAM-011-R4).
- Q: What is calibration? → A: "Calibrate" takes the current attitude as neutral, so every attitude source reads 0.5 at once. It is held for the session only and never stored: the yaw reference changes every time sampling starts, and nothing derived from motion is written to disk. Before calibration the neutral is level (pitch 0, roll 0) and the yaw at the first sample (CAM-011-R5, R10).
- Q: How is shake measured? → A: The magnitude of the user acceleration (gravity removed) divided by 2 g, clamped to 0…1, followed by an envelope with attack 20 ms and release 300 ms (MOD-005's one-pole), so a shake reads as a quick rise and a smooth fall (CAM-011-R6).
- Q: Smoothing and robustness? → A: Attitude outputs are smoothed with a 60 ms one-pole on the sample clock (injected timestamps, Δt at most 0.25 s). A non-finite sample component (NaN, ±∞) is ignored and the last value held; every output is always finite and within 0…1 (CAM-011-R7).
- Q: When do the sensors run? → A: Only while needed: while the shown visual has a binding or trigger that reads a motion source, or while Settings › Motion is on screen (its live readout and Calibrate), and only while the app is active. Sampling stops in the background and when nothing reads motion. Rate 60 Hz, 30 Hz while the power budget caps frames at 30 (PERF-008) (CAM-011-R8, R9).
- Q: Permission? → A: None is asked: device motion through the motion manager needs no usage description, so the permission catalog and project.yml are unchanged. The privacy policy gains a short "Device motion" section: read only while needed, used only on the device, never stored or sent (CAM-011-R10).
- Q: When motion is unavailable (no sensors, as in the simulator)? → A: Motion sources read 0.5 for attitude and 0 for shake; Settings › Motion shows "Motion sensors are not available on this device." and disables Calibrate and the range (CAM-011-R11).
- Q: Where is the setting and what is stored? → A: Settings › Motion (in the performance group, so it stays reachable while a scene is locked): a live readout of the four values, Calibrate, and Range. One UserDefaults key `settings.motion.range` (`narrow`, `medium`, `wide`; absent or unknown → medium; written on change only), a preference backed up with the library settings (FILE-005 included keys), erased with Settings (FILE-011), removed by the UI-test reset (CAM-011-R12).
- Q: What do motion sources read before the first sample arrives, and after sampling stops? → A: Before the first sample (and while unavailable) attitude reads 0.5 and shake 0; after sampling stops the last values are held, and on restart the smoothing snaps to the first new sample instead of gliding from the held value (CAM-011-R7, R11).
- Q: Does Calibrate announce itself and is the readout accessible? → A: Yes: Calibrate posts one polite announcement "Motion calibrated" through the AccessibilityAnnouncer lane, and the readout is one accessibility element per value ("Tilt forward 50 percent"); the readout refreshes at most 10 times a second (CAM-011-R14).
- Q: How is acceptance tested? → A: A package test feeds a synthetic motion stream (sweeps far beyond the range, spikes, NaN and ±∞, rapid shakes, the yaw seam crossed both ways, timestamps that stand still or jump back) and asserts every output is finite and within 0…1, neutral reads 0.5 after calibration, and crossing the seam moves the yaw output by less than 0.01 per sample. An app test drives a parameter through a motion binding with an injected motion source; a short UI test calibrates through the DEBUG stand-in motion source (CAM-011-S1 to S4).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tilt the device to play a parameter (Priority: P1)

A performer binds "Tilt forward" to the glow intensity in a scene. Holding the device naturally, they tap
Calibrate; tilting forward then raises the glow, tilting back lowers it, and holding still returns it to the middle.

**Why this priority**: This is the roadmap row: device tilt mapped to a control, with calibration.

**Independent Test**: Feed a synthetic attitude stream through the motion source and check the normalized output.

**Acceptance Scenarios**:

1. **Given** a calibrated neutral, **When** the device is at neutral, **Then** every attitude source reads 0.5.
2. **Given** Medium range, **When** the device tilts forward 45° or more, **Then** "Tilt forward" reads 1; tilted back 45° or more it reads 0.
3. **Given** any motion stream, including invalid readings, **When** values are read, **Then** each is finite and within 0…1.
4. **Given** the device turning through the sensor's ±180° seam, **When** values are read, **Then** "Turn" changes smoothly, without a jump.

### User Story 2 - Shake to trigger (Priority: P2)

A performer binds "Shake" to a parameter or a threshold trigger; a quick shake makes it rise at once and fall back
within about a second.

**Independent Test**: Feed rapid acceleration spikes and check the envelope's rise, fall and bounds.

**Acceptance Scenarios**:

1. **Given** the device still, **When** values are read, **Then** "Shake" reads 0.
2. **Given** a hard shake, **When** values are read, **Then** "Shake" rises toward 1 within a few samples and falls back after it stops.

### User Story 3 - Calibrate and choose the range in Settings (Priority: P2)

**Independent Test**: In Settings › Motion with a stand-in motion source, the readout shows a tilted value; Calibrate
brings it to 50 %.

**Acceptance Scenarios**:

1. **Given** Settings › Motion on screen, **When** the device is tilted, **Then** the readout shows the tilt in percent.
2. **Given** a tilted device, **When** the performer taps Calibrate, **Then** the readout shows 50 % for every attitude value.
3. **Given** a device without motion sensors, **When** Settings › Motion is shown, **Then** it says so and Calibrate and Range are disabled.

### Edge Cases

- NaN or ±∞ in a sample: that component is ignored; the previous value is held.
- Sample time standing still or going backwards: no smoothing step; a gap over 0.25 s counts as 0.25 s.
- A full turn or more: the yaw offset is limited to ±360°, so turning back one turn always brings it back.
- Pitch beyond ±90° (upside down): the sensor folds; the output stays clamped and finite.
- Sampling stopped and restarted (background, no binding): the unwrapping restarts from the first new sample.
- No motion sensors: attitude sources read 0.5, shake 0; Settings explains why.
- An expression naming `audio.motion.pitch`: refused as an unknown name.
- A scene with a motion binding opened on an older version: the binding is orphaned (MOD-013), not dropped.

## Requirements *(mandatory)*

### Functional Requirements

- **CAM-011-R1**: The system MUST offer four bindable sources: pitch, roll, yaw and shake, with stable IDs `audio.motion.<pitch|roll|yaw|shake>` that parse back exactly.
- **CAM-011-R2**: Bindings, layers and threshold triggers MUST accept the motion sources; people-facing names MUST be "Tilt forward", "Tilt sideways", "Turn", "Shake"; expressions MUST NOT accept them.
- **CAM-011-R3**: Each attitude source MUST read 0.5 + offset / (2 · range), clamped to 0…1, where offset is the angle relative to the calibrated neutral and range is the chosen half-width (20°, 45° or 90°).
- **CAM-011-R4**: Angles MUST be unwrapped between consecutive samples so the sensor's ±180° seam never causes a jump; the offset from neutral MUST stay within ±360°.
- **CAM-011-R5**: Calibrate MUST take the current attitude as neutral, after which every attitude source reads 0.5 for that attitude.
- **CAM-011-R6**: Shake MUST be the user acceleration's magnitude over 2 g, clamped to 0…1, through a one-pole envelope (attack 20 ms, release 300 ms).
- **CAM-011-R7**: Every output MUST be finite and within 0…1 for any input; non-finite sample components MUST be ignored; smoothing MUST use only the injected sample time (Δt clamped to 0…0.25 s).
- **CAM-011-R8**: Motion sensors MUST run only while the app is active and something reads motion (a binding or trigger of the shown visual, or Settings › Motion on screen), and MUST stop otherwise.
- **CAM-011-R9**: The sample rate MUST be 60 Hz, or 30 Hz while the power budget caps frames at 30.
- **CAM-011-R10**: Motion data MUST stay on the device: never stored, sent or logged; calibration is held for the session only. No permission prompt is added.
- **CAM-011-R11**: Without motion sensors, attitude sources MUST read 0.5 and shake 0, and Settings MUST explain the absence and disable its controls.
- **CAM-011-R12**: The range MUST be stored under `settings.motion.range` (absent or unknown → Medium), backed up and erased with the other settings and reset by the UI-test reset.
- **CAM-011-R14**: Calibrate MUST post one polite announcement, and the Settings readout MUST expose each value as an accessibility element, refreshing at most 10 times a second.
- **CAM-011-R13**: Per-sample processing and per-frame reads MUST NOT allocate; the changed package MUST keep building on Linux, with the sensor API only in the app.

### Key Entities

- **Motion axis**: pitch, roll, yaw or shake.
- **Motion sample**: one reading: attitude (pitch, roll, yaw in radians), user acceleration (x, y, z in g), and its time.
- **Motion tracker**: the calibrated neutral, the range, the unwrapped offsets and the smoothed outputs.
- **Motion range**: Narrow, Medium or Wide.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CAM-011-S1**: For a synthetic stream of sweeps beyond the range, spikes, NaN/±∞, rapid shakes, seam crossings and irregular timestamps, 100 % of outputs are finite and within 0…1.
- **CAM-011-S2**: After calibration, a steady neutral attitude reads 0.5 (within 0.001) on every attitude source; crossing the yaw seam changes the yaw output by less than 0.01 per sample.
- **CAM-011-S3**: In the app, a motion binding drives a parameter from the injected motion source, and the sensors stop when the app leaves the foreground or the binding is removed.
- **CAM-011-S4**: In Settings › Motion, Calibrate brings the readout to 50 % within one second (UI test under 30 s).
- **CAM-011-S5**: Package tests pass on the host and in the Linux CI shape, each new test in under 2 s.

## Assumptions

- The motion sources feed the native visuals' modulation, as every other binding source does; projectM presets are not modulated by bindings.
- Creating routes in the UI stays out of scope (MOD-012-D6); motion sources are bound through scenes and DEBUG seeds.
- A device check (real tilt and shake on D1) is recorded as a `{device}` task; the simulator has no motion sensors, so the Mac uses an injected source.
