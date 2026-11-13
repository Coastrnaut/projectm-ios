# Data Model: VIS-002 Linear Spectrum

## LinearSpectrumConfiguration (value, Sendable)

| Field | Type | Range (clamped) | Default |
|---|---|---|---|
| barCount | `SpectrumBarCount` | 16, 32, 64, 128 | 64 |
| orientation | `LinearSpectrumOrientation` | `.vertical`, `.horizontal` | `.vertical` |
| spacing | Double | 0…0.9 of a slot | 0.2 |
| capThickness (t) | Double | 0…0.05 of L | 0.015 |
| lengthScale (λ) | Double | 0…(1 − t) of L | 0.9 |
| peakHoldSeconds | Double | 0…5 | 0.5 |
| peakFallPerSecond | Double | 0.1…10 bar lengths per second | 1.0 |
| palette | `VisualPalette` | spectrum, ice, mono | spectrum |
| background | `LinearColor` (premultiplied, linear) | components 0…1 | opaque black |

Non-finite values take their defaults. `LinearSpectrumOrientation` has raw values `vertical` and
`horizontal` (the stored setting).

## LinearBarGeometry (value, per bar)

Pixels, y down; C = cross-axis size, L = length-axis size; p = C/N.

| Field | Rule |
|---|---|
| crossStart, crossEnd | k·p + s·p/2, crossStart + (1 − s)·p |
| length | v·λ·L (v sanitized, VIS-001-R8) |
| capStart, capEnd | P·λ·L, capStart + t·L (P = peak; empty when P = 0) |
| color | palette.color(bar: k, of: N) |

Mapping to the output: vertical x = cross, y = H − length; horizontal x = length, y = cross.

## PeakCapTracker (state, per bar; preallocated for 128)

| Field | Meaning |
|---|---|
| peak | 0…1 |
| holdRemaining | seconds, ≥ 0 |

Transition per frame with clamped frame time dt and displayed value v:
1. v ≥ peak → peak = v, holdRemaining = hold.
2. else: h = min(holdRemaining, dt); holdRemaining −= h; peak = max(v, peak − fall·(dt − h)).
`reset()` zeroes every bar.

## Settings (UserDefaults, user settings)

| Key | Values | Fallback |
|---|---|---|
| `settings.visual` | adds `linearSpectrum` | unknown → projectM |
| `settings.linearSpectrum.orientation` | `vertical`, `horizontal` | vertical |
| `settings.linearSpectrum.spacing` | 0, 0.2, 0.5 | 0.2 |
