# ADR-0114: Edge Outline Is Its Own Output Pass, Last in the Effect Chain, a Sobel Mask on Linear Luminance

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-014 (`specs/303-fx-014-edge-outline`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0104 (FX-006's spatial-pass pattern; the standard order gains a kind,
  `fx.edgeOutline`, after ADR-0110's mosaic), ADR-0054 (FX-020 effect chains), ADR-0049 (ACC-012 intensity limit),
  ADR-0024 (no new compile site), ADR-0009 (run-time compiled module constant)

## Context

The roadmap row FX-014 asks to "highlight image gradients with adjustable threshold and color", with the acceptance
"flat image produces no outlines and checkerboard produces boundaries". An edge filter reads neighbouring pixels, so it
needs its own pass like the blurs and the mosaic. The row names `CIColorKernel`, which is per-pixel and cannot read
neighbours; a Core Image edge filter would need a second render stack.

## Decision

1. **Own pass**: `EdgeOutlinePass` (`cmp_edge_outline`) writes one pooled `rgba16Float` picture at composite size,
   only while the outline is active (on, frame ≥ 2 × 2). Off: no pass, no picture, output bit-identical. The shader is
   a module constant spliced into the existing compile site in `Compositor.init` and listed in
   `CompositorShaderSources.archived`; no user-authored shader.
2. **Edge rule**: a 3 × 3 Sobel of Rec. 709 linear luminance with taps at ±width pixels (1…3), each clamped to the
   frame; strength = |G| ÷ 4 (a 0 → 1 step is 1); mask = smoothstep(t, t + 0.1, strength), exactly 0 at or below the
   threshold t (0.02…1, default 0.2) and where the strength is not finite.
3. **Modes**: overlay (default) returns the input pixel unchanged where the mask is 0, else mixes toward the opaque
   outline colour; outline only mixes opaque black toward it. Flat pictures are therefore bit-identical in overlay and
   black in outline-only, borders included (clamped taps).
4. **Colour and safety**: the colour is chosen in sRGB (default white), converted to linear on the CPU; under an
   ACC-012 intensity limit below 1 the linear colour is multiplied by the limit. The flash guard (FX-019) still judges
   the shown frame.
5. **Chain**: `OutputEffectKind.edgeOutline` is appended, so stored orders read with it last; a non-neutral Color
   listed before an active outline is folded into the grade pass right before it (FX-006's rule). Standard order:
   Trails → Color → Chromatic split → Directional blur → Radial blur → Echo → Mosaic → Edge outline.
6. **Storage**: a global setting (`settings.edgeOutline.enabled`, `.threshold`, `.width`, `.color` hex, `.mode`);
   scenes and presets carry an `fx.edgeOutline` entry (`threshold`, `width`, `red`, `green`, `blue`, `mode` 0/1); a
   disabled outline counts as default, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (nine reads per pixel) and one pooled picture while active.
- Edges are found on linear luminance, so dark-region contrast reads weaker than it looks; the threshold's low end
  (0.02) compensates. Colour edges of equal luminance are not outlined.
- The device frame-rate check is FX-014-T18 `{device}`.
