# Contract: MOD-016 Random walk modulator

- **W1 Shape**: `LFOShape.randomWalk`; stored name `"randomWalk"`.
- **W2 Value**: at step n and phase φ: clamp(center + amplitude · (W − 0.5), 0, 1), W = T(n) + (T(n + 1) − T(n)) ·
  `RandomWalk.ease(φ, smoothness:)`, T(n) = `SteppedRandom.level(seed:step:)` with the effective seed (MOD-008 S5).
- **W3 Ease**: e(φ) = (1 − s)·φ + s·(6φ⁵ − 15φ⁴ + 10φ³), result clamped to 0…1; e(0) = 0, monotone non-decreasing.
- **W4 Bounds**: W lies between T(n) and T(n + 1), so every value is in [min, max] of
  clamp(center ± amplitude/2, 0, 1) and finite.
- **W5 Continuity**: free oscillator at rate r: |v(t₂) − v(t₁)| ≤ amplitude · `RandomWalk.maximumSlope(smoothness:)`
  · r · |t₂ − t₁| (+1e-12).
- **W6 Determinism (acceptance)**: for the same settings, seed and origin, every frame time sequence and every
  seek yields the same value at the same time (exact equality).
- **W7 Validation**: smoothness 0…1, finite; else `LFOError.invalidSettings`.
- **W8 Scene**: entry field `smoothness` (number); written by `SceneLFOEntry(_:)` only for `randomWalk` when not 1;
  invalid → `invalidLFO`, entry kept. Tempo sync, seed and the Reduce flashing cap behave as for sample-and-hold.
