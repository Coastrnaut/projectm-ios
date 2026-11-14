# Data Model: CMP-007 Shape Masks

All live types are plain Swift in the `Compositor` target (build on Linux), `Sendable`, `Equatable`.

## LayerMaskShape

| Case | Payload | Rules |
|---|---|---|
| `ellipse` | none | Fills the local box −0.5…0.5; equal scales give a circle. |
| `rectangle(cornerRadius:)` | `Double` | Fills the box; radius a fraction of the rectangle's shorter side, clamped 0…0.5 (non-finite reads 0). |
| `polygon(_:)` | `[LayerPoint]` | 3…32 points in the local box frame; each coordinate clamped −10…10; non-zero area; even-odd fill. |

`kindName`: `ellipse`, `rectangle`, `polygon` (the saved names).

## LayerMaskTransform

| Field | Type | Default | Rule |
|---|---|---|---|
| `center` | `LayerPoint` | (0.5, 0.5) | Layer fractions; clamped −10…10; non-finite reads default. |
| `scale` | `LayerPoint` | (1, 1) | Units of the layer's shorter side; clamped 0.01…20; non-finite reads 1. |
| `rotation` | `Double` | 0 | Radians, clockwise on screen; non-finite reads 0; −0 stored as 0. |

## LayerMask

| Field | Type | Default | Rule |
|---|---|---|---|
| `shape` | `LayerMaskShape` | — | See above. |
| `transform` | `LayerMaskTransform` | identity | — |
| `feather` | `Double` | 0 | Fraction of the shorter side; clamped 0…1; non-finite reads 0. |
| `inverted` | `Bool` | false | — |

`init(...) throws(LayerMaskError)`: `.tooFewPoints(Int)`, `.tooManyPoints(Int)`, `.zeroArea`,
`.nonFinitePoint`. `maximumPolygonPoints = 32`.

## LayerMaskGeometry (CPU reference)

The mask resolved for a picture of W × H pixels: inverse placement (cos, sin, centre in pixels),
half extents, corner radius, polygon points in pixels, band width. `signedDistance(x:y:)` and
`coverage(x:y:)` take layer pixel coordinates (pixel centre = index + 0.5).

## Compositor state

`LayerCompositeSettings.mask: LayerMask?`. Each compositor record keeps `mask` (from the stack
entry at creation and every apply) and a cached shader block keyed by picture size.

## Scene document (SceneFormat)

`SceneComposite.mask: SceneMask?`; `SceneMask` = `.known(LayerMask)` | `.unknown(shape: String,
object: [String: SceneJSON])`. `SceneLiveState.preservedMasks: [LayerInstanceID: SceneMask]`.
New issue code `unsupportedMaskShape` (warning; repair report: values adjusted, no action).

## State transitions

Mask set or changed at `apply` → drawn from the next frame; nothing re-created. Output size change
→ block rebuilt for the new size on the next draw.
