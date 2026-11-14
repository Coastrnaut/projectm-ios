# Data Model: VIS-009 Particle Orbit

- **ParticleOrbitConfiguration** (value): `particleCount` (16…256, default 160), `radius` (base, fraction of R, 0.2…0.8, default 0.5), `bassDepth` (0…1, default 0.4), `angularSpeed` (rad/s, 0.1…3, default 0.8), `particleSize` (fraction of R, 0.005…0.1, default 0.022), `seed` UInt64 (default 0x5EED0009), `reduceMotion` Bool, `palette`, `background`. Non-finite → defaults. Constants: capacity 256, beat queue 16, steps 240/s, radius bounds 0.15…0.85, offset spread 0.1, τ 0.06 s / 0.15 s (Reduce Motion), rate 3 / 1.5 R/s, pulse τ 0.2 s, pulse amplitude 0.5 / 0.2, core size 0.12 R, alphas 0.75 / 0.7. `targetRadius(base:bass:depth:)`.
- **ParticleOrbitSimulation** (reference, preallocated): per slot `phase`, `speed`, `offset`; `radius`, `targetRadius`, `pulse`; beat queue; `rng`; `anchorNanoseconds?`, `stepIndex`; counters `particleSteps`, `stepsRun`, `beatsApplied`, `droppedBeats`, `skippedGaps`.
- **ParticleOrbitRadiusDrive** (VisualParameters): `resolve(manual:kick:modulator:) -> (base, bass)`.
- **ParticleOrbitRadius** (app enum, `small`/`medium`/`large`): 0.35, 0.5, 0.65.
- **Settings**: `settings.particleOrbit.radius` = `small` | `medium` | `large` (else medium).
- **Catalog**: `visual.particleOrbit.radius`, group `visual.particleOrbit` "Particle Orbit".
