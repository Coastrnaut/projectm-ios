# Research: CMP-006 Aspect Fitting

## CMP-006-D1: One placement for all four modes: a visible content rectangle

- **Decision**: Every mode is a uniform or per-axis scale plus an offset, expressed as the part of
  the content that the output shows: `visible = (Wo ÷ (Wc·sx), Ho ÷ (Hc·sy))` in content fractions,
  `offset = anchor·(1 − visible)`. The texture coordinate of output point p (0…1) is
  `offset + p·visible`; coordinates outside 0…1 are transparent. Scales: fill `s = max(Wo/Wc, Ho/Hc)`,
  fit `s = min(…)`, stretch `sx = Wo/Wc, sy = Ho/Hc` (visible = 1, offset = 0), pixelAccurate
  `s = k` (output pixels per content pixel, default 1).
- **Rationale**: The photo shader already samples exactly this rectangle (`offset + p·visible`,
  transparent outside), so fill and fit keep their exact numbers and the new modes need no new
  pass. The same rectangle gives the content → output matrix (`x_out = (u − offset) ÷ visible`), which
  composes with the CMP-005 matrix for tests and future callers.
- **Alternatives**: expressing the fit as a CMP-005 `LayerTransform` (scale + move) on a stretched
  picture: rejected, it resamples twice (stretch, then un-stretch), loses resolution, and stacks
  two user-visible transforms.

## CMP-006-D2: Anchor semantics

- **Decision**: `offset = anchor·(1 − visible)` per axis. At output point p = anchor the content
  coordinate is `anchor·(1 − visible) + anchor·visible = anchor`: the anchor point of the content lands
  on the same fraction of the output, for any output size. With visible < 1 (crop) the anchor picks
  the kept part; with visible > 1 (bars) it places the content. Stretch ignores it.
- **Rationale**: One formula, independent of orientation, is what "maintains chosen crop across
  landscape output" needs: changing the output changes `visible`, never the anchor rule.

## CMP-006-D3: pixelAccurate scale and whole-pixel origin

- **Decision**: `k = 1` output (drawable) pixel per content pixel; `contentScale` is ignored (spec
  Clarifications). The content's origin in output pixels, `anchor·(Wo − Wc·k)`, is rounded to the
  nearest whole pixel (ties away from zero, Swift `.rounded()`), and the offset is derived from the
  rounded origin. Then output pixel centre i maps to content `(i + 0.5 − origin) ÷ Wc`, a texel centre:
  bilinear sampling returns the texel unmixed.
- **Rationale**: Without rounding an odd size difference puts every sample half-way between texels
  and blurs the picture, defeating the mode.

## CMP-006-D4: Typed arithmetic

- **Decision**: Every intermediate is a named `Double` (`let sx: Double = …`), and matrices are built
  element by element; no long mixed expression.
- **Rationale**: Long untyped arithmetic trips the type checker's time limit on Linux and Xcode 26.

## CMP-006-D5: How the fit reaches a layer

- **Decision**: `LayerCompositeSettings.fit: LayerFit?` plus a Metal-side protocol `LayerFitting`
  (`var fit: LayerFit? { get set }`). The compositor sets it on a conforming layer when the layer is
  added (`init`, `apply`) and on every apply for kept layers. The layer computes the placement in
  `render` from the picture's size, so an output size change (rotation, external display) needs
  nothing more.
- **Rationale**: Fitting needs the content's pixel size, which only the layer knows; the compositor
  never sees it. The stack entry stays the one source of truth, like opacity, transform and blend.
- **Alternatives**: putting the fit into `LayerFrameContext` (per frame for all layers; wrong scope);
  rebuilding the layer on a fit change (reloads the photo or restarts the video decode; rejected by
  CMP-006-R7).

## CMP-006-D6: Video fits the upright size; bars are transparent

- **Decision**: `VideoPictureGeometry` computes the placement on the upright size (width and height
  swap for a quarter turn), then maps the upright coordinate to the texture with the rotation, the
  same mapping the shader used before. The shader returns transparent outside 0…1.
- **Rationale**: Keeps today's fill output identical (the old `CameraPictureGeometry` fill clamps
  visible to ≤ 1, which fill always is) and removes VideoLayer's dependency on CameraLayer's fill
  geometry, which CAM-007 is changing.

## CMP-006-D7: Saved form

- **Decision**: `composite.fit = {"mode": string, "anchor": {"x","y"}}`, optional, written only when
  set; unknown names kept and warned (`unsupportedFitMode`); version 1 unchanged.
- **Rationale**: SCN-001's rule: new optional fields keep version 1 (QA-004 matrix unchanged);
  omitting the field when unset keeps every existing scene byte-identical. Mirrors CMP-004's
  unknown-blend handling, including preservation through load → capture.
