# Data Model: CMP-010 Color Key

## LayerColorKey (Compositor, plain Swift)

| Field | Type | Range / rule |
|---|---|---|
| red, green, blue | Double | the key colour as displayed sRGB, each 0…1 (non-finite reads green's default 0, 1, 0) |
| tolerance | Double | 0…1 (non-finite reads 0.2): chroma distance keyed fully |
| feather | Double | 0…0.5 (non-finite reads 0.1): width of the linear ramp beyond the tolerance |

- `greenKey` = (0, 1, 0, 0.2, 0.1): the inspector's default.
- `chroma(red:green:blue:alpha:)` from premultiplied linear colour → (cb, cr); `keyChroma` of the key
  colour; `distance(red:green:blue:alpha:)`; `keep(distance:)`; `keep(red:green:blue:alpha:)`.
- −0 is stored as 0 for every field.

## LayerCompositeSettings (Compositor)

- `colorKey: LayerColorKey?` (nil: no key).

## SceneComposite (SceneFormat)

- `colorKey: LayerColorKey?`, saved as `composite.colorKey` only when set (contract C3).

## Inspector parameters (app)

- `colorKey` (toggle), `colorKeyColor` (colour picker), `colorTolerance`, `colorFeather` (sliders).
