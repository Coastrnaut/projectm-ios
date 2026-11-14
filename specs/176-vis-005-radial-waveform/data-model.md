# Data Model: VIS-005 Radial Waveform

## RadialWaveformConfiguration (package, value type)

| Field | Type | Range / default | Notes |
|---|---|---|---|
| `baseRadius` | Double | 0.2…0.75, default 0.55 | R₀, fraction of half the shorter side; non-finite → default |
| `amplitude` | Double | 0…0.25, default 0.18 | A, same unit; non-finite → default |
| `lineThickness` | Double | 0.001…0.05, default 0.006 | fraction of the shorter side, at least 1 px drawn |
| `palette` | VisualPalette | `.spectrum` | ACC-003-R13 |
| `background` | LinearColor | opaque black | premultiplied, linear |

## Layout state (per frame, preallocated)

- Tapered normalized samples sᵢ (N = 1,024), radii, points (x, y), N rectangles and areas, N colors.
- `LissajousAutoGain` (level, time since rise); reset on loop restart.

## App settings

| Key | Values | Default / invalid |
|---|---|---|
| `settings.visual` | adds `radialWaveform` | — |
| `settings.radialWaveform.ring` | `small`/`medium`/`large` → R₀ 0.40/0.55/0.70 | medium |
| `settings.radialWaveform.amplitude` | `low`/`medium`/`high` → A 0.10/0.18/0.25 | medium |

`NativeSpectrumStyle.radialWaveform(ring:amplitude:)`; accessibility value "<Ring> ring, <Amplitude> amplitude, <glow>".
