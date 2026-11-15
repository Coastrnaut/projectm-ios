# ADR-0123: Scanlines Are Their Own Output Pass After Vignette: an Integer Line Rule Anchored at Pixel 0, One Darkening Factor

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-018 (`specs/312-fx-018-scanline-texture`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0116 (FX-015's output-pass pattern; the standard order gains a kind, `fx.scanlines`,
  appended after `fx.vignette`), ADR-0110 (whole-pixel sizes, FX-012), ADR-0054 (FX-020 effect chains), ADR-0024 (no
  new compile site), ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-018 asks to "apply adjustable scanline spacing and intensity", with the acceptance "spacing is
consistent in pixels and disabled state is identity". A smooth (sine) profile or a spacing relative to the frame would
make the pitch depend on the output size and need tolerances. FX-011 (pixel sort, before Vignette) and FX-017 (film
grain) are built in parallel and append their own kinds.

## Decision

1. **Own pass**: `ScanlinesPass` (`cmp_scanlines`) writes one pooled `rgba16Float` picture at composite size, only
   while active (on, intensity > 0, frame ≥ 2 × 2). Off or intensity 0: no pass, no picture, output bit-identical. The
   shader is a module constant spliced into the existing compile site in `Compositor.init` and listed in
   `CompositorShaderSources.archived`.
2. **Integer line rule**: with c the integer row index (column when vertical) of the pixel in the picture the chain
   works on, p the spacing (2…16 px) and t = min(thickness, p − 1) (thickness 1…15 px), a pixel is in a line exactly
   when c mod p < t. Row (column) 0 is always dark: the phase is anchored at the top-left pixel, with no time input,
   so the pattern is identical every frame and never crawls. Nothing scales p (no content scale, no frame fraction):
   each output (screen, external display with its own compositor, recording cropped from the top-left, still capture)
   gets the period in its own pixels.
3. **One factor, darken only**: line pixels are colour × f with f = 1 − intensity (one `Float` per frame), alpha kept;
   every other pixel is the value read, bit for bit. f ∈ [0, 1], so nothing brightens, finite stays finite, and at f = 1
   the pass is the identity even if run.
4. **Chain**: `OutputEffectKind.scanlines` is appended after Vignette (stored orders read with it last). When FX-017
   merges, Film grain goes after Scanlines (grain on top of the lines); FX-011's Pixel sort stays before Vignette.
5. **Storage**: a global setting (`settings.scanlines.enabled`, `.spacing`, `.thickness`, `.intensity`, `.vertical`);
   scenes and presets carry an `fx.scanlines` entry (`spacing`, `thickness`, `intensity`, `vertical`); a disabled
   effect counts as default, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (one read per pixel) and one pooled picture while active.
- OUT-008's projection mesh resamples after the chain and bends the lines with everything else; the rule is exact in
  the picture before the mesh.
- No ACC-012 cap or motion-policy entry: the effect is static and only darkens; the flash guard judges the shown frame.
- The device check (look and frame rate) is FX-018-T16 `{device}`.
