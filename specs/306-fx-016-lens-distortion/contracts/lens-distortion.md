# Contract: FX-016 Lens Distortion

## C1 — Compositor

- `Compositor.lensDistortion: LensDistortion` (default `.off`), set between frames. Inactive: no pass, no picture,
  output bit-identical. Turning it off returns the picture to the pool.
- `lensDistortionFrames: Int`, `holdsLensDistortionPicture: Bool` (tests, diagnostics).
- The pass runs at the `.lensDistortion` position of `outputEffectOrder`; a non-neutral Color listed before it is
  applied right before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference = GPU)

For output pixel (x, y): p = (x + ½, y + ½); d = p − centre; r² = (d · d) × inverseRadiusSquared;
f = (1 + k r²) × inverseZoom; s = centre + d × f.

- Outside (s.x < 0, s.x > W, s.y < 0 or s.y > H, or s not finite): (0, 0, 0, 0).
- Inside: q = s − ½; (x0, y0) = ⌊q⌋; (fx, fy) = q − (x0, y0); taps (x0, y0), (x0 + 1, y0), (x0, y0 + 1), (x0 + 1, y0 + 1)
  each clamped to 0…W − 1 × 0…H − 1; fx = fy = 0 → input(clamped x0, y0) exactly; else
  mix(mix(t00, t10, fx), mix(t01, t11, fx), fy).
- At k = 0: f = 1 exactly, s = p, the result is input(x, y) bit for bit.

GPU and reference agree within half-float rounding; the inside/outside decision and the taps are the same.

## C3 — Scene entry

`fx.lensDistortion` with `strength`, `zoomToFill` (FX-020 list); absent or disabled = default.

## C4 — App setting

`LensDistortionSetting` with the three keys; Settings → Lens distortion: `lensDistortionToggle`, slider
`lensDistortionStrengthSlider` (readout `lensDistortionStrengthSliderValue`, "+30%"), toggle
`lensDistortionZoomToggle`; Effect order row `effectChain.row.fx.lensDistortion`.
