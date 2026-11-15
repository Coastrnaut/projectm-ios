# Research: FX-016 Lens Distortion

All decisions by Claude under owner rule 4 (best judgement); 2026-11-15.

## FX-016-D1: Own pass, the FX-012/FX-014 pattern

- **Decision**: `LensDistortionPass` with `cmp_lens_distortion`, one pooled `rgba16Float` picture taken on the first
  active frame and returned when inactive, at a size change and with the compositor; the source is spliced after
  `EdgeOutlinePass.source` at the existing compile site and listed in `CompositorShaderSources.archived`.
- **Rationale**: a warp reads the picture at other places, so it cannot live in the per-pixel output pass; six effects
  proved the pattern. `CIColorKernel` (named in the roadmap row) is per pixel; a Core Image `CIWarpKernel` could warp
  but needs a second render stack, its own colour handling and its own edge rules, which would make the "corners stay
  in range" proof depend on Core Image internals.
- **Alternatives**: Core Image warp kernel or `CIBumpDistortion` (no exact identity, unclear edge sampling); a compute
  kernel (a second pipeline kind for no gain); a mesh warp in the vertex stage (non-exact identity through
  rasterisation, coarser).

## FX-016-D2: Radial polynomial with a bounded coefficient

- **Decision**: source = middle + d × (1 + k r²) ÷ z, r = |d| ÷ half diagonal, k = 0.3 × strength, strength in −1…1.
- **Rationale**: the one-term Brown model is the standard lens description; the radial map g(r) = r (1 + k r²) ÷ z has
  g'(r) = (1 + 3 k r²) ÷ z, positive on 0 ≤ r ≤ 1 whenever k > −1⁄3. |k| ≤ 0.3 leaves g'(1) ≥ 0.1 at the strongest
  pincushion, so the warp never folds. Normalising by the half diagonal puts the corners at r = 1 at every aspect ratio
  and keeps the warp round (a circle stays a circle); the half diagonal is ≥ √2⁄2·2 = √2 for a 2 × 2 frame, so no
  division by zero. A polynomial has no NaN or overflow for these finite inputs.
- **Alternatives**: normalising by the half width or height (non-round on wide frames, corners at r > 1 so the bound
  would depend on the aspect ratio); a division model r ÷ (1 + k r²) (folds for barrel at larger k).

## FX-016-D3: Zoom to fill (default on)

- **Decision**: z = 1 + k when zoom is on and k > 0, else 1.
- **Rationale**: for k > 0, f(r) = (1 + k r²) ÷ (1 + k) ≤ 1 for r ≤ 1, so each sample is the output point moved toward
  the middle along its own ray; the frame is convex and contains the middle, so the sample stays inside it. Every
  pixel centre has r < 1. For k ≤ 0, f ≤ 1 without zoom, so pincushion never needs it. At k = 0, z = 1 and f = 1
  exactly.
- **Alternatives**: always black corners (honest but ugly for performers); clamp-to-edge stretching (smears the edge
  pixels into streaks; hides that the warp left the picture).

## FX-016-D4: Bilinear taps clamped to the frame, exact read on pixel centres

- **Decision**: in pixel units with pixel centres at i + ½: x = sx − ½, x0 = ⌊x⌋, fx = x − x0, taps x0 and x0 + 1 each
  clamped to 0…W − 1 (same for y); when fx = fy = 0 the result is the single read at (x0, y0), else the weighted sum of
  the four reads. A sample is inside the picture when 0 ≤ sx ≤ W and 0 ≤ sy ≤ H; outside gives (0, 0, 0, 0).
- **Rationale**: no read can leave the texture whatever the coordinate; weights are non-negative and sum to 1, so finite
  input gives finite output and no value exceeds the largest neighbour. At strength 0, d × 1 = d exactly, so the sample
  is the pixel centre and the exact read returns the input bit for bit (a weighted sum would turn −0 into +0).
- **Alternatives**: hardware sampler with clamp-to-edge (exactness of the weights at centres depends on the GPU's
  fixed-point filtering; the CPU reference could not be exact); nearest neighbour (aliasing at every strength).

## FX-016-D5: Out-of-range fill is transparent black

- **Decision**: (0, 0, 0, 0) premultiplied.
- **Rationale**: nothing outside the picture is read or invented; the composite is premultiplied, so this is "no
  content", which later effects and the tone map treat like any transparent area; recordings show black there.
- **Alternatives**: opaque black (would hide a transparent layer stack's alpha); edge colour (streaks).

## FX-016-D6: Plain-Swift model and reference

- **Decision**: `LensDistortion` (value, clamps, `isActive`, `coefficient`, `inverseZoom`, `block(width:height:)`,
  `sample(x:y:block:)` → source position and inside flag, `taps(...)`, `referencePixel`, `reference`) in Float, the
  same arithmetic as the shader.
- **Rationale**: Linux-testable, lets the dense-grid safety proof run without a GPU and gives the GPU test its expected
  values.

## FX-016-D7: Scene entry and settings

- **Decision**: `fx.lensDistortion` with `strength` (−1…1, fallback 0.3) and `zoomToFill` (0…1, fallback 1, ≥ 0.5 on),
  written only while on; `SceneEffectSettings.lensDistortion` is a property set after `init` (no init parameter, like
  FX-015), so the shared initialiser stays unchanged while FX-015 merges. Settings keys as in the spec's clarify
  session.
- **Rationale**: FX-020's rule; small, additive edits to shared files.

## FX-016-D8: No safety cap; no new motion

- **Decision**: no ACC-012 limit; the setting is static (no animation).
- **Rationale**: output values are convex combinations of input values or 0, so the warp adds no brightness; FX-019's
  flash guard still judges the shown frame. Nothing animates, so `MotionPolicy` is not involved.
