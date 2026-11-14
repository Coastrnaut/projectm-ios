# Data Model: CMP-009 Luma Key

## LayerLumaKey (Compositor, plain Swift)

| Field | Type | Range / rule |
|---|---|---|
| low | Double | 0…1 (non-finite reads 0); low ≤ high (a reversed pair is swapped) |
| high | Double | 0…1 (non-finite reads 0.1) |
| softness | Double | 0…0.5 (non-finite reads 0) |
| inverted | Bool | false: key the range out; true: keep only the range |

- `blackKey` = (0, 0.1, 0.05, false): the inspector's default.
- `luma(red:green:blue:alpha:)` from premultiplied linear colour; `keep(luma:)`; `keep(red:green:blue:alpha:)`.

## LayerCompositeSettings (Compositor)

- `lumaKey: LayerLumaKey?` (nil: no key).

## SceneComposite (SceneFormat)

- `lumaKey: LayerLumaKey?`, saved as `composite.lumaKey` only when set (contract L1).

## Inspector parameters (app)

- `lumaKey` (toggle), `lumaLow`, `lumaHigh`, `lumaSoftness` (sliders), `lumaInverted` (toggle).
