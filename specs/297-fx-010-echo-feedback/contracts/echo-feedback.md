# Contract: FX-010 Echo Feedback

## C1 Compositor

- `Compositor.echoFeedback: EchoFeedback` (default `.off`), set between frames. Inactive: no pass, no picture (all
  returned to the pool, fenced by the last command buffer), output bit-identical to before FX-010.
- Diagnostics: `echoFrames` (echo passes drawn), `echoStores` (capture passes), `echoAllocations` (pictures taken),
  `echoHistoryTextures: [MTLTexture]` (the ring, 0 or 4), `echoHistoryBytes` (Σ `allocatedSize`).
- Applied in `composite(into:)` and `encodeScene` at its position in `outputEffectOrder`, before the flash guard.

## C2 Pixel rule (GPU `cmp_echo` ≈ CPU `EchoFeedback.referencePixel`)

c = current pixel; if non-finite → c. Else e = Σ_{k<n} w_k × bilinear(history_k, (p + 0.5) ÷ size) with
n = min(count, valid, 4) (the shader's loop bound is `min(e.count, cmp_echo_cap)`, `cmp_echo_cap = 4`); out =
max(c, e) per channel. Weights: research D4. n = 0 → no pass.

## C3 Store rule (GPU `cmp_echo_capture` ≈ CPU `EchoFeedback.downsample`)

History pixel h: the mean of 4 sanitised bilinear samples of the input at (h + 0.5 ± 0.25) ÷ historySize. Written to
the oldest slot after the echo pass of a storing frame (research D3).

## C4 Memory

4 pictures at `historySize` while active; identities change only when `historySize` changes; total
`allocatedSize` ≤ 4 × the device's allocation size of one picture at that size, and the picture data ≤ 29,491,200
bytes at any output size. No per-frame allocation (the output picture is taken once per size like FX-007's).

## C5 Scene list

`fx.echo` entry (data-model). `SceneEffectSettings.echo: EchoFeedback?`; `isDefault` requires nil or disabled.

## C6 App

Settings → "Echo" (identifiers `echoToggle`, `echoCountSlider`, `echoDelaySlider`, `echoDecaySlider`, readouts
`…SliderValue`); Effect order row `effectChain.row.fx.echo`; section id `echo` for `-uitestSettingsSection`.
