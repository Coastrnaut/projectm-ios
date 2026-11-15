# Data Model: VIS-017 Signed-Distance Primitives

## SignedDistanceQuality (enum, String raw value; stored by the app)
| Case | Step cap | Hit threshold | Title |
|---|---|---|---|
| low | 24 | 0.004 | Low |
| medium (default) | 48 | 0.002 | Medium |
| high | 96 | 0.001 | High |
Absolute ceiling `SignedDistanceScene.maximumSteps` = 128 (the shader clamps too).

## SignedDistanceSettings (struct, Sendable, Equatable)
- `quality: SignedDistanceQuality` (default medium). Stored in `NoiseFieldConfiguration.signedDistance` (nil = off; on forces wedges 0, tunnel 0, waterfall/fluid off, reaction nil).

## SignedDistancePose (struct; the drive's output for one frame)
- `angle: Float` in [0, 2π); `sphereRadius: Float` in 0.55…0.70; `brightness: Float` in 0.5…0.8. `sanitized()` replaces non-finite values with the rest pose.

## SignedDistanceDrive (struct)
- `swell` (0…1), `spin` (rad/s, ≤ 0.6), `angle`, `brightness`, last frame time. `advance(groups:timeNanoseconds:reduceMotion:)`; `reset()`; `pose`.

## SignedDistanceMarch (struct; one ray's result)
- `steps: Int` (0…cap), `distance: Float` (ray parameter), `kind: SignedDistanceKind?` (`sphere`, `torus`, `box`; nil = miss).

## Constants (SignedDistanceScene)
Bounding radius 2.0; camera distance 4.5; focal 1.07 (≈ 50° vertical FOV over the shorter side); sphere 0.55 + 0.15 × swell; torus R 1.05, r 0.11, tilt 0.5 rad; boxes ×4, half-size 0.16, rounding 0.03, orbit 1.6; light direction normalize(0.5, 0.8, −0.6); ambient 0.15.
