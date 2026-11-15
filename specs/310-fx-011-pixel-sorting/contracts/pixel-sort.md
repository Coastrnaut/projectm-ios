# Contract: FX-011 Pixel Sort

## C1 Compositor

- `Compositor.pixelSort: PixelSort` (default `.off`), set between frames; turning it off returns the picture.
- `pixelSortDispatches`, `pixelSortBudgetSkips`, `pixelSortEffectiveSpan`, `pixelSortWorkload`, `holdsPixelSortPicture`.
- In `encodeOutputEffects`, case `.pixelSort`: `plan(width:height:budget:)`; not `runs` → continue (a skip increments
  `pixelSortBudgetSkips`); else fold Color, encode one dispatch, `shown` = its picture.

## C2 Sort (CPU reference = GPU)

For each row (horizontal) or column (vertical), tiles [k·L, min((k+1)·L, N)); qualifies(p) = finite(lum(p)) ∧ lum(p) ≥
threshold, lum = 0.2126 r + 0.7152 g + 0.0722 b (Float); each maximal qualifying run in a tile is stably sorted by lum
ascending in the reading direction; other pixels unchanged. The GPU output equals the reference bit for bit.

## C3 Budget

B = 132,710,400. effectiveSpan = max{ s ∈ {4,8,16,32,64} : s ≤ span ∧ W·H·s ≤ B }; none → skip. Active only when on,
the frame ≥ 2 along the direction and ≥ 1 across. Encoded work per frame ≤ B; dispatches per frame ∈ {0, 1}.

## C4 Scene entry `fx.pixelSort`

Parameters `threshold` (0…1, fallback 0.5), `span` (4…64, fallback 32, snapped down), `vertical` (0…1, fallback 0,
≥ 0.5 vertical). Written only while on; missing or invalid values reported and defaulted or clamped.

## C5 Settings

Keys `settings.pixelSort.enabled|threshold|span|direction`, in FILE-005 included keys, `ALLOWED_KEYS`, the UI-test
reset and the backup/erase app tests.
