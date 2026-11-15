# Data Model: CAM-011 Motion Sensor Modulation

| Entity | Fields | Rules |
|---|---|---|
| `MotionAxis` | `pitch`, `roll`, `yaw`, `shake` (String raw values) | ID segment of `audio.motion.<axis>`. |
| `MotionSample` | `pitch`, `roll`, `yaw` (rad), `accelerationX/Y/Z` (g), `timeNanoseconds` (UInt64) | Any field may be non-finite; such components are ignored. |
| `MotionRange` | `narrow` (20°), `medium` (45°, default), `wide` (90°) | Stored as raw value under `settings.motion.range`; absent/unknown → medium. |
| `MotionFeatureValues` | `pitch`, `roll`, `yaw`, `shake` (Double, 0…1) | `neutral` = (0.5, 0.5, 0.5, 0). Always finite, 0…1. |
| `MotionTracker` | neutral attitude, last raw attitude, unwrapped offsets (±2π), smoothed outputs, last time, range | `ingest(_:)`, `calibrate()`, `restart()`, `values`. No allocation. One owner (main actor in the app). |
| `MotionModulationCoordinator` (app) | sampler, tracker, range, `isAvailable`, `isSampling`, `readoutOpen`, host demand, app active | Sampling ⇔ available ∧ active ∧ (host demand ∨ readout open). |

State transitions of sampling: Stopped → (demand true) → Sampling(rate) → (demand false / background) → Stopped.
On every start the tracker's unwrapping restarts (first sample re-anchors) and smoothing snaps.
