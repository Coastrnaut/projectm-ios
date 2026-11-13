# Data Model: CMP-005 Transform Controls

All types are in target `Compositor`, CPU (build on Linux), `Sendable` and `Equatable`.

## LayerPoint

| Field | Type | Meaning |
|---|---|---|
| `x` | Double | horizontal component |
| `y` | Double | vertical component (down) |

`Codable` as `{"x": …, "y": …}`.

## LayerTransform (replaces the CMP-001 placeholder of six pixel numbers)

| Field | Type | Unit | Default | Range (finite values clamped) |
|---|---|---|---|---|
| `translation` | LayerPoint | fractions of the output's width (x) and height (y) | (0, 0) | −10…10 per component |
| `scale` | LayerPoint | factor per layer axis | (1, 1) | 0.05…20 per component |
| `rotation` | Double | radians; positive turns clockwise on screen | 0 | any finite |
| `anchor` | LayerPoint | fractions of the layer's picture; (0.5, 0.5) = centre | (0.5, 0.5) | −10…10 per component |

- `init(translation:scale:rotation:anchor:) throws(LayerTransformError)` — refuses any non-finite
  component, clamps the rest. `init(... uniformScale:)` convenience.
- `static let identity` — all defaults. `isIdentity` — move 0, scale 1, rotation 0 (any anchor).
- `matrix(aspect:) -> LayerTransformMatrix` — normalized layer → normalized output for output
  `width ÷ height` (aspect must be finite and > 0; otherwise 1 is used).
- `matrix(outputWidth:outputHeight:)` — convenience.
- Equality compares the four fields (so two identities with different anchors are unequal; use
  `isIdentity` for "draws as identity").

## LayerTransformMatrix

A 3 × 3 affine matrix, last row (0, 0, 1):

| Field | Meaning |
|---|---|
| `m00, m01, m02` | first row: x' = m00·x + m01·y + m02 |
| `m10, m11, m12` | second row: y' = m10·x + m11·y + m12 |

- `rows: [[Double]]` (3 × 3, for tests and diagnostics), `static let identity`,
  `apply(_: LayerPoint) -> LayerPoint`, `*` (composition: `(A * B).apply(p) == A.apply(B.apply(p))`),
  `inverse: LayerTransformMatrix?` (nil when the determinant is 0 or not finite).

## LayerTransformError

`nonFiniteTranslation`, `nonFiniteScale`, `nonFiniteRotation`, `nonFiniteAnchor`.

## Saved form (version 1)

```json
{"version":1,"translation":{"x":0.125,"y":-0.25},"scale":{"x":1.5,"y":0.75},"rotation":0.3,"anchor":{"x":0.2,"y":0.8}}
```

Decoding: `version` required and equal to 1; other fields optional (identity defaults);
non-finite refused, out-of-range clamped.

## Relationships

`LayerCompositeSettings.transform: LayerTransform` (default `.identity`) inside each
`LayerStackEntry`; the compositor keeps a copy per layer record. `isSupportedByCMP001` requires
`transform.isIdentity`; `isSupportedByCompositor` requires only `blendMode == .normal`.
