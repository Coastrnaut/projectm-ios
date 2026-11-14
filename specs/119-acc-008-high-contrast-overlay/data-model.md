# Data Model: ACC-008 High Contrast Overlay

No stored data. Value types only.

## OverlayContrast (constants)

| Field | Value | Rule |
|---|---|---|
| `normalTextMinimum` | 4.5 | ACC-008-R1 |
| `largeTextMinimum` | 3.0 | ACC-008-R1 (large text, symbols) |
| `scrimOpacity` | 0.84 | lightest passing level 0.83 (research D2) + one 0.01 step |
| `increasedScrimOpacity` | 1.0 | ACC-008-R6 |
| `tintHex` | 0xB8DCFF | accent text and bordered buttons (D4) |
| `criticalFill` | 0xC4161C | the camera badge's prominent Stop (D4) |
| `criticalText` | 0xFF9A94 | destructive text, e.g. Discard (D4) |
| `prominentTintHex` | 0x0062CC | prominent button fills (D4) |

`scrim(increasedContrast:)` → `increasedScrimOpacity` or `scrimOpacity`.

## OverlaySurface (view modifier)

Fields: `shape` (any insettable shape), `material` (default regular), `includesMaterial` (default true;
false only in fixtures). Reads `statusAppearance.increasedContrast`. Draws, back to front: material (if
included), black scrim at `scrim(…)`, content in the dark scheme with the overlay tint.

## Contrast fixture (tests only)

| Entity | Fields |
|---|---|
| `FixtureFrame` | white, black, gradient, noise |
| `TextStyleSpecimen` | element name, words, font, foreground (`primary`, `secondary`, `tint`, a palette colour, a button style), target (4.5 or 3.0) |
| `ContrastMeasurement` | element, style, frame, core pixel count, 5th-percentile ratio, median ratio |

Validation: core pixel count ≥ 20 (the text was drawn); measured ≥ target. Core pixels differ by ≥ 90% of
the full-coverage difference.
