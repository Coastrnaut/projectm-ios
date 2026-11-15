# Contract: FX-015 Vignette

## C1 — Compositor

- `Compositor.vignette: Vignette` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `vignetteFrames: Int`, `holdsVignettePicture: Bool` (tests, diagnostics).
- The pass runs at the `.vignette` position of `outputEffectOrder` (appended last); a non-neutral Color listed before
  it is applied right before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference ≈ GPU)

For pixel (x, y) of a W × H frame: P = (x + ½, y + ½), C = (centerX·W, centerY·H), s = (2/W, 2/H) ÷ √2;
d = |(P − C) ⊙ s|; t = clamp((d − (1 − softness)) ÷ softness, 0, 1); w = t²(3 − 2t);
out.rgb = in.rgb × (1 − intensity·w); out.a = in.a.

Exact where w = 0 (the centre always); elsewhere within half-float rounding of the reference.

## C3 — Scene entry

`fx.vignette` with `intensity`, `softness`, `centerX`, `centerY` (FX-020 list); absent or disabled = default.

## C4 — App setting

`VignetteSetting` with the five keys; Settings → Vignette: `vignetteToggle`, sliders `vignetteIntensitySlider`,
`vignetteSoftnessSlider`, `vignetteCenterXSlider`, `vignetteCenterYSlider`; Effect order row
`effectChain.row.fx.vignette`.
