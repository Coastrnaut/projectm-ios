# Contract: Layer transforms (CMP-005)

Extends `specs/029-cmp-001-unified-layer-protocol/contracts/layer-source.md`,
`specs/040-cmp-002-ordered-layer-stack/contracts/layer-stack.md` and
`specs/043-cmp-003-opacity-per-layer/contracts/layer-opacity.md`.

## Coordinates

- Layer coordinates: the layer's picture, normalized, (0, 0) top-left, (1, 1) bottom-right.
- Output coordinates: the output, normalized the same way.
- Aspect: output width ÷ height in pixels.

## Matrix (CMP-005-R2, research CMP-005-D1)

`M(aspect)` maps layer coordinates to output coordinates:

```
A = [[c·sx,        −s·sy ÷ a],
     [s·sx · a,     c·sy    ]]      c = cos θ, s = sin θ, a = aspect
b = anchor + translation − A·anchor
M = [[A00, A01, b.x], [A10, A11, b.y], [0, 0, 1]]
```

Equivalently: stretch x by the aspect (square units), move the anchor to the origin, scale (layer
axes), rotate (clockwise on screen for positive θ), move back, un-stretch, add the translation.
Guarantees: `M·anchor = anchor + translation`; `isIdentity ⇒ M == identity` exactly; pixel
lengths are preserved by rotation on any aspect.

## Compositor (CMP-005-R6 to R9, R11)

- `isSupportedByCompositor` = `blendMode == .normal`; any opacity, any transform.
- Per frame, each shown layer with `opacity > 0` is drawn:
  - `transform.isIdentity`: exactly as CMP-003 (`cmp_over`, per-pixel read).
  - otherwise: `cmp_over_transformed`: output pixel centre → layer pixel through `D·M⁻¹·D⁻¹`
    (`D = diag(W, H)`), bilinear sample, outside the picture = (0, 0, 0, 0), sanitized, × opacity,
    premultiplied "over".
- `apply`: a kept layer takes its entry's transform from the next frame; nothing is created,
  prepared or released for a transform-only change. No transform animation.
- Diagnostics: `transformedDraws` (draws through the transformed path in the last frame) and
  `shownTransform(ofLayer:)`.

## Saved form (CMP-005-R5, research CMP-005-D3)

```json
{"version":1,"translation":{"x":0,"y":0},"scale":{"x":1,"y":1},"rotation":0,"anchor":{"x":0.5,"y":0.5}}
```

| Key | Type | Unit | Default |
|---|---|---|---|
| `version` | integer | — | required, 1 |
| `translation.x`, `.y` | number | output fractions | 0 |
| `scale.x`, `.y` | number | factor | 1 |
| `rotation` | number | radians | 0 |
| `anchor.x`, `.y` | number | layer fractions | 0.5 |

Encoding writes every key. Decoding refuses another version and non-finite numbers, clamps
out-of-range values, and defaults missing keys. Encode → decode reproduces every value, and so
the matrix for any aspect, bit for bit.
