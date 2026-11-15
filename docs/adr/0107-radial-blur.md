# ADR-0107: The Radial Blur Is Its Own Output Pass, Fourth in the Effect Chain, Gathering 16 Samples Towards the Focus

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-008 (`specs/296-fx-008-radial-blur`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0104 (FX-006's spatial-pass pattern; the standard order gains a fourth kind,
  `fx.radialBlur`, after the split), ADR-0054 (FX-020 effect chains), ADR-0024 (no new compile site), ADR-0009
  (run-time compiled module constant)

## Context

The roadmap row FX-008 asks to "blur outward from an adjustable focus point", with the acceptance "center remains
stable while outer test points spread predictably". A blur reads neighbours, so like FX-006 it needs its own pass.
FX-007 (directional blur) is built in parallel and appends its own kind.

## Decision

1. **Own pass**: `RadialBlurPass` (`cmp_radial_blur`) writes one pooled `rgba16Float` picture at composite size, only
   while the blur is active (on, strength > 0, frame ≥ 2 × 2). Inactive: no pass, no picture, output bit-identical.
   The shader is a module constant spliced into the existing compile site in `Compositor.init` and listed in
   `CompositorShaderSources.archived`.
2. **Pixel rule**: out(P) = mean of 16 samples at F + (P − F) ÷ (1 + s·k/15), k = 0…15 (sample 0 is P). Every sample
   lies between P and the focus F, so inside the frame; positions are clamped as well. A pixel's spread is
   |P − F|·s ÷ (1 + s): zero at the focus (passed through bit for bit) and linear in distance; a bright point at
   distance d becomes a streak from d to d(1 + s), pointing away from the focus.
3. **Budget and filter**: a fixed 16 samples (constant cost), the GPU's linear filter (16 fetches per pixel); the
   software reference uses exact bilinear weights and the GPU must match it within 1/128.
4. **Bounds**: strength ≤ 25%; focus 0…1 of width and height (0 = left/top). No ACC-012 cap (averaging adds no
   brightness); the flash guard measures the shown frame.
5. **Chain**: `OutputEffectKind.radialBlur` is appended, so stored orders read with the blur last; a non-neutral
   Color listed before an active blur is folded into the grade pass right before it (FX-006's rule). The merge with
   FX-007 decides the relative position of the two new kinds by appending both.
6. **Storage**: a global setting (`settings.radialBlur.*`); scenes and presets carry an `fx.radialBlur` entry
   (`strength`, `focusX`, `focusY`); a disabled blur counts as default, so older scenes save byte-identically.

## Consequences

- One extra full-screen pass (16 filtered fetches per pixel) and one pooled picture while active; with the standard
  order and a non-neutral grade, the grade pass also runs.
- Long streaks of sharp points show as separate copies (16 samples); accepted for soft visualizer content.
- The device frame-rate check is FX-008-T18 `{device}`.
