# Contract: Shape masks (CMP-007)

## Swift API (target `Compositor`, plain Swift)

```swift
public enum LayerMaskShape: Sendable, Equatable { case ellipse; case rectangle(cornerRadius: Double); case polygon([LayerPoint]) }
public struct LayerMaskTransform: Sendable, Equatable { center, scale: LayerPoint; rotation: Double; static let identity }
public struct LayerMask: Sendable, Equatable {
    public static let maximumPolygonPoints = 32
    public init(shape:transform:feather:inverted:) throws(LayerMaskError)
    public func geometry(width: Int, height: Int) -> LayerMaskGeometry
}
public struct LayerMaskGeometry { func signedDistance(x:y:) -> Double; func coverage(x:y:) -> Double; let band: Double }
LayerCompositeSettings.mask: LayerMask?   // nil: unmasked
```

## Drawing rules

- M1. Space: layer pixels of the layer's output-sized picture, before the CMP-005 transform. For a
  transformed layer the mask is evaluated at the inverse-mapped position, so it moves with the layer.
  For a CMP-006-fitted photo or video the mask cuts the layer rectangle.
- M2. Units: centre in layer fractions; scale, feather and polygon points in units of the shorter
  side S = min(W, H); corner radius a fraction of the rectangle's shorter side; rotation clockwise.
- M3. Band w = feather·S + 1 px. t = clamp((w/2 − d)/w, 0, 1), coverage = t²(3 − 2t); inverted:
  1 − coverage. d ≥ w/2 ⇒ coverage exactly 0; d ≤ −w/2 ⇒ exactly 1.
- M4. The premultiplied layer colour and alpha (after sanitizing and × opacity) are × coverage,
  then blended as the layer's blend mode says (normal: fixed-function "over" in the open pass; other
  modes: `cmp_blend`'s pass, as CMP-004).
- M5. No mask: the existing pipelines and bytes, bit-identical. A mask change at `apply` shows from
  the next frame; nothing is re-created.
- M6. Polygons: 3…32 points, non-zero area, even-odd. Ellipse distance is exact for circles and an
  estimate (exact sign) for ellipses.

## Saved form (SCN-001, optional, version 1)

```json
"composite": { "...": "...",
  "mask": { "shape": "polygon",
            "points": [{"x": -0.5, "y": -0.5}, {"x": 0.5, "y": -0.5}, {"x": 0, "y": 0.5}],
            "feather": 0.02, "inverted": false,
            "transform": {"center": {"x": 0.5, "y": 0.5}, "scale": {"x": 1, "y": 1}, "rotation": 0} } }
```

- S1. `shape` required (string). `cornerRadius` only for `rectangle`, `points` only for `polygon`
  (required there). `feather`, `inverted`, `transform` and its parts optional (defaults).
- S2. Encode writes every field of a known shape, and only when the layer has a mask.
- S3. Out-of-range numbers are clamped with `valueClamped`; unknown keys of a known shape are dropped
  with `droppedField`; a polygon with < 3 or > 32 points or zero area drops the mask with
  `droppedField` (reason in the message).
- S4. An unknown `shape` keeps the whole object verbatim; validation warns `unsupportedMaskShape`
  (SCN-012: values adjusted, a note); the layer is drawn unmasked; capture writes it back while the
  live mask is nil.
