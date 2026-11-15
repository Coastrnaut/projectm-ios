# Contract: FX-006 Chromatic Split

## C1 Compositor

- `Compositor.chromaticSplit: ChromaticSplit` (default `.off`), set between frames. Inactive: no pass, no picture
  (returned to the pool, fenced by the last command buffer), output bit-identical to before FX-006.
- `Compositor.chromaticFrames: Int`, `holdsChromaticPicture: Bool` (tests, diagnostics).
- Applied in `composite(into:)` and `encodeScene` at its position in `outputEffectOrder`, before the flash guard and
  the tone map.

## C2 Pixel rule (GPU `cmp_chromatic` = CPU `ChromaticSplit.referencePixel`)

For pixel p in a w × h frame: v' = fade(p) × v(p) (research D2, D3); if v' = 0 or the own value is non-finite the
output is the own value; else R = bilinear(p − v').r, B = bilinear(p + v').b, G = own.g,
A = max(own.a, bilinear(p − v').a, bilinear(p + v').a). Bilinear clamps every texel index to the frame.

## C3 Scene list

`fx.chromatic` entry (data-model). `SceneEffectSettings.chromatic: ChromaticSplit?`; `isDefault` requires it nil
or disabled.

## C4 App

Settings → "Chromatic split" (identifiers `chromaticToggle`, `chromaticAmountSlider`, `chromaticAngleSlider`,
`chromaticRadialToggle`, readout `chromaticAmountSliderValue`); Effect order row `effectChain.row.fx.chromatic`.
