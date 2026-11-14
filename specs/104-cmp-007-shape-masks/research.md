# Research: CMP-007 Shape Masks

## CMP-007-D1 — Signed distance in layer pixels, coverage by a clamped smoothstep

- **Decision**: Resolve the mask for the picture size (W × H pixels, shorter side S) into pixels:
  centre c = (cx·W, cy·H), half extents h = 0.5·scale·S, polygon points p·scale·S, corner radius
  r = cornerRadius·2·min(hx, hy), band w = feather·S + 1. A layer pixel centre p maps to the mask's
  local frame by q = R(−θ)(p − c). The signed distance d (negative inside) is: ellipse
  `k0·(k0 − 1)/k1` with k0 = |q/h|, k1 = |q/h²| (exact for circles; Quilez's gradient-normalized
  estimate for ellipses, sign exact), rounded box `|max(a, 0)| + min(max(ax, ay), 0) − r` with
  a = |q| − h + r, polygon: minimum edge distance with an even-odd crossing sign. Coverage
  t = clamp((w/2 − d)/w, 0, 1), cov = t²(3 − 2t), inverted 1 − cov.
- **Rationale**: the clamp makes "beyond the band" exactly 0 (t ≤ 0 ⇒ cov = 0 exactly) and "deep
  inside" exactly 1 (t ≥ 1 ⇒ 3 − 2 = 1, 1·1·1 = 1 exactly), so multiplying premultiplied colour and
  alpha by coverage gives alpha exactly 0 outside and the unmasked value inside. The one-pixel
  minimum band anti-aliases hard edges. Smoothstep is monotonic on 0…1 (CMP-007-R4).
- **Alternatives**: a texture mask rendered per layer (an extra pass and texture per layer;
  rejected by CMP-007-R7); MSAA (does not give exact zeros and does not feather); exact ellipse
  distance (an iterative or quartic solve per pixel; not needed for an alpha edge).

## CMP-007-D2 — Where the mask runs on the GPU

- **Decision**: In the layer's fragment stage of the existing passes. Normal layers with a mask
  draw with a new `cmp_over_masked` fragment (the same fixed-function "over" pipeline state
  settings, in the same open pass) that reads the picture per pixel (identity) or samples it through
  the inverse transform (CMP-005), sanitizes, × opacity, × coverage evaluated at the **layer** pixel
  (the output pixel for identity, the inverse-mapped position for a transform). `cmp_blend` gets the
  mask block at `buffer(1)` and applies coverage to the source before the blend equation; with no
  mask (kind 0) it skips the multiplication, so its output is bit-identical to before.
- **Rationale**: no extra pass (CMP-007-R7); one code path per draw kind; unmasked layers keep
  `cmp_over` / `cmp_over_transformed` untouched (existing goldens stay bit-identical).
- **Alternatives**: masking inside each layer source (every layer kind would change; masks would
  not follow the transform consistently); a separate masking pass (extra bandwidth).

## CMP-007-D3 — The parameter block

- **Decision**: `CMPMask` = rows of the inverse placement (float4 × 2), shape (kind, hx, hy, r),
  edge (band, inverted, point count, 0), then `float2 points[32]`: 64 + 256 = 320 bytes, passed with
  `setFragmentBytes` (limit 4 KB; no buffer per frame). Built from `LayerMaskGeometry` and cached
  per record and picture size, rebuilt only when the mask or the size changes.
- **Rationale**: one fixed layout; no allocation per frame.

## CMP-007-D4 — Polygon cap and fill rule

- **Decision**: 3 to 32 points, non-zero area (|shoelace area| > 1e-12 in local units), even-odd.
  Over the cap or degenerate: the live model refuses (`LayerMaskError`), the scene decoder drops the
  whole mask with a `droppedField` warning naming the reason. See spec Clarifications.
- **Rationale**: a fixed loop bound for the shader; even-odd is what the per-edge crossing test
  gives without a winding sum, and matches SVG `evenodd`.

## CMP-007-D5 — Saved form

- **Decision**: optional `composite.mask` (spec Clarifications), every field written so that
  decode → encode is byte-identical; unknown shape kinds kept as their raw JSON object.
- **Rationale**: same pattern as CMP-006 `composite.fit`; no version bump, so QA-004's migration
  matrix needs no row and older apps drop the field with `droppedField`.

## CMP-007-D6 — Typed steps

- **Decision**: every intermediate in the CPU reference and the block builder is a named, typed
  `Double` (or `Float`), as CMP-006 did; no long mixed literal expressions.
- **Rationale**: such expressions time out the Swift type checker on Linux and Xcode 26.

## CMP-007-D7 — Precision of CPU vs GPU

- **Decision**: the GPU computes in `float` from the same pixel-space numbers; the composite is
  `rgba16Float`. Edge pixels are compared with the reference within 0.01; the exact-zero check uses
  the reference with a 0.05-pixel margin beyond the band (pixels closer than that to the band's
  outer edge are edge pixels, compared with tolerance, and must still be ≥ 0).
- **Rationale**: float rounding can move a pixel by ~1e-4 px across the boundary; the guarantee is
  structural (the clamp), the test proves it on every other pixel.
