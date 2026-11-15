# Contract: Kaleidoscope fold (VIS-014)

- K1 `KaleidoscopeFold(wedges:rotation:)`, `fold(_: SIMD2<Float>) -> SIMD2<Float>`; `KaleidoscopeFoldShader.function`
  (MSL `float2 vis_kfold(float2 p, float wedges, float rotation)`, same operations). Identity for wedges < 2.
- K2 Continuity: for any p and N, |fold(p + ε) − fold(p)| ≤ |ε| (the fold is 1-Lipschitz).
- K3 Symmetry: fold(R(2π/N)·p) = fold(p) and fold(M_k·p) = fold(p) for each mirror axis M_k.
- K4 `NoiseFieldGenerator` with `configuration.wedges == 0` draws byte-identical frames to VIS-013 (digests).
- K5 `NoiseFieldDrive.rotation` advances by `spin × Δt` (Δt ≤ 1 s, never negative) only when folded.
