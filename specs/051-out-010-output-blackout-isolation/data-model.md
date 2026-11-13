# Data Model: OUT-010 Output Blackout Isolation

## OutputBlackout (PresentationLifecycle, value type, session state)

| Field | Type | Meaning |
|---|---|---|
| `phase` | `.live`, `.blackedOut`, `.restoreWaiting`, `.fadingIn` | The state below. |
| `luminanceFactor` | Double 0…1 | The output's luminance as a fraction of the content's (0 = black). |
| `sinceRestoreStart` | Double ≥ 0 (private) | Clamped frame time since the last restore started; +∞ before the first. |

Derived: `coverOpacity = 1 − sRGBEncode(luminanceFactor)`; `isBlack` (`luminanceFactor == 0`);
`isBlackoutRequested` (`.blackedOut` or `.restoreWaiting`: the control shows "Restore output");
`needsFrames` (`.restoreWaiting`, `.fadingIn`, or `sinceRestoreStart` below the spacing).

Constants: `restoreSpacing = 1 s`; `fadeDuration(reduceFlashing:)` = 4 s on, 1 s off;
`maxFrameTime = 0.1 s`.

### Transitions

| From | Event | To | Effect |
|---|---|---|---|
| any | `blackOut()` | `.blackedOut` | `luminanceFactor = 0` at once |
| `.blackedOut` | `restore()`, spacing passed | `.fadingIn` | `sinceRestoreStart = 0` |
| `.blackedOut` | `restore()`, spacing not passed | `.restoreWaiting` | none |
| `.restoreWaiting` | `advance` reaches the spacing | `.fadingIn` | `sinceRestoreStart = 0` |
| `.fadingIn` | `advance(dt)` | `.fadingIn` / `.live` | `luminanceFactor += dt / fadeDuration`; `.live` at 1 |
| `.live`, `.fadingIn` | `restore()` | unchanged | none |

`advance(frameTime:reduceFlashing:)` clamps the frame time to 0…0.1 s (NaN and negatives are 0) and
adds it to `sinceRestoreStart` in every phase.

## Slot cover (app)

Each `VisualSlotView` has one black cover layer; the coordinator sets every slot's cover to the
model's `coverOpacity` (actions disabled) whenever the model changes and before every placement.
