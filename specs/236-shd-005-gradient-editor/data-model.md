# Data Model: SHD-005 Gradient Editor

## GradientRampStop (VisualGenerators)
| Field | Type | Rule |
|---|---|---|
| position | Float | 0…1, clamped; non-finite → 0 |
| red, green, blue | UInt8 | sRGB-encoded |
| alpha | Float | 0…1, clamped; non-finite → 1 |

## GradientInterpolation
`smooth` (linear light, default) · `srgb` · `step`. Stored names: absent, `"srgb"`, `"step"`.

## GradientRamp
| Field | Rule |
|---|---|
| stops | 2…8 (fewer → refused by `init?`), stable-sorted by position |
| interpolation | GradientInterpolation |
| `color(at:)` | straight linear RGBA per SHD-005-R2 |
| `shaderStops` | per stop: linear RGBA, encoded RGB + position |

## ColorPalette stop detail (SceneFormat)
| Field | File key | Default (not written) | Valid |
|---|---|---|---|
| positions: [Int]? | `positions` | even spacing | count = colours, each 0…1000, non-decreasing |
| alphas: [Int]? | `alphas` | all 255 | count = colours, each 0…255 |
| interpolation | `interpolation` | smooth | `"srgb"`, `"step"` |

Derived: `stopPositions` (thousandths, even spacing = round(1000·i/(n−1))), `stopAlphas`, `hasStopDetail`.

## Operations (PaletteLibrary, user palettes only)
- `setStopPosition(id, index, thousandths)`: clamped to [previous, next] (0 and 1000 at the ends).
- `setStopAlpha(id, index, value)`: clamped 0…255.
- `setInterpolation(id, mode)`.
- `addColor`: appends position 1000 and the last alpha when detail exists.
- `removeColor`: removes the same index from detail.
