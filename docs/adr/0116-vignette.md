# ADR-0116: Vignette Is Its Own Output Pass, Last in the Effect Chain, Darkening Only Outside a Clear Core

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-015 (`specs/305-fx-015-vignette`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0110 (FX-012's output-pass pattern; the standard order gains a kind, `fx.vignette`,
  appended last), ADR-0104 (spatial-pass pattern), ADR-0054 (FX-020 effect chains), ADR-0024 (no new compile site),
  ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-015 asks to "apply radial falloff with center and softness controls", with the acceptance "center
brightness stays unchanged at zero intensity". The falloff depends only on the pixel's own value and position, so it
could be a step of the per-pixel grade (`cmp_grade_at`, which FX-013 made position-aware) or a pass of its own.
FX-014 (edge outline) is built in parallel and appends its own kind.

## Decision

1. **Own pass, not a grade step**: `VignettePass` (`cmp_vignette`) writes one pooled `rgba16Float` picture at
   composite size, only while the vignette is active (on, intensity > 0, frame ≥ 2 × 2). Off or intensity 0: no pass,
   no picture, output bit-identical. The shader is a module constant spliced into the existing compile site in
   `Compositor.init` and listed in `CompositorShaderSources.archived`. A grade step was rejected: it would sit at
   Color's place (later blurs, split and mosaic would smear the falloff) and grow the grade block every output path
   binds.
2. **Pixel rule**: d = |((P − C) ÷ (W/2, H/2))| ÷ √2 (an ellipse following the frame; corners at 1 from the middle),
   t = clamp((d − (1 − softness)) ÷ softness, 0, 1), w = t²(3 − 2t), colour × (1 − intensity·w), alpha kept, in the
   linear premultiplied composite. The same Float steps in Swift and MSL.
3. **Darken only, exact core**: the factor is in [0, 1], so no channel rises and finite stays finite; where w = 0
   (distance below 1 − softness, the centre always) it is exactly 1 and the pixel is bit-exact at any intensity.
4. **Bounds**: intensity 0…1 (default 0.5), softness 0.1…0.9 (default 0.5; the core is never empty and the band never
   divides by zero), centre 0…1 of the width and height (default 0.5, 0.5). No ACC-012 cap (darkening adds no
   brightness); the flash guard measures the shown frame.
5. **Chain**: `OutputEffectKind.vignette` is appended, so stored orders read with the vignette last; a non-neutral
   Color listed before it is folded into the grade pass right before it. Standard order: Trails → Color → Chromatic
   split → Directional blur → Radial blur → Echo → Mosaic → (Edge outline, FX-014) → Vignette.
6. **Storage**: a global setting (`settings.vignette.enabled`, `.intensity`, `.softness`, `.centerX`, `.centerY`);
   scenes and presets carry an `fx.vignette` entry (`intensity`, `softness`, `centerX`, `centerY`); a disabled
   vignette counts as default, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (one read per pixel) and one pooled picture while active; with the standard order and a
  non-neutral grade, the grade pass also runs.
- Core Image (`CIVignette`) is not used: it would be a second render path outside the compositor's pool and order.
- The device frame-rate check is FX-015-T15 `{device}`.
