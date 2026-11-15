# ADR-0121: Pixel Sort Is One Compute Dispatch Before Vignette, With a Hard Per-Frame Workload Budget

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: FX-011 (`specs/310-fx-011-pixel-sorting`)
- **Constitution**: I (public APIs; shader policy of ADR-0024), VI (modular boundaries), VIII (default output
  bit-identical), X (evidence-based quality)
- **Builds on and amends**: ADR-0117 and ADR-0116 (the standard order gains `fx.pixelSort` between Lens distortion and
  Vignette), ADR-0054 (FX-020 effect chains), ADR-0024 (no new compile site), ADR-0009 (run-time compiled module
  constant)

## Context

The roadmap row FX-011 asks to "reorder luminance segments within a fixed GPU workload", with the acceptance
"threshold changes ordering; worst-case frame budget is enforced". A true pixel sort of whole rows costs time that grows
with content (run lengths) and frame size. Every earlier output effect is a fragment pass with a fixed cost per pixel; a
sort needs a whole run at once.

## Decision

1. **Segments inside fixed tiles.** Rows (or columns) are cut into tiles of `span` ∈ {4, 8, 16, 32, 64} pixels from the
   left (top) edge. A pixel qualifies when its stored colour's Rec. 709 luminance is finite and ≥ threshold. A segment is
   a maximal qualifying run inside one tile; it is stably sorted by luminance ascending in the reading direction.
   Non-qualifying pixels stay. Pixels move whole; no value is computed.
2. **One compute dispatch** (`cmp_pixel_sort`, a module constant spliced after `LensDistortionPass.source` at the
   compositor's existing compile site and listed in `CompositorShaderSources.archived`): one threadgroup of `span`
   threads per tile; each thread loads its pixel to threadgroup memory, finds its segment with one loop of `span` steps,
   counts its stable rank with a second loop of `span` steps and writes its pixel to segment start + rank. The work is
   the same for every picture. This is the first compute pass in the output chain (the flash guard was the first
   compute pipeline); a fragment version would need `span` full-frame passes (odd-even transposition) or O(span²) per
   pixel.
3. **Frame budget.** Workload = W × H × span steps; B = 132,710,400 (7680 × 4320 × 4). The effective span is the largest
   choice ≤ the chosen span with W × H × span ≤ B; if span 4 does not fit, the pass is skipped and counted. At most one
   dispatch per frame; the encoded workload never exceeds B. 1080p sorts at span 64, 4K at 16, 8K at 4.
4. **Chain position.** `OutputEffectKind.pixelSort` is declared between `lensDistortion` and `vignette`: the standard
   order ends … Edge outline, Lens distortion, Pixel sort, Vignette. Stored orders without it read with it last
   (FX-020's rule, unchanged).
5. **Default off**: no pass, no picture, bit-identical output.

## Consequences

- Shorter streaks on very large outputs instead of dropped frames; the footer says so.
- The GPU output equals the CPU reference exactly (a permutation), which makes the acceptance tests exact.
- Device GPU frame time is checked on D1 (FX-011-T16, `{device}`).

## Alternatives considered

- Odd-even transposition in fragment passes (span passes of full-frame traffic), bitonic networks (variable-length
  segments need padding; no gain at span ≤ 64), downscaling above a pixel count (changes pixels outside segments),
  timing feedback (wall-clock dependent).
