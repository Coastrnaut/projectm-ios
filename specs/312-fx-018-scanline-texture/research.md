# Research: FX-018 Scanline texture

- **FX-018-D1 — Own output pass, not a grade step.** Decision: `ScanlinesPass` with `cmp_scanlines`, a module constant
  appended at `Compositor.init`'s reviewed compile site and in `CompositorShaderSources.archived`; one pooled
  `rgba16Float` picture. Rationale: an overlay texture must stay sharp, so it sits at the end of the chain where no
  later blur, mosaic or lens warp resamples it; it is reorderable and switchable like FX-006 to FX-016; the shared grade
  block is untouched. Alternatives: a step in `cmp_grade_at` (at Color's place, smeared by later passes; grows the
  block every output path binds), a step in the output pass (`cmp_output`, after the flash guard: not reorderable and
  shared by recordings and captures), Core Image (`CIColorKernel`): a second render path outside the pool and order.
  All rejected.
- **FX-018-D2 — Line rule in integer pixels.** Decision: c = y (x when vertical) as the integer pixel index
  `uint(in.position.y)` of the fragment (pixel centres at y + ½, so the integer part is exact); dark when
  c % p < t with p = spacing (2…16) and t = min(thickness, p − 1) (1…15). Integer arithmetic, so the set of dark rows
  is exact for every size; no normalised coordinate, no content scale. Alternatives: a fraction of the height (period
  varies with size; violates the acceptance), points (period varies with the screen scale), a sine profile (no
  exact pixel boundary, needs a tolerance). Rejected.
- **FX-018-D3 — Phase.** Decision: anchored at pixel 0 (row 0 dark), with no time or frame input, so the pattern is
  identical every frame and cannot crawl or flicker; a size change restarts it at the new top-left. The recording
  output is the screen output cropped from the top-left, so its rows are the same rows.
- **FX-018-D4 — Darken only, one factor.** Decision: f = 1 − intensity computed once on the CPU as a `Float` and passed
  in the block; dark pixels return `float4(v.rgb * f, v.a)`, others return `v` itself (the exact value read from a
  half-float picture written back as half: bit-identical). f ∈ [0, 1] so colour never rises and finite stays finite;
  at f = 1 a dark pixel is `v.rgb * 1 = v.rgb` exactly, so the shader run at intensity 0 is also the identity.
  Intensity 0 normally runs no pass.
- **FX-018-D5 — Block and reference.** `CMPScanlines { uint period; uint thickness; uint vertical; float factor; }`
  (16 bytes). The CPU reference applies the same rule and the same single `Float` multiply; the result is rounded to
  half precision by the picture. A single multiply is correctly rounded on both sides, so the tests expect the
  half-rounded reference exactly (a 1-ulp half tolerance is allowed only if a GPU proves otherwise, recorded in the
  test report).
- **FX-018-D6 — Chain position.** Decision: `fx.scanlines` appended after `fx.vignette` (the current last). FX-011's
  `fx.pixelSort` is placed between Lens distortion and Vignette and FX-017's `fx.filmGrain` after Scanlines when those
  branches merge (grain on top of the lines, like grain in a photographed CRT); both sides are kept at merge. Stored
  orders without `fx.scanlines` read with it after their last known kind (FX-020's append rule).
- **FX-018-D7 — Settings and scene entry.** Five keys `settings.scanlines.{enabled,spacing,thickness,intensity,
  vertical}` (Bool, Int, Int, Double, Bool; absent or malformed → default, out of range → nearest bound, spacing and
  thickness rounded), included in FILE-005 backups as visual settings and stored by their own store (not in
  `AppSettings.allKeys`). Setting the spacing lowers a larger stored thickness to spacing − 1. Scene entry
  `fx.scanlines` with `spacing`, `thickness`, `intensity`, `vertical` (0 or 1; ≥ 0.5 reads as vertical), written only
  while on, in a new `SceneEffectChain+Scanlines.swift`; `SceneEffectSettings.scanlines` is a property set after
  `init` (like `vignette`), so the shared initialiser does not change.
- **FX-018-D8 — Safety.** No ACC-012 cap and no flash-policy entry: the effect only darkens and is static; the flash
  guard judges the shown frame. A line pitch of 2 px at high intensity can show moiré on a downscaled preview; this is
  a property of the picture, not a temporal hazard.
