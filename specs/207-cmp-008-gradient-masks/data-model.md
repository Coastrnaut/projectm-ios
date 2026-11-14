# Data Model: CMP-008 Gradient Masks

## LayerGradientStop (Compositor, plain Swift)

| Field | Type | Rule |
|---|---|---|
| position | Double | 0…1, clamped; non-finite reads 0 |
| alpha | Double | 0…1, clamped; non-finite reads 1 |

## LayerGradientKind

- `linear(start: LayerPoint, end: LayerPoint)`: layer fractions, each coordinate clamped −10…10;
  |end − start| ≥ 1e-6 or the mask is refused (`zeroLength`).
- `radial(center: LayerPoint, radius: Double)`: centre clamped −10…10; radius in units of the
  shorter side, clamped 0.01…20 (non-finite reads 0.5).
- Saved names: `linear`, `radial` (`kindNames`).

## LayerGradientMask

| Field | Type | Rule |
|---|---|---|
| kind | LayerGradientKind | as above |
| stops | [LayerGradientStop] | 2…8 (`tooFewStops`, `tooManyStops`), stable-sorted by position |

`alpha(at t: Double) -> Double`: research CMP-008-D1. `geometry(width:height:)` →
`LayerGradientGeometry`. Defaults for the editor: `linearDefault` (start (0, 0.5), end (1, 0.5)),
`radialDefault` (centre (0.5, 0.5), radius 0.5), both with stops (0, 1), (1, 0).

## LayerGradientGeometry (CPU reference, shader source)

kind (1 linear, 2 radial), axis (linear: sx, sy, ex, ey pixels; radial: cx, cy, r pixels), stops;
`parameter(x:y:)` (t), `alpha(x:y:)`.

## LayerCompositeSettings (extended)

`gradientMask: LayerGradientMask?` — nil draws without a gradient. Coverage = shape coverage (1 if no
shape) × gradient alpha (1 if no gradient).

## SceneGradientMask (SceneFormat)

`known(LayerGradientMask)` | `unknown(kind: String, object: [String: SceneJSON])`; `SceneComposite.gradientMask`
optional; `SceneLiveState.preservedGradientMasks: [LayerInstanceID: SceneGradientMask]` for unknown kinds.

## App: LayerGradientEdit rules

- kind: None / Linear / Radial (switching keeps the stops; a new gradient takes the defaults).
- angle (degrees, −180…180), radius (0.1…2 in the editor; files may hold 0.01…20).
- stop n: position, alpha; add (≤ 8, middle of the widest gap, alpha from `alpha(at:)`); remove (≥ 2).
