# Data Model: FX-008 Radial Blur

## RadialBlur (Compositor, plain Swift)

| Field | Type | Range | Default | Invalid |
|-------|------|-------|---------|---------|
| isEnabled | Bool | | false | |
| strength | Double | 0…0.25 | 0.1 | NaN → default; out of range → nearest bound |
| focusX | Double | 0…1 (0 = left) | 0.5 | NaN → default; out of range → nearest bound |
| focusY | Double | 0…1 (0 = top) | 0.5 | NaN → default; out of range → nearest bound |

Derived: `tapCount` = 16; `focusPixels(width:height:)` = (focusX·(w − 1), focusY·(h − 1));
`isActive(width:height:)` = on ∧ strength > 0 ∧ w ≥ 2 ∧ h ≥ 2; `block` = `CMPRadialBlur` (focus float2, last float2,
strength float, pad).

## Settings keys (app)

`settings.radialBlur.enabled`, `settings.radialBlur.strength`, `settings.radialBlur.focusX`,
`settings.radialBlur.focusY`: absent at defaults, written when changed, backed up and erased (FILE-005/011).

## Scene entry (SceneFormat, FX-020 `effects`)

`{"kind": "fx.radialBlur", "enabled": true, "parameters": {"strength": 0.1, "focusX": 0.5, "focusY": 0.5}}`, written
only while on; out-of-range or wrong-typed parameters are clamped or defaulted and reported.

## OutputEffectKind

`trails`, `grade`, `chromatic`, `radialBlur` (appended).
