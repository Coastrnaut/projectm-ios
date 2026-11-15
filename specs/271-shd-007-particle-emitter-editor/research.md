# Research: SHD-007 Particle Emitter Editor

- **SHD-007-D1 Extend the fountain, not a new generator.** Decision: an optional `emitter` in
  `ParticleFountainConfiguration`. Rationale: the fountain already has the pool, the seeded SplitMix64, fixed
  steps on the injected clock, the layout, the Metal pass, flash areas and the app wiring; nil keeps VIS-008 and
  its goldens bit for bit. Alternatives: a new `ParticleEmitterGenerator` (duplicates all of that and needs a new
  visual choice); applying to the Particle Orbit too (orbits have no spawn shape or collisions).
- **SHD-007-D2 Exact counts with an integer accumulator.** Decision: rate stored as thousandths per second
  (`UInt64`), accumulator += rateMilli per step, spawn while accumulator ≥ 240 000. Rationale: integer arithmetic
  gives ⌊rateMilli·k/240 000⌋ exactly; Double accumulation of rate·dt drifts (1/240 is not representable).
  Rate ≤ 240/s keeps it at most one spawn per step. Alternatives: `floor(rate·t)` from the elapsed time (jumps on
  a rate change), Poisson spawning (no exact count).
- **SHD-007-D3 Draw order.** Decision: per particle, position draws (shape: 0, 1 or 2 units), direction, speed,
  lifetime — always in that order, also when a range is degenerate (the draw is still taken). Rationale: changing
  one range never shifts another value's draws, so runs stay comparable.
- **SHD-007-D4 Death by age is checked after the step.** A particle dies at the first step with age ≥ lifetime,
  so the age at death is in [lifetime, lifetime + 1/240). Collisions are resolved before the age check.
- **SHD-007-D5 Bounds.** Floor = the output's bottom edge, y = −0.1 R (the emitter sits 0.1 R above it). Box:
  |x| ≤ halfWidth, −0.1 ≤ y ≤ height − 0.1. Bounce puts the particle on the bound and sets the component to
  −v·restitution; kill removes it. Spawn positions are clamped into the bounds. None: VIS-008's floor/side kill
  is not applied; the lifetime ends every particle (at most 10 s).
- **SHD-007-D6 Seed.** The emitter's seed replaces the configuration seed when present (reset restores it).
- **SHD-007-D7 Preview.** SwiftUI `Canvas` drawing `ParticleFountainLayout` squares of a private simulation
  advanced on a fixed 30 fps clock in a `TimelineView(.animation)` tick (the tick only advances the frame index;
  time comes from the index). Rationale: the real simulation and layout code; no Metal context needed in Settings.
  Alternatives: SHD-012's material fixture (materials only), an MTKView (heavier, a second render loop).
- **SHD-007-D8 Storage.** One JSON key holding `{enabled, settings}`; included in backups (a creative setting
  like the fountain's gravity). Lenient decoding: each field optional, clamped.
- **SHD-007-D9 New seed.** SplitMix64 of a per-launch counter, mod 65 536, skipping the current seed (SHD-006).
