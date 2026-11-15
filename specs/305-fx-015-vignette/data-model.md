# Data Model: FX-015 Vignette

## Vignette (Compositor, plain Swift)

| Field | Type | Range | Default |
|-------|------|-------|---------|
| isEnabled | Bool | | false |
| intensity | Double | 0…1 (step 0.01) | 0.5 |
| softness | Double | 0.1…0.9 (step 0.05) | 0.5 |
| centerX | Double | 0…1 (step 0.05) | 0.5 |
| centerY | Double | 0…1 (step 0.05) | 0.5 |

NaN → default; ±Inf and out of range → nearest bound. Active: on, intensity > 0, frame ≥ 2 × 2.

## Stored forms

- UserDefaults: `settings.vignette.enabled` (Bool), `settings.vignette.intensity`, `.softness`, `.centerX`, `.centerY`
  (Double). Written only when changed.
- Scene: `{"kind": "fx.vignette", "enabled": true, "parameters": {"intensity", "softness", "centerX", "centerY"}}`,
  written only while on.
