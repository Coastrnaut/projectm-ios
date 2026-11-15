# Contract: Starfield flight (VIS-016)

- S1 `StarfieldConfiguration.activeCount` = min(max(density, 1), 2000); the pool holds 2000 stars allocated once.
- S2 `reset()` re-seeds the generator and redraws every star (x, y, z in index order): positions equal a fresh
  simulation's bit for bit.
- S3 `advance(toNanoseconds:)` runs step k when anchor + ⌊(k+1)·10⁹/240⌋ ≤ t (at most 240 per call; a longer gap
  moves the anchor and counts a skip); the first call after reset sets the anchor only; earlier times do nothing.
- S4 Per step: bass ← bass + (target − bass)(1 − e^(−Δt/0.2)); v = min(speed × (1 + 0.5·bass), 0.6) × (0.5 if Reduce
  Motion); for each star in index order z −= v·Δt; if z < near: z += far − near, x, y redrawn (x then y).
- S5 Layout: centre + (x, −y)·0.5·R/z; side clamp(0.004·R/z, 1 px, 0.04 R); alpha min(0.2/z, 0.8) × fades; only the
  first `activeCount` stars, only those inside the frame; mean light ≤ 0.05 by a uniform alpha scale.
- S6 Generator: bands → low group → `setBass`; advance; layout; FX-019 gain; tessellate; `FlatShapePass`. No allocation
  per frame. `restartLoop()` resets the simulation and the limiter's slew.
- S7 Host: accessibility value "<Speed> speed, <n> stars, <glow>"; speed and density change in place.
