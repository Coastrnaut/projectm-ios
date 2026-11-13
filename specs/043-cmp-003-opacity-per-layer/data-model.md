# Data Model: CMP-003 Opacity per Layer

All types are in the `Compositor` target; the CPU ones build on Linux.

## LayerCompositeSettings (existing, CMP-001)

- `opacity: Double` — the target opacity, 0…1; clamped by the initializer, non-finite reads 1.
- New: `isSupportedByCompositor: Bool` — `blendMode == .normal && transform == .identity` (any
  opacity). `isSupportedByCMP001` keeps its meaning.

## LayerOpacityCurve (new, CPU)

- `.linear` — position `t`.
- `.easeInOut` — smoothstep `t²(3 − 2t)`.

## LayerOpacityTransition (new, CPU)

- `duration: Double` (seconds, finite, ≥ 0), `curve: LayerOpacityCurve`.
- `init(duration:curve:) throws(LayerOpacityError)`; `.immediate` (duration 0, linear).

## LayerOpacityError (new, CPU)

- `nonFiniteTarget`, `nonFiniteDuration`, `negativeDuration`.

## LayerOpacityAnimator (new, CPU)

| Field | Meaning |
|---|---|
| `value` (read) | The opacity shown at the last `advance` (or set by `init` / immediate change) |
| `target` (read) | Where the current segment ends |
| `isAnimating` (read) | `value != target` while a segment runs |
| start, duration, curve, elapsed (private) | The current segment |

Transitions:

- `init(opacity:)` → value = target = clamp(opacity) (non-finite → 1), not animating.
- `setOpacity(_:duration:curve:)` → refuses non-finite target or bad duration (no change); else
  start = value, target = clamp(new), elapsed = 0; duration 0 sets value = target at once.
- `setOpacity(_:transition:)` → same, with a validated transition.
- `advance(by: dt)` → elapsed += max(dt, 0) (non-finite → 0); value = target when elapsed ≥
  duration, else start + curve(elapsed / duration)·(target − start), clamped to the segment.
  Returns `value`.

## Compositor record (existing, CMP-002)

- New field `opacity: LayerOpacityAnimator`, created from the entry's (or layer's) settings.
- `apply`: kept record whose entry opacity changed → `setOpacity(new, transition:)`; new record →
  animator at the entry's opacity.
- `composite`: every record's animator advances by the frame's `frameDuration`; a shown picture is
  drawn with that value unless it is 0.
