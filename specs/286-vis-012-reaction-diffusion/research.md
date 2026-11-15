# Research: VIS-012 Reaction Diffusion

## D1 Compile site and pass type
- Decision: fragment passes into render targets; MSL appended to `NoiseFieldGenerator.shaderSource`; pipelines through
  `NativePipelineArchive.makeRenderPipelineState` (as VIS-011 D1).
- Alternatives: compute kernels or a new generator (a new compile site to review).

## D2 Model, grid and format
- Decision: Gray–Scott, explicit Euler dt = 1, 9-point Laplacian (−1, 0.2, 0.05), torus, 128² on every device, state
  pair `rg32Float` (U, V), health 16 × 16 `rgba32Float`; texels read with `read()` (no filtering).
- Rationale: the Sims formulation is stable with Du ≤ 1 (diffusion is a convex combination), well known presets exist
  for it, and 32-bit floats keep CPU and GPU arithmetic alike. 0.25 MiB.
- Alternatives: 256² (4× the work for little visible gain on a phone); half floats (pattern drift between devices).

## D3 Presets
- Decision: Coral (0.0545, 0.062), Mitosis (0.0367, 0.0649), Spots (0.030, 0.062), Maze (0.029, 0.057); Du 1.0, Dv 0.5.
  Clamp F 0.01…0.10, k 0.04…0.07, Du 0.2…1.0, Dv 0.1…0.5.
- Rationale: each preset grows from a small seed on a 128² torus; the ranges keep the explicit scheme stable.

## D4 Seeds
- Decision: CPU-generated initial texture (Float32) written into a shared staging buffer made once, blitted into the
  state texture at a reload. SplitMix64 over the stored seed decides spot positions and radii, square/ring offsets and
  the stripe phase.
- Rationale: one implementation gives the GPU and the reference bit-identical starts; no seed shader to keep in step.
- Alternatives: a GPU seed shader (fast-math float differences would break bit identity).

## D5 Iteration bound
- Decision: 1/60 s fixed steps from an exact-nanosecond anchor, ≤ 4 per frame (stall skip), Speed 1…16 iterations
  per step (Reduce Motion ⌈Speed/2⌉) → ≤ 64 per frame (`maximumIterationsPerFrame`).
- Rationale: the same steps at shared times for any frame rate (VIS-011 D3); worst case 64 × 16 K fragments.

## D6 Audio
- Decision: bass kicks from the frame's bands (VIS-007's low group; above 0.6 after below 0.4; ≥ 0.25 s apart, 1 s
  under Reduce Motion), queue 4, ≤ 1 per step, Gaussian radius 0.04, ±0.25 × bass to V/U, seeded position.
- Alternatives: feed modulation (can leave a preset's stable region and wipe the pattern); onset bus (needs a host
  subscription; bands are already delivered every frame).

## D7 Non-finite guard and health
- Decision: exponent-bit test `(bits & 0x7f800000) == 0x7f800000` → 0, then clamp [0, 1] in every pass; health image
  (max U, max V, min value, flag) read back without waiting from three shared buffers; a flag re-seeds (counted).

## D8 Display and light bound
- Decision: t = smoothstep(0.1, 0.4, V); colour = palette8(t) × t × ramp × gain, channels ≤ 0.8; ramp 0 → 1 over 1 s
  after each reload. Envelope input: uniform min(0.8, brightest stop) × ramp per channel (`loadUniform`).
- Rationale: a rigorous upper bound like VIS-011's; the ramp makes every reload a slow rise, so reloads cannot strobe.
