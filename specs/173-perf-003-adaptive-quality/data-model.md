# Data model: PERF-003 Adaptive effect quality

## EffectQualityLevel (enum, Int raw, Comparable)

`full = 0`, `reduced = 1`, `minimal = 2`; `label` "full", "reduced", "minimal". Higher raw = cheaper.

## Inputs

- `EffectThermalState`: nominal, fair, serious, critical (the app maps `ProcessInfo.ThermalState`; unknown → serious).
- Low Power: Bool.
- `EffectBudgetSignal`: unavailable, within, over.
- Time: seconds, monotonic (display-link timestamp); non-finite or backwards values are ignored.

## EffectQualityPolicy

`overBudgetHold` 3 s, `recoveryHold` 10 s, `fadeDuration` 0.4 s; non-finite or ≤ 0 values read the defaults.

## EffectQualityLadder (state)

| Field | Meaning |
|---|---|
| target | the level the inputs ask for |
| applied | the level the glow is drawn at |
| glowWeight | 0…1, multiplies the clamped glow intensity |
| overBudgetTime, goodTime | hold timers |
| reason | `EffectQualityReason?` (thermal, low power, budget; nil at Full) |

Transitions per step (dt ≥ 0):
1. floor = max(thermal floor, Low Power floor). If floor > target: target = floor, goodTime = 0.
2. budget over: overBudgetTime += dt; at ≥ hold: target = min(target + 1, minimal), timers 0. Otherwise overBudgetTime = 0.
3. target > floor and budget not over: goodTime += dt; at ≥ recoveryHold: target −= 1, goodTime = 0. Else goodTime = 0.
4. target ≠ applied: w −= dt / fade; at w ≤ 0: w = 0, applied = target. target = applied and w < 1: w += dt / fade (≤ 1).
5. `intensityFactor` = applied == minimal ? 0 : w.

`start(thermal:lowPower:)`: target = applied = floor, w = 1, timers 0.

## BloomPlan (extended)

`init(parameters:width:height:quality:)`, `quality` default `.full` (today's plan). Reduced per research D2;
Minimal keeps Full's sizes (the effect is pass-through). Invariant: `haloExtent(reduced) ≤ haloExtent(full)`.
`blurWork` = reducedWidth × reducedHeight × (2R + 1) × 2 (texel reads of the two blur passes).

## Diagnostics `frameTimings.effectQuality` (optional)

`{ "level": "full" | "reduced" | "minimal", "reason": "thermal" | "low power" | "budget" (optional) }`.
