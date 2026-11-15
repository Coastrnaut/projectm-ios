# ADR-0110: Mosaic Pixelation Is Its Own Output Pass, Sixth in the Effect Chain, Showing Each Cell's Centre Pixel

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-012 (`specs/299-fx-012-mosaic-pixelation`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0104 (FX-006's spatial-pass pattern; the standard order gains a sixth kind,
  `fx.mosaic`, after ADR-0106's directional blur and ADR-0107's radial blur), ADR-0054 (FX-020 effect chains),
  ADR-0024 (no new compile site), ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-012 asks to "reduce spatial resolution into square or hexagonal blocks", with the acceptance
"block size one equals original frame; larger sizes are visibly discrete". A mosaic reads other pixels, so like the
blurs it needs its own pass. FX-010 (echo feedback) is built in parallel and appends its own kind.

## Decision

1. **Own pass**: `MosaicPass` (`cmp_mosaic`) writes one pooled `rgba16Float` picture at composite size, only while the
   mosaic is active (on, block size ≥ 2, frame ≥ 2 × 2). Block size 1 or off: no pass, no picture, output
   bit-identical. The shader is a module constant spliced into the existing compile site in `Compositor.init` and
   listed in `CompositorShaderSources.archived`.
2. **Pixel rule**: each cell shows the pixel at its centre, read exactly (no filter, no averaging), clamped to the
   frame: one read per pixel whatever the size; every output value is an input value.
3. **Grids**: squares of N × N from the frame's top-left corner, centre pixel (bx·N + ⌊N/2⌋, by·N + ⌊N/2⌋);
   pointy-top hexagons with centre spacing N in a row and (√3/2)·N between rows, cell (0, 0) centred on the top-left
   corner, nearest centre by cube rounding (the same Float steps in Swift and MSL; ties at borders may round
   differently).
4. **Bounds**: block size 1…64 whole pixels of the composite, default 8; shape square (default) or hexagon. No ACC-012
   cap (copying adds no brightness); the flash guard measures the shown frame.
5. **Chain**: `OutputEffectKind.mosaic` is appended, so stored orders read with the mosaic last; a non-neutral Color
   listed before an active mosaic is folded into the grade pass right before it (FX-006's rule).
6. **Storage**: a global setting (`settings.mosaic.enabled`, `.size`, `.shape`); scenes and presets carry an
   `fx.mosaic` entry (`size`, `shape` 0/1); a disabled mosaic counts as default, so older scenes save
   byte-identically.

## Consequences

- One extra full-screen pass (one read per pixel) and one pooled picture while active; with the standard order and a
  non-neutral grade, the grade pass also runs.
- The block size is in composite pixels, so on a 3× screen 8 px is about 2.7 points; the 64 px cap keeps pictures
  readable.
- The device frame-rate check is FX-012-T18 `{device}`.
