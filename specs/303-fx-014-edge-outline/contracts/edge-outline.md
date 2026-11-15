# Contract: FX-014 Edge Outline

## C1 — Compositor

- `Compositor.edgeOutline: EdgeOutline` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `edgeOutlineFrames: Int`, `holdsEdgeOutlinePicture: Bool` (tests, diagnostics).
- The pass runs at the `.edgeOutline` position of `outputEffectOrder`; a non-neutral Color listed before it is applied
  right before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference = GPU)

For pixel p, w = width, last = (W − 1, H − 1), s(dx, dy) = Y(input(clamp(p + (dx·w, dy·w), 0, last))):

- Gx = (s(1,−1) + 2 s(1,0) + s(1,1)) − (s(−1,−1) + 2 s(−1,0) + s(−1,1));
- Gy = (s(−1,1) + 2 s(0,1) + s(1,1)) − (s(−1,−1) + 2 s(0,−1) + s(1,−1));
- E = √(Gx² + Gy²) ÷ 4; m = E finite ? smoothstep(t, t + 0.1, E) : 0;
- overlay: m = 0 → input(p) exactly, else mix(input(p), (c, 1), m); outline only: mix((0, 0, 0, 1), (c, 1), m).

GPU and reference agree on which pixels have m > 0 and, on exactly representable pictures, on every value.

## C3 — Scene entry

`fx.edgeOutline` with `threshold`, `width`, `red`, `green`, `blue`, `mode` (FX-020 list); absent or disabled = default.

## C4 — App setting

`EdgeOutlineSetting` with the five keys; Settings → Edge outline: `edgeOutlineToggle`, slider
`edgeOutlineThresholdSlider` ("0.20"), pickers `edgeOutlineWidthPicker` (1 px, 2 px, 3 px) and `edgeOutlineModePicker`
(Overlay, Outline only), colour well `edgeOutlineColor`; Effect order row `effectChain.row.fx.edgeOutline`.
