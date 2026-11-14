# Contract: Aspect fitting (CMP-006)

## Modes (CMP-006-R1, R3, R4)

With content Wc × Hc pixels, output Wo × Ho pixels, anchor (ax, ay) in 0…1 and k output pixels per
content pixel (pixelAccurate; default 1):

| Mode | Scale x | Scale y | Offset |
|---|---|---|---|
| fill | max(Wo/Wc, Ho/Hc) | same | a·(1 − visible) |
| fit | min(Wo/Wc, Ho/Hc) | same | a·(1 − visible) |
| stretch | Wo/Wc | Ho/Hc | 0 (anchor ignored) |
| pixelAccurate | k | k | from the origin round(a·(Wo − Wc·k)) in output pixels: −origin ÷ (Wc·k) |

`visible = Wo ÷ (Wc·scale x)` and `Ho ÷ (Hc·scale y)`. Output point p (0…1, top-left) shows content
coordinate `offset + p·visible`; outside 0…1 the layer is transparent. Any size ≤ 0: identity.

## Guarantees (CMP-006-R5, R6, S1, S2)

- fill: visible ≤ 1 on both axes (covers the output); fit: visible ≥ 1 on both axes (all content
  shown); stretch: visible = 1; pixelAccurate: one content pixel = k output pixels on both axes.
- Pixel aspect = 1 in every mode except stretch.
- The anchor's content point lands on the same output fraction at every output size (pixelAccurate:
  within half an output pixel).
- Applied inside the layer picture; the CMP-005 transform, CMP-003 opacity and CMP-004 blend mode
  then apply to the picture as for any layer (CMP-006-R8).

## Layers (CMP-006-R7, R11)

| Layer | Fit | No fit set |
|---|---|---|
| photo (`ImageLayerSource`) | all four | its init `mode` (default fill), centre |
| video (`VideoLayerSource`) | all four, on the upright size | fill, centre |
| camera | not yet (CAM-007; follow-up in the spec) | unchanged |
| text, spectra, materials, graphs, projectM | ignored (drawn at output resolution) | unchanged |

A fit change at `Compositor.apply` is shown from the next frame; nothing is reloaded or rebuilt.

## Saved form (CMP-006-R9, R10)

```json
"composite": {"opacity": 1, "blend": "normal", "transform": {…},
              "fit": {"mode": "pixelAccurate", "anchor": {"x": 0.5, "y": 0}}}
```

- `fit` optional; absent = no fit set; written only when set (scenes without it are byte-identical).
- `mode` required inside `fit`; one of the four names is drawn; any other string is kept through
  decode, encode, load and capture, warned as `unsupportedFitMode` (repair report: note) and drawn
  as the layer's default.
- `anchor` optional (centre); components clamped to 0…1 (`valueClamped`); other keys dropped
  (`droppedField`).
- Format version stays 1.
