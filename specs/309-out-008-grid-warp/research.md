# Research: OUT-008 Grid Warp

- **OUT-008-D1 Where the warp happens.** Decision: in the held visual's own final pass, like OUT-009's calibration:
  the compositor's screen pass (`composite(into:)`) and projectM's FX-019 output step. The external slot hands the mesh
  to its visual's view when that view is an `OutputWarpReceiver`; the device slot and a visual leaving a slot get
  `.none`. Rationale: OUT-007 used Core Animation's projective `sublayerTransform`, but a mesh is not projective and
  Core Animation's mesh transform is not public API (Constitution I). Capturing an arbitrary layer's pixels and redrawing
  them is not possible with public API for a `CAMetalLayer` without a second render path. Recordings (`encodeOutput`,
  REC-003 taps) and captures read content, not the screen pass, so they stay unwarped by construction. Alternatives:
  CAMeshTransform (private; rejected), a per-visual offscreen copy and a slot-level warp layer (a second render path
  for six hosts and the engine; rejected), CA replicator/tiles (cannot show different parts of one Metal layer;
  rejected). Consequence: the native spectra (no shared final pass) are not covered, as in OUT-009.
- **OUT-008-D2 Interpolation.** Decision: uniform Catmull-Rom in u and v (tensor product), phantom points
  P₋₁ = 2P₀ − P₁ and Pₙ = 2Pₙ₋₁ − Pₙ₋₂ at the borders. It passes through every control point (weights (0, 1, 0, 0) at
  t = 0), is C¹, and reproduces affine grids exactly, so the identity maps every point to itself. Bilinear: creases at
  grid lines (rejected); B-spline: does not pass through the handles (rejected); bicubic with estimated derivatives:
  more parameters to validate (rejected).
- **OUT-008-D3 Drawing the surface.** Decision: a fixed tessellation of 16 × 16 quads (two triangles each) per control
  cell, generated in the vertex shader from `vertex_id` (no vertex buffer): vertex → lattice (i, j) → (u, v) =
  (i / (16·cellsX), j / (16·cellsY)) → position = surface(u, v); the fragment samples the source picture at the
  interpolated (u, v) with bilinear filtering, clamp-to-edge. Uncovered pixels are cleared to opaque black first. The
  CPU validator uses the same lattice, so the triangles it checks are the triangles drawn. 16 per cell keeps the
  piecewise-linear error below about 0.1 % of the picture for the allowed curvature; 9 × 9 points draw 128 × 128 quads
  (98 304 vertices), trivial for the GPU.
- **OUT-008-D4 Validity (no fold).** Decision, in this order (first failure is the reason): `badSize` (columns or rows
  outside 3…9, wrong point count), `nonFinite`, `outOfRange` (−0.5…1.5), `cellFolded` (a control cell's turn is ≤ −sine
  limit, i.e. concave, crossed or mirrored), `cellDegenerate` (a turn's sine below 0.035 ≈ 2°, or coincident points),
  `surfaceFolds` (a drawn triangle's signed area ≤ 1e-9 in the identity orientation), `outlineCrosses` (two non-adjacent
  segments of the drawn outline intersect), `tooSmall` (drawn area < 5 %). A triangulated disk whose triangles all keep
  their orientation and whose boundary is a simple curve is mapped one-to-one, so an accepted mesh never overlaps
  itself. The control-cell rules give the editor clear early reasons; the surface rules catch Catmull-Rom overshoot.
- **OUT-008-D5 Compositor pass.** Decision: when `outputWarp` is set, the screen pass draws into a pooled picture of the
  output's size and format, then `GridWarpPass` (pipeline per output format, created on first use) draws that picture
  through the mesh into the drawable. Everything before (flash guard, grade, tone map, dither, OUT-009 calibration) is
  unchanged, so the warp only moves finished display pixels. The MSL is a module constant appended to
  `CompositorShaders.source` (the existing reviewed compile site; it is therefore in the PERF-009 archive key). The
  picture returns to the pool when the warp turns off. `.none` encodes exactly the old pass.
- **OUT-008-D6 FX-019 step.** Decision: `PMFlashLimiterSetWarp(limiter, columns, rows, points, guides)` stores up to 81
  points; while set, the output step clears the target to black and draws the mesh with a second program (same
  fragment maths, warp vertex shader, optional guides) instead of the full-screen triangle. `PMFlashLimiterDrawOutput`'s
  "display" flag now means calibrated and warped, so REC-001 captures (drawn with the flag off) are content. GL
  coordinates: picture (u, v) y-down → scene texcoord (u, 1 − v); output (x, y) y-down → NDC (2x − 1, 1 − 2y).
- **OUT-008-D7 Guides.** Decision: while the editor is open the warp pass draws 1.5-pixel white lines where the
  sampled (u, v) lies on a control grid line (distance measured with screen-space derivatives), on top of the picture.
  This is the calibration pattern (OUT-007 used a test-card layer, which a mesh inside the visual cannot bend).
- **OUT-008-D8 Storage.** Decision: `settings.externalDisplay.gridWarp` = "C×R:" (as `CxR:`) followed by the points
  row by row, `x,y` separated by `;`, six decimals. Identity removes the key; a missing, malformed or invalid value reads
  as the identity. OUT-014: optional `"gridWarp": {"columns", "rows", "points": [{"x","y"}]}`, written only when not
  the identity; an invalid one refuses the import (`settings.gridWarp`).
- **OUT-008-D9 Editor.** Decision: a full-screen cover like the corner-pin editor: the display's shape, the warped grid
  (sampled surface lines), one 44 pt handle per control point (drag; VoiceOver element "Row 2, column 3" with a spoken
  value and Move left/right/up/down actions), a grid-size picker (3 × 3, 5 × 5, 9 × 9; resample else identity), a point
  picker (row and column steppers) with four nudge buttons (0.005), Reset, Done, and the last refusal's reason in red
  text (announced through `AccessibilityAnnouncer`).
