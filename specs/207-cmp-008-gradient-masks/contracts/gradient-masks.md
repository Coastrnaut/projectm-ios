# Contract: gradient masks (CMP-008)

## G1. Live model (`Compositor`, plain Swift)

```swift
public struct LayerGradientStop: Sendable, Equatable { position, alpha }          // clamped 0…1
public enum LayerGradientKind: Sendable, Equatable { case linear(start:end:), radial(center:radius:) }
public enum LayerGradientMaskError: Error { tooFewStops(Int), tooManyStops(Int), zeroLength }
public struct LayerGradientMask: Sendable, Equatable {
    static let maximumStops = 8, minimumStops = 2
    init(kind:stops:) throws(LayerGradientMaskError)   // clamps, stable-sorts
    func alpha(at t: Double) -> Double                 // research CMP-008-D1
    func geometry(width:height:) -> LayerGradientGeometry
}
LayerCompositeSettings.gradientMask: LayerGradientMask?
```

## G2. Compositor

- A layer with `mask` or `gradientMask` set is drawn with coverage = shape coverage × gradient alpha,
  evaluated at the layer pixel; no extra pass for normal mode (`maskedDraws` counts it); blend modes
  through `cmp_blend`. Layers with neither are drawn exactly as before.
- A change of either at `apply` shows from the next frame; the layer is not re-created.

## G3. Scene format (`composite.gradientMask`, optional, version 1)

```json
{"kind": "linear", "start": {"x": 0, "y": 0.5}, "end": {"x": 1, "y": 0.5},
 "stops": [{"position": 0, "alpha": 1}, {"position": 1, "alpha": 0}]}
{"kind": "radial", "center": {"x": 0.5, "y": 0.5}, "radius": 0.5, "stops": [...]}
```

| Input | Result |
|---|---|
| Field absent | no gradient; nothing written |
| Known kind, all fields | round-trips byte for byte |
| Missing `start`/`end`/`center`/`radius` | defaults (linear (0, 0.5)→(1, 0.5); radial centre, 0.5) |
| `stops` missing, < 2 or > 8 | gradient dropped, `droppedField` (counted before decoding stops) |
| Value out of range | clamped, `valueClamped` |
| Stops out of order | stable-sorted, `valueClamped` |
| Zero-length linear | gradient dropped, `droppedField` |
| Unknown key of a known kind (also inside a stop) | dropped, `droppedField` |
| Unknown `kind` | object kept verbatim; validation `unsupportedMaskShape` at `…gradientMask.kind`; not drawn |
| `kind` missing or not a string | `malformed` error (as a mask without `shape`) |

Load maps a known gradient to `LayerCompositeSettings.gradientMask`; an unknown one is kept in
`SceneLiveState.preservedGradientMasks` and written back by capture while the live gradient is nil.

## G4. Inspector (app)

Section "Gradient" after "Mask": `layerControl.gradientKind` picker (None, Linear, Radial),
`layerControl.gradientAngle` or `layerControl.gradientRadius` slider, per stop n (1-based):
`layerControl.gradientStop<n>.position`, `layerControl.gradientStop<n>.alpha` (ACC-005),
`layerGradientRemoveStop<n>`; `layerGradientAddStop`. Help for kind, angle, radius, stops. Undo label
"<Layer> Gradient …"; slider keys `layer.<kind>.gradient…`. Read-only rows show the values only.
