# Data Model: MOD-016 Random walk modulator

| Entity | Fields | Rules |
|---|---|---|
| `LFOShape` | adds `randomWalk` (stored name) | Unknown names: `unknownLFO` (MOD-007). |
| `LFO` (extended) | `smoothness: Double` (default 1) | 0…1, finite; checked by `validationProblem` for every shape. Reuses `rateHz`, `phaseOffset`, `amplitude` (depth), `center`, `sync`, `seed`. |
| `RandomWalk` | `ease(_ phi:, smoothness:) -> Double`, `maximumSlope(smoothness:) -> Double` | Pure; e(0) = 0, e(1) = 1, monotone; slope ≤ (1 − s) + 1.875·s. |
| Target | T(n) = `SteppedRandom.level(seed, n)` | Pure function of seed and step (MOD-008). |
| Scene entry | optional `smoothness` | Written only for `randomWalk` when not 1 (research MOD-016-D4). |

Value rule (output 0…1, clamped, finite): centre + amplitude · (W − 0.5), W = T(n) + (T(n + 1) − T(n)) · e(φ),
where (n, φ) is the oscillator's exact step and phase.
