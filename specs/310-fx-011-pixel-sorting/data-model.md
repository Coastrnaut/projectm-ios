# Data Model: FX-011 Pixel Sorting Approximation

## PixelSort (Compositor, plain Swift)

| Field | Type | Range / default |
|-------|------|-----------------|
| isEnabled | Bool | false |
| threshold | Double | 0…1, default 0.5 (NaN → 0.5) |
| span | Int | one of 4, 8, 16, 32, 64; default 32 (others snap down, minimum 4) |
| direction | Direction (`horizontal`, `vertical`) | horizontal |

## PixelSort.Plan

| Field | Meaning |
|-------|---------|
| runs | the pass is encoded this frame |
| effectiveSpan | span used (0 when not run) |
| workload | W × H × effectiveSpan (0 when not run) |
| budgetSkipped | on and large enough, but no span fits the budget |

## Block (`CMPPixelSort`, 16 bytes)

`threshold: Float`, `span: UInt32`, `vertical: UInt32`, `pad: UInt32`; frame size from the textures.

## Storage

UserDefaults: `settings.pixelSort.enabled` (Bool), `.threshold` (Double), `.span` (Int), `.direction` (String).
Scene entry `fx.pixelSort`: `threshold` 0…1, `span` 4…64, `vertical` 0…1.
