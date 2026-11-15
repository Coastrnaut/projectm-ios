# Contract: VIS-011 Fluid Ink

## C1 Generator mode
`NoiseFieldConfiguration.fluidInk(reduceMotion:palette:)`; `fluidInk == true` forces wedges 0, tunnelPace 0,
waterfall false. `NoiseFieldGenerator.enqueueImpulse(atNanoseconds:strength:threshold:) -> Bool` (false: ignored or
queue full). `fluidPass` (made in `init` in fluid mode, else on the first fluid frame; nil before) exposes `textures`, `allocatedBytes`, `health`.
Entering the mode and `restartLoop()` reset the field and the scheduler (storage kept).

## C2 Per frame (fluid mode)
1. Scheduler advances to the frame's time: n ≤ 4 steps, each with ≤ 2 splats.
2. Bound M steps with each step's splats; gain = envelope over 64 samples of M (× downstream transfer).
3. If a completed health readback reported non-finite or over-cap values: reset the field.
4. Encode n steps (splat, advect velocity, divergence, 20 Jacobi, gradient, advect ink), the health pass and its copy,
   then the display pass: ink sampled bilinearly across the output × gain, clamped 0…0.8, opaque.

## C3 Reference solver
`FluidInkSolver(gridSize:)` (target `VisualFluidReference`) runs the same passes with the same formulas in Float; `step(splats:speedCap:)`;
after each step a non-finite value anywhere resets to rest (counted).

## C4 App
`settings.visual = fluidInk`, title "Fluid Ink", identifier `fluidInk`, value "Ink from sudden sounds, Glow off|on";
host drains onsets into `enqueueImpulse`; no scene layer.
