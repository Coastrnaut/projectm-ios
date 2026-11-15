# ADR-0104: The Chromatic Split Is Its Own Output Pass, Third in the Effect Chain, Faded to Zero at the Frame Border

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-006 (`specs/293-fx-006-chromatic-split`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0054 (FX-020: the reorderable output effects gain a third kind, `fx.chromatic`; the
  standard order becomes Trails → Color → Chromatic split; Color is folded into its pass before any active spatial
  effect that follows it, not only before Trails), ADR-0051 (Trails unchanged), ADR-0024 (no new compile site),
  ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-006 asks to "offset color channels with edge-aware controls", with the acceptance "zero offset is
exact pass-through and edges stay within frame bounds". The split samples neighbouring pixels, so it cannot live in
the per-pixel output pass (FX-003's grade, which FX-005 extends in parallel).

## Decision

1. **Own pass**: `ChromaticSplitPass` (`cmp_chromatic`) writes one pooled `rgba16Float` picture at composite size,
   only while the split is active (on, amount > 0, frame ≥ 3 × 3). Inactive: no pass, no picture, output bit-identical.
   The shader is a module constant spliced into the existing compile site in `Compositor.init` and listed in
   `CompositorShaderSources.archived`.
2. **Pixel rule**: red read at p − v, blue at p + v, green and the pixel's own value at p, alpha the largest of the
   three samples; bilinear by hand from `read`, a weight of exactly 0 never mixes in the neighbour.
3. **Edge rule ("edges stay within frame bounds")**: v is scaled by min(1, e ÷ max(amount in pixels, 1)), e the
   distance to the nearest border, so |v| ≤ e and every sample is inside the frame; samples are clamped as well. The
   outermost ring of pixels is shown unchanged. No contrast-aware softening inside the picture.
4. **Bounds**: amount ≤ 2% of the shorter side; no ACC-012 cap (the split moves values, adds no brightness); the
   flash guard measures the shown frame.
5. **Chain**: `OutputEffectKind.chromatic` is appended, so every stored FX-020 order reads with the split last. The
   compositor walks the order; a non-neutral Color listed before the first active Trails or split is applied by
   FX-020's grade pass right before it (outputs then use the neutral grade). With the split inactive, every FX-020
   result is unchanged.
6. **Storage**: a global setting (`settings.chromatic.*`) like Trails; scenes and presets carry an `fx.chromatic`
   entry (`amount`, `angle`, `radial`); a disabled split counts as default, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (7 texel reads per pixel) and one pooled picture while active; with the standard order
  and a non-neutral grade, the grade pass also runs (one more pass).
- Later spatial FX rows can join the same walk as further `OutputEffectKind` cases.
- The device frame-rate check is FX-006-T18 `{device}`.
