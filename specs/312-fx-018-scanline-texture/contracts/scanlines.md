# Contract: FX-018 Scanline texture

## C1 — Compositor

- `Compositor.scanlines: Scanlines` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `scanlinesFrames: Int`, `holdsScanlinesPicture: Bool` (tests, diagnostics).
- The pass runs at the `.scanlines` position of `outputEffectOrder` (appended after Vignette); a non-neutral Color
  listed before it is applied right before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference = GPU)

For pixel (x, y) of a W × H frame: c = y (x when vertical); p = spacing; t = min(thickness, p − 1); f = 1 − intensity
(one `Float`). If c mod p < t: out.rgb = in.rgb × f, out.a = in.a; otherwise out = in bit for bit. Row (column) 0 is
always dark. Measured pitch (first row of a dark band to the first row of the next) = p for every pair of bands.

## C3 — Scene entry

`fx.scanlines` with `spacing`, `thickness`, `intensity`, `vertical` (FX-020 list); absent or disabled = default.

## C4 — App setting

`ScanlinesSetting` with the five keys; Settings → Scanlines: `scanlinesToggle`, sliders `scanlinesSpacingSlider`,
`scanlinesThicknessSlider`, `scanlinesIntensitySlider`, picker `scanlinesOrientationPicker`; Effect order row
`effectChain.row.fx.scanlines`.
