# Data Model: FX-014 Edge Outline

## EdgeOutline (Compositor, plain Swift)

| Field | Type | Range / default | Rule |
|-------|------|-----------------|------|
| isEnabled | Bool | false | off = no pass |
| threshold | Double | 0.02…1, 0.2 | NaN → default, else clamped |
| width | Int | 1…3, 1 | rounded, clamped |
| color | EdgeOutlineColor (r, g, b sRGB 0…1) | white | each clamped; hex "RRGGBB" in settings |
| mode | EdgeOutlineMode `overlay` / `outlineOnly` | overlay | unknown → overlay |

- `isActive(width:height:)`: on and frame ≥ 2 × 2.
- `limited(by: SafetyClamp)`: colour scale = intensity limit when it caps intensity, else 1.
- `Block` (shader `CMPEdgeOutline`, 32 bytes): `colour: SIMD4<Float>` (linear × scale, alpha 1), `threshold: Float`,
  `width: Int32`, `mode: UInt32`, `pad`; `last: SIMD2<UInt32>` is folded in as two UInt32 — see contract C2.

## Settings keys (app)

`settings.edgeOutline.enabled` (Bool), `.threshold` (Double), `.width` (Int), `.color` (String hex), `.mode` (String).

## Scene entry

`fx.edgeOutline`: `threshold` 0.02…1, `width` 1…3, `red`/`green`/`blue` 0…1, `mode` 0…1 (≥ 0.5 outline only).
