# Contract: VIS-010 Particle Trails

## C1 Generator option

`ParticleFountainGenerator.trails` and `ParticleOrbitGenerator.trails` (`ParticleTrailLength`, default `.off`).
Changes apply from the next frame. `.off` draws exactly the pre-feature frame. `restartLoop()` also clears the trail.
`trailPass` (read-only, nil until the first trails-on frame) exposes `textures`, `allocatedBytes` for tests.

## C2 Per frame (trails active)

1. h = effective half-life; d = `ParticleTrails.decay(frameDuration:halfLife:)`.
2. Gain from FX-019's envelope over `particles(g) + g·E` (C3).
3. If reset (first use, loop restart, output size change, Off → on): next = particles only; target shows no trail.
4. Else next = max(particles, cut(min(d·prev, 0.8))); target = background, then prev × d × gain ("over"), then
   particles × gain.
5. `newest` = next. No texture is created after the first trails-on frame.

## C3 Flash bound

`E_z ← min(d · (E_z + P_z), 0.8)` for luminance and redness of the 17 areas, after the frame; P = particle levels at
the frame's gain minus the background's levels; E = 0 after a reset.

## C4 App

Key `settings.particleTrails` (`off`/`short`/`long`), picker "Trails" (identifier `particleTrailsPicker`) in the
fountain's and orbit's options; accessibility value gets ", Trails Short|Long" when on.
