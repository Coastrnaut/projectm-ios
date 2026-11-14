# Data Model: MOD-008 Stepped LFO

| Entity | Fields | Rules |
|---|---|---|
| `LFOShape` | `sine`, `triangle`, `square`, `sampleHold` (raw values are the stored names) | Unknown names: `unknownLFO` (MOD-007). |
| `LFO` (extended) | `dutyCycle: Double` (default 0.5), `seed: UInt32?` (nil), `glide: Double` (default 0) | duty 0.05…0.95, glide 0…1, finite; checked by `validationProblem` for every shape. |
| `LFOCycle` | `step: Int64`, `phase: Double` (0…<1) | Whole cycles since the origin including the phase offset; from the exact phase sum. |
| `SteppedRandom` | `level(seed: UInt64, step: Int64) -> Double` (0…<1), `defaultSeed(slot:)` = 2³² + slot | Pure, integer-only. |
| `LFOPhaseSegment` (MOD-009, extended) | `startCycle: Int64` | A new segment starts at the reached step and phase. |
| Scene entry | optional `duty`, `seed`, `glide` | Written only when they matter (research MOD-008-D5). |

Value rules (output 0…1, clamped, finite):

- square: centre + amplitude/2 · (phase < duty ? +1 : −1)
- sample-and-hold: centre + amplitude · (L − 0.5), L = level(seed, step), or the glide ramp from
  level(seed, step − 1) while phase < glide.
