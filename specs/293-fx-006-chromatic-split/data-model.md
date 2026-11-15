# Data Model: FX-006 Chromatic Split

## ChromaticSplit (Compositor, plain Swift)

| Field | Type | Range / default | Notes |
|-------|------|-----------------|-------|
| isEnabled | Bool | false | |
| amount | Double | 0…0.02, 0.005 | fraction of the shorter side; NaN → default, clamp |
| angleDegrees | Double | 0…360, 0 | wraps; 0° = red moves right, 90° = red moves up |
| isRadial | Bool | false | angle ignored when on |

Derived: `amountPixels(width:height:)`, `isActive(width:height:)` (enabled and amountPixels > 0),
`vector(x:y:width:height:)` (after the edge fade), `sample positions` (clamped), `reference(pixels:width:height:)`.

## OutputEffectKind

`trails` (`fx.trails`), `grade` (`fx.grade`), `chromatic` (`fx.chromatic`, new). Standard order: trails, grade,
chromatic.

## Scene `effects` entry

`{"kind": "fx.chromatic", "enabled": Bool, "parameters": {"amount": 0…0.02, "angle": 0…360, "radial": 0|1}}`;
missing → default, non-number → default (`valueClamped`), out of range → clamped (`valueClamped`).

## App setting keys

`settings.chromatic.enabled` (Bool), `settings.chromatic.amount` (Double), `settings.chromatic.angle` (Double),
`settings.chromatic.radial` (Bool). Absent → defaults; included in backups and erase.
