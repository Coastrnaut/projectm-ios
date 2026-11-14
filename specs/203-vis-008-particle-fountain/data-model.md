# Data Model: VIS-008 Particle Fountain

- **ParticleFountainConfiguration** (value): `gravity` (R/s², 0.5…10, default 3.0; non-finite → default), `drag` (per second, 0…5, default 0.8), `life` (s, 0.5…10, default 2.5), `particleSize` (fraction of R, 0.005…0.1, default 0.025), `seed` UInt64 (default 0x5EED0008), `reduceMotion` Bool, `palette`, `background` (premultiplied linear). Constants: `capacity` 512, `onsetQueueCapacity` 32, `stepsPerSecond` 240, `maximumStepsPerAdvance` 240, `minimumBurst` 4, `burstRange` 20, `excessScale` 0.25, `coneHalfAngle` 20°, `speedRange` 3.0…4.0 R/s, `emitterHeight` 0.1, `floor` −0.15, `sideBound` 3, `peakAlpha` 0.8, `attackSeconds` 0.05, `reduceMotionTimeScale` 0.7. `burstSize(strength:threshold:)`; `effective…` values under Reduce Motion.
- **ParticleGravity** (app enum, String raw values `low`, `medium`, `high`): G = 2.0, 3.0, 4.5.
- **SplitMix64** (value): `state`; `next() -> UInt64`, `unit() -> Double`.
- **Particle** (value): `x`, `y`, `vx`, `vy` (R, R/s), `age`, `life` (s), `gravity`, `drag`, `sequence` (spawn order since the last restart).
- **ParticleFountainSimulation** (reference, preallocated): pool of `capacity` particles (dense array, swap-remove on death), onset queue, `rng`, `anchorNanoseconds?`, `stepIndex`, `liveCount`, `spawnedCount`, `droppedParticles`, `droppedOnsets`, `simulatedNanoseconds`; `enqueueOnset(atNanoseconds:strength:threshold:)`, `advance(toNanoseconds:)`, `reset()`, `particle(_:)`.
- **Settings**: `settings.particleFountain.gravity` = `low` | `medium` | `high` (else medium).
