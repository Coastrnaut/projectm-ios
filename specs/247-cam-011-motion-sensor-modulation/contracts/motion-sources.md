# Contract: motion sources (CAM-011)

- **M1 IDs**: `audio.motion.pitch`, `audio.motion.roll`, `audio.motion.yaw`, `audio.motion.shake`; `AudioFeatureSource(id:)` parses exactly these; `id` round-trips. Names: "Tilt forward", "Tilt sideways", "Turn", "Shake".
- **M2 Value**: `AudioFeatureSource.motion(axis).value(in:)` returns the frame's `motion` value for the axis, clamped to 0…1, non-finite → neutral (0.5 attitude, 0 shake); nil `motion` → neutral.
- **M3 Normalization**: attitude = clamp(0.5 + offset/(2·range), 0, 1), offset = unwrapped angle − neutral, |offset| ≤ 2π, smoothed by a 60 ms one-pole.
- **M4 Shake**: clamp(√(x²+y²+z²)/2, 0, 1) through attack 20 ms / release 300 ms.
- **M5 Calibration**: after `calibrate()`, every attitude value is 0.5 for the current attitude.
- **M6 Robustness**: any input (NaN, ±∞, huge values, time going backwards) leaves every value finite in 0…1.
- **M7 Expressions**: the names are refused (unknown name).
- **M8 Sampling (app)**: the sensor runs only while available, active and demanded; 60 Hz, or 30 Hz when the power budget caps 30 fps.
- **M9 Setting**: `settings.motion.range` ∈ {narrow, medium, wide}; written on change only; in FILE-005 included keys, `ALLOWED_KEYS`, removed by `-uitestResetNotice`.
