# ADR-0065: Device Motion Modulation Reads the Motion Sensors Only While Used, on the Device, Without Storing Readings

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: CAM-011 (`specs/247-cam-011-motion-sensor-modulation`)
- **Constitution**: I (public APIs), VI (modular boundaries), VII (bounded work off the audio path), X (evidence);
  Privacy constraints

## Context

CAM-011 asks to "map device tilt and acceleration to controls with calibration", accepted when a "synthetic motion
stream produces bounded normalized values". Until now the app read no motion sensor. A new sensor input needs a
reviewed rule for when it runs, what it may keep, and whether it needs a permission.

## Decision

1. The only sensor API is `CMMotionManager` device motion (public; `.xArbitraryZVertical`, the main queue), behind
   the app's `MotionSampling` protocol. Normalization (unwrapping, calibration, range, smoothing, shake envelope) is
   Foundation-free in ParameterGraph (`MotionTracker`), so the acceptance tests run on Linux; no package imports
   CoreMotion.
2. Device motion needs no usage description, so no permission prompt is added and FILE-013's permission catalog is
   unchanged. Activity, pedometer and altimeter data (which do need one) are never read.
3. The sensor runs only while the app is active and something reads motion: a binding or trigger of the shown visual
   names an `audio.motion.*` source, or Settings › Motion is on screen. It stops in the background, when the visual
   is released and when the last motion route is removed. 60 Hz; 30 Hz while the PERF-008 budget caps frames at 30.
4. Readings and the calibration stay in memory: nothing derived from motion is written, logged, put in diagnostics,
   scenes or backups, or sent. Only the range preference (`settings.motion.range`) is stored.
5. Motion sources use IDs with the `audio.` binding-source prefix (`audio.motion.pitch`, …), as MOD-007-D4 did for
   LFOs, so stored scenes restore them and older versions orphan rather than drop them.

## Consequences

- Scenes can bind tilt and shake like any other source; a device without sensors (and the simulator) reads the
  neutral values (attitude 0.5, shake 0) and Settings says so.
- The privacy policy gains a "Device motion" section.
- Real tilt, shake and the background stop are checked on D1 (CAM-011-T15, `{device}`); simulator runs use an
  injected or stand-in source and are not evidence of sensor behaviour.
