# ADR-0117: Lens Distortion Is Its Own Output Pass After Edge Outline: a Bounded Radial Polynomial With Safe Sampling

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-016 (`specs/306-fx-016-lens-distortion`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0104 (FX-006's spatial-pass pattern; the standard order gains a kind,
  `fx.lensDistortion`, after ADR-0114's edge outline), ADR-0054 (FX-020 effect chains), ADR-0024 (no new compile
  site), ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-016 asks to "provide bounded barrel and pincushion warps", with the acceptance "zero distortion is
identity; corners remain safely sampled". A warp reads the picture at other places, so it needs its own pass like the
blurs, the mosaic and the edge outline. The row names `CIColorKernel`, which is per pixel; a Core Image warp kernel
would need a second render stack whose edge sampling the tests could not pin down.

## Decision

1. **Own pass**: `LensDistortionPass` (`cmp_lens_distortion`) writes one pooled `rgba16Float` picture at composite size,
   only while the warp is active (on, strength ≠ 0, frame ≥ 2 × 2). Inactive: no pass, no picture, output
   bit-identical. The shader is a module constant spliced into the existing compile site in `Compositor.init` and listed
   in `CompositorShaderSources.archived`; no user-authored shader.
2. **Mapping**: for an output pixel centre at offset d from the frame middle, r = |d| ÷ half diagonal (corners at r = 1
   at every aspect ratio) and the sample is at middle + d × (1 + k r²) ÷ z, k = 0.3 × strength, strength −1…1
   (positive barrel, negative pincushion). |k| ≤ 0.3 < 1⁄3 keeps r ↦ r (1 + k r²) strictly increasing on 0…1, so the
   warp never folds.
3. **Zoom to fill** (default on): z = 1 + k for k > 0, else 1. Then (1 + k r²) ÷ z ≤ 1 for every pixel, so each sample
   lies on its own ray between the middle and the output point, inside the (convex) frame. Pincushion never leaves the
   frame, zoom or not.
4. **Sampling**: bilinear with the four taps each clamped to the frame; a sample exactly on a pixel centre is that
   pixel, read once (so strength 0 run through the shader is bit-exact). A sample outside 0…W × 0…H (barrel with zoom
   off only) or with a non-finite position gives transparent black (0, 0, 0, 0). No read ever leaves the texture, and
   finite input gives finite output (weights are non-negative and sum to 1).
5. **Chain**: `OutputEffectKind.lensDistortion` is appended, so stored orders read with it after Edge outline; a
   non-neutral Color listed before an active warp is folded into the grade pass right before it (FX-006's rule).
   FX-015's vignette, merged in parallel, goes after it.
6. **Storage**: a global setting (`settings.lensDistortion.enabled`, `.strength`, `.zoomToFill`); scenes and presets carry
   an `fx.lensDistortion` entry (`strength`, `zoomToFill` 0/1); a disabled warp counts as default, so older scenes save
   byte-identically. No ACC-012 cap: the warp adds no brightness.

## Consequences

- One extra full-screen pass (at most four reads per pixel) and one pooled picture while active.
- With zoom on, a barrel warp crops the edges of the picture (the corners stay the picture's corners); with zoom off it
  shows black corners instead.
- The device frame-rate check is FX-016-T17 `{device}`.
