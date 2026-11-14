# Contract: MOD-008 Stepped LFO

- **S1 Shapes**: `LFOShape.square`, `.sampleHold`; stored names `"square"`, `"sampleHold"`.
- **S2 Square**: value = clamp(center + amplitude/2 · (φ < dutyCycle ? 1 : −1), 0, 1); φ = dutyCycle is low.
- **S3 Sample-and-hold**: value of step n = clamp(center + amplitude · (level(seed, n) − 0.5), 0, 1);
  constant for the whole step when glide = 0. `level` is `SteppedRandom.level(seed:step:)` (research D1).
- **S4 Step number**: n = ⌊phaseOffset + rate·t⌋ for a free oscillator, exact (no drift); synced oscillators
  continue n across rate changes.
- **S5 Seed**: effective seed = `UInt64(seed)` when set, else `SteppedRandom.defaultSeed(slot:)` = 2³² + slot.
  `LFO.value(elapsedNanoseconds:…)` outside a bank uses slot 0.
- **S6 Determinism (acceptance)**: for the same LFO settings, seed and origin, every frame time sequence
  yields the same value at the same time; in particular every step holds the same level.
- **S7 Validation**: dutyCycle 0.05…0.95, glide 0…1, finite; else `LFOError.invalidSettings`.
- **S8 Scene**: entry fields `duty` (number), `seed` (whole number 0…4294967295), `glide` (number); written by
  `SceneLFOEntry(_:)` only per research D5; invalid → `invalidLFO`, entry kept.
