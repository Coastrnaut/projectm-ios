# Contract: FX-012 Mosaic Pixelation

## C1 — Compositor

- `Compositor.mosaic: Mosaic` (default `.off`), set between frames. Inactive: no pass, no picture, output
  bit-identical. Turning it off returns the picture to the pool.
- `mosaicFrames: Int`, `holdsMosaicPicture: Bool` (tests, diagnostics).
- The pass runs at the `.mosaic` position of `outputEffectOrder`; a non-neutral Color listed before it is applied right
  before it; the flash guard and tone map come after.

## C2 — Pixel rule (CPU reference = GPU)

For pixel (x, y), N = blockSize, last = (w − 1, h − 1):

- square: c = (⌊x/N⌋·N + ⌊N/2⌋, ⌊y/N⌋·N + ⌊N/2⌋);
- hexagon: (q, r) = hexRound(r_f = 2(y + ½) ÷ (√3 N), q_f = (x + ½) ÷ N − r_f ÷ 2); c = ⌊(N(q + r/2), (√3/2)N·r)⌋;
- out = input(min(max(c, 0), last)), read exactly.

GPU equals the reference exactly for squares; for hexagons at every pixel whose four neighbours share its cell.

## C3 — Scene entry

`fx.mosaic` with `size`, `shape` (FX-020 list); absent or disabled = default.

## C4 — App setting

`MosaicSetting` with the three keys; Settings → Mosaic: `mosaicToggle`, slider `mosaicSizeSlider` ("8 px"), picker
`mosaicShapePicker` (Square, Hexagon); Effect order row `effectChain.row.fx.mosaic`.
