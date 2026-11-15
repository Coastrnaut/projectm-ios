# Data Model: VIS-016 Starfield Flight

- **StarfieldSpeed** (enum, String raw): `slow` 0.1, `medium` 0.2 (default), `fast` 0.4 depth/s; titles "Slow",
  "Medium", "Fast". Stored as `settings.starfield.speed`; anything else → `medium`.
- **StarfieldConfiguration** (value): `density` Int (clamped 1…2000), `speed`, `seed` UInt64 (default 0x5EED_0016),
  `reduceMotion`, `palette`, `background`. Constants: `capacity` 2000, `densityRange` 1…2000, `settingsDensityRange`
  100…2000 step 100, `defaultDensity` 600, `stepsPerSecond` 240, `maximumStepsPerAdvance` 240, `near` 0.05, `far` 1,
  `lateralSpread` 2, `focal` 0.5, `bassBoost` 0.5, `bassTimeConstant` 0.2, `maximumSpeed` 0.6, `reduceMotionScale`
  0.5, `baseSide` 0.004, `maximumSide` 0.04, `brightness` 0.12, `maximumAlpha` 0.8, `fadeInDepth` 0.15,
  `fadeOutDepth` 0.05, `lightBound` 0.05. `activeCount` = clamp(density).
- **Star** (value): x, y, z (Double).
- **StarfieldSimulation**: pool (2000 stars, allocated in init), `rng`, `anchorNanoseconds`, `stepIndex`, `bass`
  (smoothed), `bassTarget`, `respawnCount`, `skippedGaps`; `reset()`, `advance(toNanoseconds:)`, `setBass(_:)`,
  `star(_:)`, `effectiveSpeed`.
- **StarfieldLayout**: per drawn star a square (centre, side, colour), `squareCount`, `lightScale`, `meanLight`;
  flash regions.
- **App**: `VisualChoice.starfield`, `NativeSpectrumStyle.starfield(speed:density:)`, `AppSettings.starfieldSpeed`,
  `AppSettings.starfieldDensity`.
