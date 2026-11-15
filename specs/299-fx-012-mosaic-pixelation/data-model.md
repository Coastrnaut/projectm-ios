# Data Model: FX-012 Mosaic Pixelation

## Mosaic (Compositor, plain Swift)

| Field | Type | Range | Default | Invalid |
|-------|------|-------|---------|---------|
| isEnabled | Bool | | false | |
| blockSize | Int | 1…64 | 8 | out of range → nearest bound (Double: NaN → default, rounded) |
| shape | MosaicShape | square, hexagon | square | unknown → square |

Derived: `isActive(width:height:)` = on ∧ blockSize ≥ 2 ∧ w ≥ 2 ∧ h ≥ 2; `squareCell(x:y:)`, `hexCell(x:y:)` (axial
q, r), `samplePixel(x:y:width:height:)` (the cell's centre pixel, clamped); `block` = `CMPMosaic` (size float, shape
uint, last uint2).

## Settings keys (app)

`settings.mosaic.enabled` (Bool), `settings.mosaic.size` (Int), `settings.mosaic.shape` (String): absent at defaults,
written when changed, backed up and erased (FILE-005/011).

## Scene entry (SceneFormat, FX-020 `effects`)

`{"kind": "fx.mosaic", "enabled": true, "parameters": {"size": 8, "shape": 0}}`, written only while on; out-of-range or
wrong-typed parameters are clamped or defaulted and reported.

## OutputEffectKind

`trails`, `grade`, `chromatic`, `directionalBlur`, `radialBlur`, `mosaic` (appended).
