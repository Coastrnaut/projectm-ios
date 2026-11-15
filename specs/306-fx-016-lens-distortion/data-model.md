# Data Model: FX-016 Lens Distortion

## LensDistortion (Compositor, plain Swift)

| Field | Type | Range / default | Rule |
|-------|------|-----------------|------|
| isEnabled | Bool | false | off = no pass |
| strength | Double | −1…1, 0.3 | NaN → default, else clamped; > 0 barrel, < 0 pincushion |
| zoomToFill | Bool | true | only changes strength > 0 |

- `coefficient` k = 0.3 × clamped strength (`maxCoefficient` = 0.3).
- `isActive(width:height:)`: on, k ≠ 0 and frame ≥ 2 × 2.
- `Block` (shader `CMPLensDistortion`, 32 bytes, `setFragmentBytes`): `centre: SIMD2<Float>` (W ÷ 2, H ÷ 2),
  `size: SIMD2<Float>` (W, H), `inverseRadiusSquared: Float` (4 ÷ (W² + H²)), `coefficient: Float` (k, 0 when off),
  `inverseZoom: Float` (1 ÷ (1 + k) when zoom and k > 0, else 1), `pad: Float`.

## Settings keys (app)

`settings.lensDistortion.enabled` (Bool), `.strength` (Double), `.zoomToFill` (Bool).

## Scene entry

`fx.lensDistortion`: `strength` −1…1, `zoomToFill` 0…1 (≥ 0.5 on).
