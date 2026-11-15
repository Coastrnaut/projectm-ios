# Contract: VIS-012 Reaction Diffusion

## C1 Generator mode
`NoiseFieldConfiguration.reactionDiffusion(_ settings:reduceMotion:palette:)`; a non-nil `reactionDiffusion` forces
wedges 0, tunnelPace 0, waterfall false, fluidInk false. `NoiseFieldGenerator.reactionPass` (made in `init` in this
mode, else on the first reaction frame) exposes `textures`, `allocatedBytes`, `lastHealth`, `reloads`.
`reactionScheduler` exposes `plannedSteps`, `plannedIterations`, `totalIterations`, injection counters.

## C2 Per frame
1. Reload if entering the mode or preset/pattern/seed changed or a completed health readback flagged: seed staging
   buffer filled (`ReactionDiffusionSeed.fill`), blitted into the state; scheduler, kick detector, ramp reset.
2. Bass kick detector on the bands; scheduler plans ≤ 4 steps × iterations (≤ 64), ≤ 1 injection per step.
3. Envelope gain over 64 samples of the uniform bound.
4. Encode iterations (injection on a step's first iteration), health pass + copy, display.

## C3 Reference
`GrayScottSolver(gridSize:parameters:)` in `VisualFluidReference`: `seed(pattern:seed:)` uses the same
`ReactionDiffusionSeed.fill`; `iterate(injection:)` uses the same formula order; asserts finite and [0, 1].

## C4 App
`settings.visual = reactionDiffusion`, title "Reaction Diffusion", identifier `reactionDiffusion`, value
"<Preset>, <Pattern>, seed <n>, speed <s>, Glow off|on"; options identifiers `reactionPresetPicker`,
`reactionPatternPicker`, `reactionSeedStepper`, `reactionSpeedStepper`; no scene layer.
