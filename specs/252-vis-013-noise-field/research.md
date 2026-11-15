# Research: VIS-013 Noise Field

- **VIS-013-D1 Shared noise.** Decision: `SeededNoise` (VisualGenerators) holds the lowbias32 finalizer, the
  lattice hash, value noise, fBm and the domain point, operation for operation as SHD-006 contract N2;
  `SeededNoiseShader.functions` holds `mat_nhash`, `mat_snoise`, `mat_sfbm` verbatim. The material literal keeps
  its own text because SHD-001's source-safety test forbids interpolation; `SharedNoiseSourceTests` asserts
  containment, and `MaterialNoiseTests`' recorded digests prove the material is unchanged. Alternatives: a
  dependency from VisualGenerators to ProceduralMaterials (cycle); an unguarded copy.
- **VIS-013-D2 Drawing.** One full-screen triangle, fragment shader: q = p × frequency + (phase, 0.5 phase); warp
  from fields 1 and 2 at warp frequency 1; n = fBm field 0; t = clamp((n − 0.2)/0.6, 0, 1) indexes 16 palette
  colours interpolated in linear light; colour = palette(t) × (0.25 + 0.75 n) × brightness × gain; non-finite → 0;
  alpha 1. Uniforms passed with `setFragmentBytes` from a preallocated buffer.
- **VIS-013-D3 Drive.** Groups from VIS-007's `MandalaBandGroups` (low, mid, high). Warp target = 0.5 + 1.0 ×
  depth × low (depth 0.5 under Reduce Motion); brightness target = 0.5 + 0.3 × mean(low, mid, high), ≤ 0.8. One-pole
  smoothing a += (target − a)(1 − exp(−Δt/0.25)), Δt clamped to 0…0.1 s. Phase = speed × seconds since the anchor
  (first frame after reset), speed 0.12 cells/s (0.06 with Reduce Motion), per-frame advance ≤ 1 s, never backwards.
- **VIS-013-D4 Flash estimate.** 8 × 8 sample points at the centres of an 8 × 8 grid (four per 4 × 4 safety tile)
  evaluated with the CPU mirror and the frame's warp and phase; per area the mean relative luminance and redness
  of the sample colours × brightness, linear in the gain, handed to `FlashEnvelope.gain(frameTime:configuration:)`.
  At most 64 × 3 × 6 noise evaluations per frame.
- **VIS-013-D5 Determinism proof.** `NoiseFieldRenderTests` renders 64 × 64 frames after a fixed fixture band
  timeline (30 frames at 60 Hz) twice from fresh generators and compares bytes; FNV-1a 64 per GPU class
  (`MTLDevice.name`) as `MaterialNoiseTests`; unknown GPUs print the digest and skip that comparison.
- **VIS-013-D6 Seed control.** New Seed uses `NoiseSeedSequence` (SHD-006-D8) with its counter kept in memory for
  the session (not stored): deterministic across installs, never the system random source.
