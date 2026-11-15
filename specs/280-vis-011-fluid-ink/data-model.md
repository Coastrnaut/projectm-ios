# Data Model: VIS-011 Fluid Ink

- **FluidInk** (constants): grid 128, step 1/60 s, maxStepsPerFrame 4, jacobi 20, speedCap 0.45 (/s, × 0.5 Reduce
  Motion), velocityHalfLife 1 s, inkHalfLife 2.5 s, inkCap 0.8, splatRadius 0.06, splatSpeed 0.45, splatInk 0.6,
  queueCapacity 16, maxImpulsesPerStep 2, maxStrengthPerStep 1.5, reduceMotionSpacing 0.5 s, seed 1301.
- **FluidImpulse**: timeNanoseconds (UInt64), strength (0.4…1; from onset strength/threshold), index (UInt64; seeds
  position x,y ∈ 0.15…0.85, angle, palette position).
- **FluidSplat** (per applied impulse): centre, velocity (dx, dy), ink colour (linear rgb × strength × 0.6), radius.
- **FluidStepScheduler**: anchor?, stepIndex, queue (16), counters: droppedImpulses, skippedGaps, appliedImpulses.
  `advance(to:) → steps` with each step's splats (≤ 2).
- **FluidInkBound**: M (rgb), reset → 0; `step(splats:)`.
- **FluidInkSolver** (reference): N, velocity (2N²), ink (3N²), scratch; `step(splats:speedCap:)`, `reset()`,
  `health` (maxSpeed, maxInk, kineticEnergy, nonFiniteResets).
- **FluidInkPass** (GPU): textures [velocity ×2, pressure ×2, divergence, ink ×2, health], newest indices, needsReset,
  health buffers ×3 and their command buffers, resets counter.
