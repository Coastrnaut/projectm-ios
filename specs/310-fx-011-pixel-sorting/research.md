# Research: FX-011 Pixel Sorting Approximation

All decisions by Claude under owner rule 4 (best judgement); 2026-11-15.

## FX-011-D1: Own pass, the FX-014/FX-015/FX-016 pattern, as one compute dispatch

- **Decision**: `PixelSortPass` with the kernel `cmp_pixel_sort`, one pooled `rgba16Float` picture (the pool's
  pictures already allow shader writes) taken on the first active frame and returned when inactive, at a size change
  and with the compositor; the source is spliced after `LensDistortionPass.source` at the existing compile site and
  listed in `CompositorShaderSources.archived`. The compute pipeline is made from the shared library (the flash guard
  already uses compute, CMP-001); the archive key includes the source even though compute pipelines are not archived,
  so a source edit still changes the key.
- **Rationale**: sorting needs every pixel of a tile at once; a threadgroup holds the tile in fast memory.
- **Alternatives**: L fragment passes of odd-even transposition (exact, but L full-frame passes: at span 32 on a 4K
  frame about 32 × 66 MB of traffic per frame); a fragment gather of the k-th smallest (O(L²) per pixel); a bitonic
  network (O(L log² L) compare steps but L must be a power of two per segment, and segments are variable-length runs:
  padding makes it as costly as the rank loop at L ≤ 64 and more complex).

## FX-011-D2: Segments = qualifying runs inside fixed tiles

- **Decision**: tiles of the effective span from the left (top) edge; qualifying = finite Rec. 709 luminance ≥
  threshold on the stored colour; segment = maximal qualifying run inside a tile.
- **Rationale**: tiles cap the segment length at the span, which is what makes the workload fixed; luminance is
  preserved by moving pixels, so the mask does not change as pixels move. Non-finite luminance never qualifies, so the
  sort compares only finite numbers.

## FX-011-D3: Stable rank-and-scatter with fixed loops

- **Decision**: thread i (pixel i of the tile) computes the segment start s (the first index after the last
  non-qualifying pixel before i) and end e with one loop over all `span` indices, then, if it qualifies, its rank
  r = #{ j in [s, e) : lum_j < lum_i, or lum_j = lum_i and j < i } with a second loop over all `span` indices (masked),
  and writes its pixel to s + r; a non-qualifying pixel writes itself in place. Threads beyond the frame edge (partial
  last tile) load nothing, never qualify and write nothing.
- **Rationale**: ranks of distinct (lum, index) keys are a permutation of [s, e), so every output pixel is written once;
  the result equals a stable sort; work is exactly 2 × span steps per thread whatever the picture.
- **CPU reference**: the same definition with Swift's stable sort per segment (independent algorithm), compared exactly.

## FX-011-D4: The frame budget

- **Decision**: steps(W, H, span) = W × H × span. B = 132,710,400 (7680 × 4320 × 4). Effective span = the largest of
  {4, 8, 16, 32, 64} ≤ chosen span with steps ≤ B; none → skip (counted). The pass is active only for frames ≥ 2 pixels
  along the direction and ≥ 1 across. The compositor exposes `pixelSortEffectiveSpan`, `pixelSortWorkload` (last
  frame), `pixelSortDispatches` and `pixelSortBudgetSkips`; tests can lower the budget (`pixelSortBudget`, internal
  default B) to exercise the skip on small frames.
- **Rationale**: 1080p runs at span 64, 4K at 16, 8K (the largest external output, `ExternalOutputRehearsal.maximumSide`
  7680) at 4; iPhone 15 Pro Max-class screens (≈ 1290 × 2796) at 32. Reducing the span keeps the effect's meaning
  (shorter streaks) and exactness; downscaling would change pixels outside segments.
- **Alternatives**: downscale above a pixel count (breaks "untouched" pixels); per-frame timing feedback (wall clock
  dependent, untestable).

## FX-011-D5: Chain position

- **Decision**: `OutputEffectKind.pixelSort` declared between `lensDistortion` and `vignette`, so the standard order is
  … Edge outline, Lens distortion, Pixel sort, Vignette (Vignette stays last).
- **Rationale**: the sort works on the finished, warped picture, and the vignette's darkening frames the result rather
  than being sorted into streaks. Stored orders without the kind read with it appended last (FX-020's rule, unchanged).

## FX-011-D6: Settings and scene

- **Decision**: four keys (clarifications); scene entry `fx.pixelSort` with `threshold`, `span`, `vertical`, written
  only while on; span snapped down to a choice after clamping.
