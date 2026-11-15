# ADR-0106: The Directional Blur Is Its Own Output Pass With a Fixed 16-Tap Kernel, Fourth in the Effect Chain

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-007 (`specs/295-fx-007-directional-blur`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0104 (FX-006: the effect-chain walk gains a fourth kind, `fx.directionalBlur`; the
  standard order becomes Trails → Color → Chromatic split → Directional blur), ADR-0054 (FX-020 chain), ADR-0024 (no
  new compile site), ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-007 asks to "blur along a selected angle with fixed tap budget", with the acceptance "angle zero
blurs horizontally and radius zero is identity". Like the chromatic split, the blur reads neighbouring pixels, so it
cannot live in the per-pixel output pass.

## Decision

1. **Own pass**: `DirectionalBlurPass` (`cmp_directional_blur`) writes one pooled `rgba16Float` picture at composite
   size, only while the blur is active (on and radius > 0 pixels). Inactive: no pass, no picture, output
   bit-identical. The shader is a module constant spliced into the existing compile site in `Compositor.init` and
   listed in `CompositorShaderSources.archived`.
2. **Fixed tap budget**: exactly 16 samples per pixel (shader constant `cmp_dirblur_taps`), evenly spaced from −radius
   to +radius along d = (cos θ, −sin θ), with fixed Gaussian weights (σ = radius ÷ 2) that sum to 1. The cost does not
   depend on the radius.
3. **Axis**: angle 0…180° (the axis has no sign); direction components below 1e-6 are snapped to 0, so 0° samples only
   the pixel's own row and 90° only its own column.
4. **Sampling and edges**: hardware linear filtering on positions clamped to the frame's pixel centres; past the
   border the border pixel repeats, so no outside value is read. No fade at the border (unlike ADR-0104), because
   clamped positions alone keep the blur inside the frame.
5. **Bounds**: radius ≤ 2% of the shorter side; no ACC-012 cap (the blur averages values, adds no brightness).
   A non-finite own pixel passes through; non-finite samples are skipped and the weights renormalised.
6. **Chain and storage**: `OutputEffectKind.directionalBlur` is appended after `chromatic`; a non-neutral Color listed
   before an active blur is folded into the grade pass right before it. Global setting `settings.directionalBlur.*`;
   scenes and presets carry an `fx.directionalBlur` entry (`radius`, `angle`); a disabled blur counts as default.

## Consequences

- One extra full-screen pass (16 filtered samples per pixel) and one pooled picture while active.
- The GPU output matches the CPU reference within hardware filtering precision, not bit for bit (the bypass is
  bit-exact).
- The device frame-rate check is FX-007-T17 `{device}`.
