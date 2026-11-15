# Data Model: FX-007 Directional Blur

## DirectionalBlur (Compositor, plain Swift)

| Field | Type | Range / default | Notes |
|-------|------|-----------------|-------|
| isEnabled | Bool | false | |
| radius | Double | 0…0.02, 0.005 | fraction of the shorter side, each side of the pixel; NaN → default, clamp |
| angleDegrees | Double | 0…180, 0 | folds mod 180; 0° = horizontal, 90° = vertical |

Derived: `radiusPixels(width:height:)`, `isActive(width:height:)` (enabled and radiusPixels > 0), `tapCount` (16),
`unitOffsets` (u_i), `weights` (sum 1), `taps(width:height:)` (offset vectors in pixels), `samplePosition` (clamped),
`reference(pixels:width:height:)`.

## OutputEffectKind

`trails`, `grade`, `chromatic` (FX-006), `directionalBlur` (`fx.directionalBlur`, new). Standard order: trails,
grade, chromatic, directionalBlur.

## Scene `effects` entry

`{"kind": "fx.directionalBlur", "enabled": Bool, "parameters": {"radius": 0…0.02, "angle": 0…180}}`; missing →
default, non-number → default (`valueClamped`), out of range → clamped (`valueClamped`).

## App setting keys

`settings.directionalBlur.enabled` (Bool), `settings.directionalBlur.radius` (Double),
`settings.directionalBlur.angle` (Double). Absent → defaults; included in backups and erase.
