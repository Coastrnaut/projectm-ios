# Research: FX-008 Radial Blur

All decisions by Claude under owner rule 4 (best judgement); 2026-11-15.

## FX-008-D1: Own pass, FX-006's pattern

- **Decision**: `RadialBlurPass` with `cmp_radial_blur`, one pooled `rgba16Float` picture taken on the first active
  frame and returned when inactive, at a size change and with the compositor; the source is spliced after
  `ChromaticSplitPass.source` at the existing compile site and listed in `CompositorShaderSources.archived`.
- **Rationale**: a blur reads neighbours, so it cannot live in the per-pixel output pass; FX-006 proved the pattern.
- **Alternatives**: extending `cmp_chromatic` (couples two effects and their order); a compute kernel (a second
  pipeline kind for no gain).

## FX-008-D2: Sample positions (gather towards the focus)

- **Decision**: output(P) = mean over k = 0…15 of input(F + (P − F) ÷ (1 + s·k/15)).
- **Rationale**: every sample is on the segment from P to F, so it is inside the frame whenever F is (the frame is
  convex); the spread of P, |P − F|·s ÷ (1 + s), is linear in its distance and zero at the focus; a bright point at
  distance d is picked up by outputs from d to d(1 + s) on its ray, a streak of exactly d·s pixels pointing outward
  ("blur outward"). Sample 0 is P itself.
- **Alternatives**: samples at P − (P − F)·s·t (streak d·s ÷ (1 − s), not linear in s); samples outward from P (need
  clamping at the frame and smear border colour inward).

## FX-008-D3: Fixed budget and cap

- **Decision**: 16 samples always (a constant loop bound in the shader and `RadialBlur.tapCount`); strength 0…0.25,
  default 0.1, step 0.01.
- **Rationale**: constant cost per pixel; at 25% the copies of a sharp point at the far corner of a 1080p frame are
  about 9 px apart, which blends on soft visualizer content.
- **Alternatives**: a tap count growing with the spread (variable cost); jittered samples (noise, not deterministic).

## FX-008-D4: Filtering and identity

- **Decision**: the GPU's linear filter (`coord::pixel`, `clamp_to_edge`), each position additionally clamped to the
  frame; a pixel whose spread is exactly 0 or whose own value is non-finite returns its own value (bit for bit).
- **Rationale**: one fetch per sample instead of four reads; the clamps make out-of-frame reads impossible even for
  rounding. The hardware's sub-pixel weights are coarser than float, so GPU vs reference is checked within 1/128.
- **Alternatives**: manual bilinear from `read` like FX-006 (exact, but 64 reads per pixel).

## FX-008-D5: Plain-Swift model

- **Decision**: `RadialBlur` (Codable, Sendable) with clamps, `focusPixels`, `isActive`, `block`, `samplePositions`,
  `spread` and `referencePixel`/`reference` using exact bilinear weights; no Metal, so it builds on Linux.

## FX-008-D6: Chain position

- **Decision**: `OutputEffectKind.radialBlur = "fx.radialBlur"`, appended after `.chromatic`; stored FX-020/FX-006
  orders read with the blur last. A non-neutral Color listed before an active blur is folded into the grade pass right
  before it (the same rule as Trails and the split).
- **Rationale**: append-only keeps every stored order valid; FX-007 appends its own case and the merge decides the
  final order of the two new kinds.

## FX-008-D7: No new compile site

- **Decision**: the source joins the one `CompositorShaders.library` call in `Compositor.init`; the shader takes only
  a 32-byte constant block (`CMPRadialBlur`: focus, strength, last pixel); no user text reaches it (SHD-011).

## FX-008-D8: Settings and storage

- **Decision**: `settings.radialBlur.enabled` (Bool), `.strength`, `.focusX`, `.focusY` (Double), written only when
  changed; included in FILE-005 backups and FILE-011 erase; scenes store `fx.radialBlur` (`strength`, `focusX`,
  `focusY`) only while on (a disabled blur counts as default). No ACC-012 cap (averaging adds no brightness).
