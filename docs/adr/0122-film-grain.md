# ADR-0122: Film Grain Is Its Own Output Pass, Last in the Effect Chain, From an Integer Hash With a Capped Grain Clock

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-017 (`specs/311-fx-017-film-grain`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0116 (FX-015's vignette was last; the standard order gains `fx.filmGrain` after it),
  ADR-0117 (output-pass pattern), ADR-0054 (FX-020 effect chains), ADR-0024 (no new compile site), ADR-0009 (run-time
  compiled module constant)

## Context

The roadmap row FX-017 asks to "overlay deterministic seeded grain with optional temporal variation", with the
acceptance "fixed seed produces stable snapshots and opacity zero is identity". Grain must be the same on every GPU
(snapshots), must never strobe, and must not shift the picture's brightness.

## Decision

1. **Own pass, last**: `FilmGrainPass` (`cmp_film_grain`) writes one pooled `rgba16Float` picture while active (on,
   opacity > 0, frame ≥ 2 × 2). Off or opacity 0: no pass, no picture, output bit-identical; the shader also returns its
   input at scale 0. Module constant spliced into the existing compile site and listed in
   `CompositorShaderSources.archived`. Standard order: Trails → Color → Chromatic split → Directional blur → Radial blur
   → Echo → Mosaic → Edge outline → Lens distortion → Vignette → Film grain (grain sits on top of the final picture;
   FX-011's pixel sort inserts before Vignette, FX-018's scanlines may follow).
2. **Integer hash**: PCG hash (Jarzynski and Olano) chained over seed × 4 + channel, grain frame, cell row and cell
   column, 32-bit wrapping; n = (h >> 8) × 2⁻²³ − 1, exact in Float. No floating-point sine hash. The GPU's hash and
   noise equal the Swift reference bit for bit (tested by reading them back).
3. **Blend**: d = (opacity × 0.08) × n × alpha added to the linear premultiplied colour, floored so a channel never goes
   below zero (or below its own negative value); alpha kept. Zero-mean, peak change ≤ 0.08 of white; no ACC-012 cap.
4. **Grain clock**: grain frame = presentation time ÷ 41 666 667 ns (≤ 24 Hz) from CMP-001's injected clock when "Vary
   over time" is on; 0 (static) when off, under Reduce flashing (compositor, from the frame context) or under Reduce
   Motion (app's effective value). Stateless: the same time gives the same grain.
5. **Storage**: global setting (`settings.filmGrain.enabled`, `.opacity`, `.size`, `.color`, `.seed`, `.animated`);
   scenes and presets carry an `fx.filmGrain` entry, written only while on, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (one read, up to three hashes per pixel) and one pooled picture while active.
- Core Image's random generator is not used (not exact across GPUs, outside the pool and order).
- The device frame-rate check is FX-017-T17 `{device}`.
