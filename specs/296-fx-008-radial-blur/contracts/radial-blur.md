# Contract: FX-008 Radial Blur

## C1 — Compositor

- `Compositor.radialBlur: RadialBlur` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `radialBlurFrames: Int`, `holdsRadialBlurPicture: Bool` (tests, diagnostics).
- The pass runs at the `.radialBlur` position of `outputEffectOrder`; a non-neutral Color listed before it is applied
  right before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference = GPU)

For pixel P (integer coordinates), focus F = focusPixels, s = strength:

- own non-finite, or P = F (spread 0) → own value;
- else out = (1/16) Σ_{k=0}^{15} bilinear(clamp(F + (P − F) ÷ (1 + s·k/15))), positions clamped to [0, w−1]×[0, h−1].

GPU within 1/128 per channel of the reference (hardware filter weights).

## C3 — Scene entry

`fx.radialBlur` with `strength`, `focusX`, `focusY` (FX-020 list); absent or disabled = default.

## C4 — App setting

`RadialBlurSetting` with the four keys; Settings → Radial blur: `radialBlurToggle`, sliders
`radialBlurStrengthSlider` ("10%"), `radialBlurFocusXSlider`, `radialBlurFocusYSlider` ("50%"); Effect order row
`effectChain.row.fx.radialBlur`.
