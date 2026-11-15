# Data Model: VIS-012 Reaction Diffusion

- **ReactionDiffusionSettings** (stored): `preset` (coral|mitosis|spots|maze, default coral), `pattern`
  (square|spots|ring|stripes, default square), `seed` Int 0…9999 (default 1), `speed` Int 1…16 (default 8). Out of
  range or unknown → default. Keys `settings.reactionDiffusion.preset|pattern|seed|speed`.
- **GrayScottParameters**: feed, kill, du, dv (clamped ranges, research D3).
- **Grid state**: U, V ∈ [0, 1] on 128² (state pair), step index, anchor (ns), fade-in ramp start.
- **Injection**: time (ns), strength = clamp(bass, 0, 1), position from SplitMix64(seed, index) in 0.1…0.9.
- **ReactionDiffusionHealth**: maxU, maxV, minValue, flag (non-finite or out of [0, 1]).
- State transitions: reload (entry, preset/pattern/seed change, restart, health flag) → seeded state, ramp 0, clock
  and queue reset; Speed/palette/glow change → no reload.
