# Research: VIS-011 Fluid Ink

## D1 Compile site and pass type
- Decision: fragment passes into render targets, MSL appended to `NoiseFieldGenerator.shaderSource`; pipelines built
  lazily through `NativePipelineArchive.makeRenderPipelineState`.
- Rationale: ADR-0066 reviewed that site for module-constant shaders and PERF-009 keys its source; render pipelines are
  what the archive path handles. No compute pipeline exists in the reviewed sites today.
- Alternatives: compute kernels (would need an archive path for compute and a review); a new generator (new site).

## D2 Grid and formats
- Decision: 128 × 128 on every device; velocity `rg32Float`, pressure `r32Float`, divergence `r32Float`, ink
  `rgba32Float` (so the ink matches the reference solver too), health 16 × 16 `rgba32Float`. All fields read with `read()` and manual bilinear interpolation.
- Rationale: 32-bit float filtering is not guaranteed on every iOS GPU; manual bilinear matches the reference solver.
  The memory (1.06 MiB) and time are small, and one grid gives one look and one golden per platform class.
- Alternatives: 64² on compact devices (different look, extra goldens); half-float velocity (precision of the
  projection).

## D3 Step and scheduling
- Decision: fixed 1/60 s; anchor at the first frame; step k ends at anchor + k·10⁹/60 ns (integer); ≤ 4 steps per
  frame; a longer gap skips the rest and re-anchors (counted). Impulses apply at the first step whose start is ≥ their
  time (VIS-008's rule).
- Rationale: frame-rate independent at shared times; bounded work per frame.

## D4 Solver passes
- Decision per step: splat (velocity and ink), advect velocity (× 0.5^(dt/1 s), clamp speed 0.45), divergence,
  20 Jacobi iterations from p = 0, subtract gradient (clamp speed), advect ink (× 0.5^(dt/2.5 s), clamp 0…0.8). Domain
  [0,1]², cell h = 1/N, cell centres (i + 0.5)h, clamp-to-edge reads. Every pass maps non-finite to 0.
- Rationale: textbook stable fluids (Stam 1999; GPU Gems ch. 38); unconditionally stable advection, bounded projection.

## D5 Non-finite guard
- Decision: prevention in every pass plus detection: reference solver scans after each step; GPU writes a 16 × 16
  health image (per 8 × 8 block: max speed, max ink, kinetic energy sum, non-finite flag) copied each frame to one of
  three shared buffers and read when its command buffer has completed (no waiting); a flag or a value over cap
  (+1 % tolerance) resets the field on the next frame.
- Alternatives: CPU mirror at full grid (too slow in Debug); synchronous readback (waits on the GPU).

## D6 Flash bound
- Decision: global per-channel bound M (see spec Clarifications), loaded into all 64 estimate samples.
- Rationale: rigorous by the maximum principle of bilinear semi-Lagrangian advection; deterministic; cheap.
- Alternatives: per-area bound with neighbour spreading (saturates to the global in a few steps); GPU readback per
  area (lags, non-deterministic gain).

## D7 Tests within budget
- The reference solver lives in its own target `VisualFluidReference`, compiled with `-O` even in Debug (a local path
  package may use unsafeFlags, as Packages/Rendering): in plain Debug the 60 s run took 10 s, optimized 0.2 s.
- CPU stability at 32² for 60 s at 60 Hz (3 600 steps; 0.2 s); GPU stability for 60 s at 60 Hz with health
  readback every 60 frames, at 128² (3 600 steps of up to 26 passes; health read twice a second; about 2.5 s on the host). Long sweeps
  (several minutes, Reduce Motion, 30/60/120 fps) behind `VIS011_LONG=1`.
