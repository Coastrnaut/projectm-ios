# Data Model: UIX-005 Performance Control Layout

## PerformanceLayout (ShowControl, value type)

| Field | Meaning |
|---|---|
| `arrangement` | `.bottomBar`, `.bottomGrid` (two rows of two), `.sideColumns` |
| `target` | side of a square target: 60, or 72 when `regular` |
| `spacing` | 12, or 16 when `regular` |
| `margin` | 8: space around the pad inside the safe area |
| `columnWidth` | `target + 2 × margin` (side columns) |
| `reservedInsets(barHeight:)` | (top, leading, bottom, trailing): side columns reserve `columnWidth` leading and trailing; a bar reserves `barHeight + margin` at the bottom |

Inputs: `width`, `height` (the safe-area size), `regular` (both size classes regular).
Rules: `width > height` → `.sideColumns`; else one row fits when
`4 × target + 3 × spacing + 2 × margin ≤ width` → `.bottomBar`, otherwise `.bottomGrid`.

## Performance layout state (app, session)

`AppCoordinator.performanceLayout: Bool`, false at launch (DEBUG `-uitestPerformanceLayout` → true). Not stored.

## Blackout target (app, derived)

From `OutputBlackout.Phase`: live/fadingIn → "Black out output", `eye.slash`, enabled, B key;
blackedOut → "Restore output", `eye`, enabled; restoreWaiting → "Restoring output", `eye`, disabled.
Accessibility value: the phase's OUT-010 value ("Live", "Blacked out", "Restore waiting", "Fading in").
