# Data Model: FX-018 Scanline texture

## Scanlines (Compositor, plain Swift)

| Field | Type | Range | Default |
|-------|------|-------|---------|
| isEnabled | Bool | | false |
| spacing | Int | 2…16 pixels (step 1) | 3 |
| thickness | Int | 1…15 pixels (step 1); used as min(thickness, spacing − 1) | 1 |
| intensity | Double | 0…1 (step 0.01) | 0.5 |
| isVertical | Bool | | false (horizontal lines) |

NaN → default; ±Inf and out of range → nearest bound; spacing and thickness rounded to whole pixels. Active: on,
intensity > 0, frame ≥ 2 × 2. Line rule: index c (row, or column when vertical) is dark when c mod spacing < effective
thickness; factor 1 − intensity.

## Stored forms

- UserDefaults: `settings.scanlines.enabled` (Bool), `.spacing` (Int), `.thickness` (Int), `.intensity` (Double),
  `.vertical` (Bool). Written only when changed.
- Scene: `{"kind": "fx.scanlines", "enabled": true, "parameters": {"spacing", "thickness", "intensity", "vertical"}}`,
  written only while on.
