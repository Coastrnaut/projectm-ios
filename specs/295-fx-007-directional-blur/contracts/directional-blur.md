# Contract: FX-007 Directional Blur

## C1 Compositor

- `Compositor.directionalBlur: DirectionalBlur` (default `.off`), set between frames. Inactive: no pass, no picture
  (returned to the pool, fenced by the last command buffer), output bit-identical to before FX-007.
- `Compositor.directionalBlurFrames: Int`, `holdsDirectionalBlurPicture: Bool` (tests, diagnostics).
- Applied in `composite(into:)` and `encodeScene` at its position in `outputEffectOrder`, before the flash guard and
  the tone map.

## C2 Pixel rule (GPU `cmp_directional_blur` ≈ CPU `DirectionalBlur.referencePixel`)

For pixel p (index space) in a w × h frame: if the own value is non-finite, output it. Else for i in 0…15:
q_i = clamp(p + u_i × radiusPx × d, [0, w−1] × [0, h−1]); s_i = bilinear(q_i); the output is Σ w_i s_i over finite
s_i divided by Σ w_i over finite s_i (no finite sample → own value). Exactly 16 samples, weights fixed (research D2).
The GPU uses hardware linear filtering, so it matches the CPU within filtering precision (≤ 1/256 per channel on
values in 0…1). Non-finite handling is tested on the CPU reference only: hardware filtering may
turn a weight-0 non-finite neighbour into a non-finite sample, which the skip rule then drops (both never spread).

## C3 Scene list

`fx.directionalBlur` entry (data-model). `SceneEffectSettings.directionalBlur: DirectionalBlur?`; `isDefault`
requires it nil or disabled.

## C4 App

Settings → "Directional blur" (identifiers `directionalBlurToggle`, `directionalBlurRadiusSlider`,
`directionalBlurAngleSlider`, readouts `…SliderValue`); Effect order row `effectChain.row.fx.directionalBlur`;
section id `directionalBlur` for `-uitestSettingsSection`.
