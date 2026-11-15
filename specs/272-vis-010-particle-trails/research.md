# Research: VIS-010 Particle Trails

- **VIS-010-D1 Accumulation size**: Decision: fixed 512 × 512 `rgba16Float`, independent of output. Rationale: the
  acceptance asks for constant allocation; a drawable-sized pair would be reallocated at every rotation. 16-bit float
  avoids the 8-bit rounding stall (`round(v·d) = v` for small v). Alternatives: drawable size (rejected), 1024² (16 MiB).
- **VIS-010-D2 Blend**: Decision: FX-009's max blend with decay (ADR-0051), plus a 0.8 cap and a 1/512 cut.
  Rationale: bounded by the brightest particle, no tone map needed; the cut makes trails fade to exactly 0 in finite
  time. Alternatives: additive (runaway to 1/(1 − d)).
- **VIS-010-D3 Decay**: Decision: `d = min(0.5^(Δt/h), 0.99)`, Δt clamped to 0…0.1 s; Short 0.1 s, Long 0.3 s.
  Rationale: same fade per second at any frame rate (product of per-frame factors = 0.5^(t/h)). The package cannot
  import the compositor's `MotionFeedback`, so the formula is restated and its constants matched.
- **VIS-010-D4 Draw order**: Decision: pass 1 writes `next = max(particles, cut(min(d·prev, 0.8)))` (decay triangle,
  then particles with `MTLBlendOperation.max`); pass 2 clears the target to the background, draws `prev` sampled
  linearly × d × gain with premultiplied "over", then the crisp particles. Rationale: the shown trail never doubles
  the current particles, and current particles keep full resolution.
- **VIS-010-D5 Flash bound**: Decision: per area and signal `E ← min(d·(E + P), 0.8)`, P = the frame's particle
  levels at the frame's gain minus the background's; envelope input = particles(g) + g·E. Rationale: mean of a
  per-pixel max ≤ sum of means; nondecreasing in g as the envelope's bisection needs.
- **VIS-010-D6 Compile site**: Decision: append the trail MSL to `FlatShapePass.shaderSource`; `FlatShapePass` keeps
  its `MTLLibrary`; trail pipelines go through `NativePipelineArchive.makeRenderPipelineState`. Rationale: no new
  `METAL_SOURCE_ALLOWED` entry and no ADR (SHD-011, ADR-0024).
- **VIS-010-D7 Allocation timing**: Decision: lazily on the first trails-on frame, kept for the generator's life.
- **VIS-010-D8 Fixture**: Decision: the 10-minute fixture runs the CPU model for all 36 000 frames at 16 × 16 and the
  GPU generator for the 36 000-frame clock at 8 × 8 output, encoding every frame but committing in batches is not
  possible (triple-buffered slots), so every frame is committed and waited on only when no slot is free; if this
  exceeds the budget, the GPU part encodes a representative subset (every frame for the first and last minute plus
  every 10th frame between) while the clock still advances every frame.
