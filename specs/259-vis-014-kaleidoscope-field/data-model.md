# Data Model: VIS-014 Kaleidoscope Field

- **KaleidoscopeFold** (value): `wedges` Int (2…24; < 2 = identity), `rotation` Float (rad). `fold(_ p:)` →
  folded point (research D2). Constants: `wedgeRange` 2…24, `defaultWedges` 6, `baseSpin` 0.1, `bassSpin` 0.3,
  `maximumSpin` 0.4 rad/s, `reduceMotionScale` 0.5.
- **NoiseFieldConfiguration** (VIS-013) + `wedges` Int (0 = off; else clamped to 2…24; 1 → 0);
  `effectiveSpin(low:)`; `static func kaleidoscope(wedges:reduceMotion:palette:)` = frequency 4, octaves 4,
  seed 1301 with the fold.
- **NoiseFieldDrive** (VIS-013) + `spin` (rad/s, smoothed) and `rotation` (rad, [0, 2π)); both stay 0 when
  `wedges` is 0.
- **Setting** `settings.kaleidoscope.wedges` Int 2…24, else 6; `VisualChoice.kaleidoscope`;
  `NativeSpectrumStyle.kaleidoscope(wedges:)`.
