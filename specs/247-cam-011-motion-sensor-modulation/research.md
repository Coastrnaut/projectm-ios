# Research: CAM-011 Motion Sensor Modulation

- **CAM-011-D1 Sensor API.** Decision: `CMMotionManager` device motion (`startDeviceMotionUpdates(using:
  .xArbitraryZVertical, to: .main)`), reading `attitude.pitch/roll/yaw` and `userAcceleration` (gravity already
  removed, in g). Rationale: sensor fusion gives a stable attitude and a gravity-free acceleration in one stream;
  `xArbitraryZVertical` needs no magnetometer calibration (yaw is relative, which calibration makes explicit).
  Device motion needs no `NSMotionUsageDescription` (that key covers motion activity, pedometer and altimeter
  data), so FILE-013's catalog and project.yml are unchanged. Alternatives: raw accelerometer tilt (rejected:
  noisy, no yaw); `CMMotionActivityManager` (rejected: needs permission, wrong data).
- **CAM-011-D2 IDs.** `audio.motion.<pitch|roll|yaw|shake>`, keeping the `audio.` binding-source prefix
  (MOD-007-D4): MOD-013 restore and the ID migration table treat `audio.` IDs as sources, and an older version
  orphans an unknown `audio.` ID instead of dropping or misreading it as a parameter. Alternative `motion.pitch`
  (rejected: would read as a parameter ID and be refused by scene restore).
- **CAM-011-D3 Unwrapping.** Each angle keeps an unwrapped offset from neutral: offset += remainder(new − last,
  2π) per sample, limited to ±2π. A seam crossing (+π → −π) adds a small step instead of −2π. On a restart the
  first sample sets offset = remainder(angle − neutral, 2π). Alternative: wrap relative to neutral every sample
  (rejected: jumps 1 → 0 when turned 180° from neutral).
- **CAM-011-D4 Normalization and smoothing.** value = clamp(0.5 + offset / (2·range), 0, 1), smoothed with
  `AudioFeatureEnvelope(attack 0.06, release 0.06).step` on the sample clock (Δt from integer nanoseconds,
  non-increasing 0, cap 0.25 s). Shake: clamp(|a| / 2 g, 0, 1) through `AudioFeatureEnvelope(0.02, 0.3)`.
  Reusing MOD-005's `step` gives NaN safety and 0…1 clamping by construction.
- **CAM-011-D5 Calibration.** `calibrate()` sets neutral to the last raw attitude, zeroes the offsets and snaps
  the smoothed attitude outputs to 0.5. Session only; never stored (privacy, and the yaw reference changes on
  every start). Default neutral: pitch 0, roll 0, yaw = first sample's yaw.
- **CAM-011-D6 Demand and lifecycle.** The coordinator runs the sensor only when (host uses motion OR the Settings
  readout is open) AND the app is active AND the device has motion. The host recomputes `usesMotion` when its
  bindings or triggers change (not per frame). Each sample also re-checks demand, so a released host stops the
  sensor within one sample. Rate: 60 Hz, 30 Hz while PERF-008's budget caps frames at 30.
- **CAM-011-D7 Frame path.** `AudioFeatureFrame.motion: MotionFeatureValues?` (a 4-Double struct, no borrow
  needed); nil reads attitude 0.5, shake 0. The host reads `motionValues?()` only when `usesMotion`.
- **CAM-011-D8 Testing without sensors.** `MotionSampling` is injected. The app test uses a manual sampler that
  pushes samples; the UI test uses DEBUG `-uitestMotionStandIn`, a stand-in reporting a fixed tilt (pitch 0.3 rad,
  roll −0.2 rad, yaw 0.1 rad) at the requested rate with a timer.
- **CAM-011-D9 Settings placement.** In the performance group (not the scene-edit group), so Calibrate stays
  usable while a scene is locked; the range is a device preference, not part of the scene.
- **CAM-011-D10 ADR.** A new sensor input in the app is recorded in an ADR (device motion modulation: no
  permission, on-device only, demand-driven sampling).
