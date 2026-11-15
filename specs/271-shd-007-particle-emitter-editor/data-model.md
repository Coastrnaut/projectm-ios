# Data Model: SHD-007 Particle Emitter Editor

Lengths in R (half the output's shorter side) from the fountain's emitter point, y up; seconds; degrees.

## ParticleEmitterSettings (VisualGenerators, `Sendable, Hashable, Codable`)

| Field | Type | Range | Default |
|---|---|---|---|
| shape | `point`, `line`, `circle`, `rectangle` | — | `point` |
| shapeWidth | Double | 0…2 | 0.4 |
| shapeHeight | Double | 0…2 (rectangle only) | 0.2 |
| rate | Double, particles/s, resolved to 0.001 | 0…240 | 30 |
| minimumSpeed, maximumSpeed | Double R/s | 0…8, ordered | 2.5, 3.5 |
| direction | Double ° from up, clockwise positive (toward +x) | −180…180 | 0 |
| spread | Double ° half-angle | 0…180 | 20 |
| minimumLifetime, maximumLifetime | Double s | 0.1…10, ordered | 1.5, 2.5 |
| gravity | Double R/s² | 0…10 | 3 |
| bounds | `none`, `floor`, `box` | — | `floor` |
| boxHalfWidth | Double | 0.2…3 | 1 |
| boxHeight | Double (above the bottom edge) | 0.5…5 | 2.5 |
| action | `bounce`, `kill` | — | `bounce` |
| restitution | Double | 0…1 | 0.6 |
| seed | UInt64 | any (the editor offers 0…65535) | 7 |

Rules: `clamped()` puts every value in range, non-finite → default, swaps an inverted min/max pair. Decoding
reads each field optionally (missing → default) and clamps. `rateMilli = UInt64((rate·1000).rounded())`.

## ParticleFountainConfiguration (changed)

`emitter: ParticleEmitterSettings?` (nil = VIS-008 behaviour). Clamped with the rest.

## ParticleFountainSimulation (changed)

New state: `spawnAccumulator: UInt64` (thousandths of a particle), `spawnAttempts` (continuous spawns tried since
reset, including dropped), `expiredCount`, `minimumAgeAtExpiry`, `maximumAgeAtExpiry` (deaths by lifetime only),
`boundKills`, `bounces`. All reset by `reset()`. The pool stays at `capacity` (512).

## ParticleEmitterChoice (app)

`enabled: Bool` (default false) + `settings: ParticleEmitterSettings`. Stored as JSON under
`settings.particleFountain.emitter`; absent at defaults. `effective` = settings when enabled, else nil.
