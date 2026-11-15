# Contract: Particle emitter (SHD-007)

## E1 Simulation (VisualGenerators, pure Swift)

- `ParticleFountainSimulation(configuration:)` with `configuration.emitter = settings`.
- `advance(toNanoseconds:)`: unchanged schedule (anchor on first call, step k at anchor + ⌊k·10⁹/240⌋, at most
  240 steps per call). Before each step: queued onsets (bursts drawn with the emitter's shape, velocity and
  lifetime), then `accumulator += rateMilli` (rate halved under Reduce Motion); if `accumulator ≥ 240 000`, one
  spawn attempt (`accumulator −= 240 000`). An attempt with a full pool counts in `droppedParticles`.
- Step: semi-implicit Euler with the particle's gravity and drag, age += 1/240, then bounds (bounce or kill),
  then death when age ≥ lifetime (recorded in the expiry stats).
- Invariants: `spawnAttempts == ⌊rateMilli·steps/240 000⌋` at constant rate; `liveCount ≤ 512`; with bounds on,
  every live particle is inside them after every step; same seed and settings → identical particles.

## E2 Settings

- `ParticleEmitterSettings` ranges and defaults per data-model.md; `clamped()`; `Codable` lenient decode.

## E3 App

- `AppSettings.particleEmitter: ParticleEmitterChoice`, key `settings.particleFountain.emitter`.
- `NativeSpectrumStyle.particleFountain(gravity:emitter:)`; the host applies `emitter` to the fountain's
  configuration on build and in place.
- Settings › "Particle emitter" (`particleEmitterLink`) → screen with identifiers `particleEmitterEnabled`,
  `particleEmitterPreview`, `particleEmitterReset`, `particleEmitterNewSeed`, `particleEmitterSeed`,
  `particleEmitterShape`, `particleEmitterRate` and the other sliders `particleEmitter<Name>`.
