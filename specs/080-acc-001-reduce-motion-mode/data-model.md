# Data Model: ACC-001 Reduce Motion Mode

## MotionPolicy (value, app target)

| Field | Type | Meaning |
|---|---|---|
| `reduceMotion` | Bool | The system Reduce Motion state (or the DEBUG override). |

Derived:

- `decoration(_ animation: Animation) -> Animation?` — nil when `reduceMotion`, else `animation`.
- `seconds(_ s: Double) -> Double` — 0 when `reduceMotion`, else `s`.
- `controlsAnimation: Animation?` — `decoration(.easeInOut(duration: MotionPolicy.controlsSeconds))`.
- `controlsTransitionSeconds: Double` — `seconds(MotionPolicy.controlsSeconds)` (0.2 s or 0).
- `static safetyFade(_ animation: Animation) -> Animation` — identity; marks a safety fade (R4).

No stored data. State transitions: `reduceMotion` follows the system setting (notification, scene
activation) and, in DEBUG, the override.

## AppCoordinator additions

- `motion: MotionPolicy` (computed from `settings.systemReduceMotion`).
- DEBUG: `lastControlsTransitionSeconds: Double?` — set whenever `controlsVisible` changes, from
  `motion.controlsTransitionSeconds`.
