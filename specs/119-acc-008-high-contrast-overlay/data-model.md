# Data Model: ACC-008 High Contrast Overlay

No stored data. Value types only.

## OverlayContrast (constants)

| Field | Value | Rule |
|---|---|---|
| `normalTextMinimum` | 4.5 | ACC-008-R1 |
| `largeTextMinimum` | 3.0 | ACC-008-R1 (large text, symbols) |
| `scrimOpacity` | measured (research D2) | lightest passing level, 0.01 steps |
| `increasedScrimOpacity` | 1.0 | ACC-008-R6 |
| `tintHex` | 0x409CFF | accent text and bordered buttons (D4) |
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

Validation: core pixel count ≥ 20 (the text was drawn); measured ≥ target.
