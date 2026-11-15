# Research: FX-012 Mosaic Pixelation

All decisions by Claude under owner rule 4 (best judgement); 2026-11-15.

## FX-012-D1: Own pass, the FX-006/FX-008 pattern

- **Decision**: `MosaicPass` with `cmp_mosaic`, one pooled `rgba16Float` picture taken on the first active frame and
  returned when inactive, at a size change and with the compositor; the source is spliced after
  `RadialBlurPass.source` at the existing compile site and listed in `CompositorShaderSources.archived`.
- **Rationale**: a mosaic reads other pixels, so it cannot live in the per-pixel output pass; three effects proved the
  pattern.
- **Alternatives**: a compute kernel (a second pipeline kind for no gain); mip-map downsampling (averages, needs
  mip storage, only power-of-two sizes).

## FX-012-D2: One exact centre read per pixel

- **Decision**: a cell shows its centre pixel, fetched with `texture.read` (integer coordinates, no filter).
- **Rationale**: one read per pixel whatever the size (constant cost); every output value is an input value, so the
  GPU equals the CPU reference bit for bit; the classic pixelation look.
- **Alternatives**: averaging a fixed grid of taps (smoother on noise, but costs k reads and is only approximately
  reproducible); the top-left pixel (shifts the picture by half a block).

## FX-012-D3: Square grid anchored at the top-left

- **Decision**: block (⌊x/N⌋, ⌊y/N⌋), centre pixel (bx·N + ⌊N/2⌋, by·N + ⌊N/2⌋) clamped to the frame.
- **Rationale**: integer maths, no rounding ambiguity; easy to check ("every 8 × 8 block from the corner"). The
  partial last column/row takes the nearest pixel inside the frame.
- **Alternatives**: a grid centred on the frame (symmetric edges, but both edges then carry partial blocks and the
  maths needs an offset per size).

## FX-012-D4: Pointy-top hexagons, spacing N

- **Decision**: cell centres at (N·(q + r/2), (√3/2)·N·r) for integer axial (q, r); a pixel centre (x + ½, y + ½)
  maps to r_f = 2y′ ÷ (√3·N), q_f = x′ ÷ N − r_f ÷ 2, then cube rounding (the component with the largest rounding
  error is recomputed from the other two). The colour is the pixel containing the centre, ⌊centre⌋, clamped.
- **Rationale**: the standard nearest-centre hex assignment; spacing N matches the square size in a row; the same
  float formula in Swift and MSL agrees away from cell borders (ties at borders may round differently, which the tests
  allow).
- **Alternatives**: flat-top (columns instead of rows; equivalent, rows read more naturally on a landscape picture);
  rectangular brick offsets (not hexagonal).

## FX-012-D5: Bypass at size 1 and range

- **Decision**: block size 1…64 whole pixels, default 8; active = on ∧ size ≥ 2 ∧ frame ≥ 2 × 2. Size 1 runs no pass.
- **Rationale**: the acceptance "block size one equals original frame" holds bit for bit by construction; 64 keeps
  the picture readable (≈ 18 blocks across a phone picture).
- **Alternatives**: running the shader at size 1 (also exact for squares, but costs a pass for nothing).

## FX-012-D6: Chain position and storage

- **Decision**: kind `fx.mosaic`, appended after `fx.radialBlur`, and after FX-010's `fx.echo` since the merge (stored orders without it read with it last); scene
  entry parameters `size` (1…64, rounded) and `shape` (0 square, 1 hexagon; ≥ 0.5 hexagon); settings keys
  `settings.mosaic.enabled`, `settings.mosaic.size` (integer), `settings.mosaic.shape` (`square`/`hexagon`).
- **Rationale**: the FX-020 rules; appending keeps older orders, scenes and presets valid.
