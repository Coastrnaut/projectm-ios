# Research: CMP-008 Gradient Masks

## CMP-008-D1: Evaluation rule and monotonicity

- **Decision**: alpha(t) = a₀ for t ≤ p₀; a_last for t ≥ p_last; otherwise, for the first segment
  i with pᵢ₋₁ < t < pᵢ, aᵢ₋₁ + (aᵢ − aᵢ₋₁)·(t − pᵢ₋₁)/(pᵢ − pᵢ₋₁). Walk the sorted stops from the
  start; a stop at or before t sets alpha to its own value, the first stop after t interpolates with
  its predecessor and stops the walk. Equal positions give a hard step (the later stop wins at and
  after the position).
- **Rationale**: linear interpolation between two values is monotonic by construction, which is the
  row's acceptance; clamping outside matches CSS/SVG `pad` spread and keeps alpha in 0…1. The same
  loop in Swift (Double) and Metal (float) keeps CPU and GPU within float rounding (< 1e-6 in alpha
  for t in 0…1), far below the 1/255 tolerance.
- **Alternatives**: smoothstep between stops (not what "stops" means in common tools; still monotonic
  but surprising); repeat/reflect spread (not asked; can be a later kind).

## CMP-008-D2: Geometry units

- **Decision**: linear start/end in layer fractions (pixels = fraction × W or H); t = ((p − s)·(e − s))
  / |e − s|² in pixels. Radial centre in layer fractions, radius × min(W, H) pixels; t = |p − c| / r.
- **Rationale**: endpoints in fractions follow the layer at any size (a left-to-right gradient stays
  left-to-right); the radial radius in shorter-side units keeps circles round, as CMP-007's shapes.
  Projection in pixels keeps a diagonal gradient's isolines perpendicular on screen.
- **Alternatives**: the CMP-007 mask transform (centre/scale/rotation) for gradients too: more
  parameters than a gradient needs and a second meaning of "scale".

## CMP-008-D3: Shader block and routing

- **Decision**: append `float4 grad; float4 axis; float2 stops[8];` to `CMPMask` (304 → 400 bytes;
  Swift `MaskBlock` mirrors it with SIMD4 fields and a 4-SIMD4 tuple). Kind 0 in `grad.x` = no
  gradient; shape kind 0 = no shape; `cmp_mask_coverage` multiplies the two factors and returns exactly
  1 when both are absent. A layer with only a gradient uses the same masked routes as CMP-007 (normal:
  `cmp_over_masked` in the open pass; other modes: `cmp_blend`).
- **Rationale**: no new pipeline or pass; unmasked layers untouched; one cached block per record.
  Swift layout: 3 × 16 + 256 = 304, then three 16-byte-aligned fields: 304 + 16 + 16 + 64 = 400, equal to
  MSL's layout (float2 arrays pack at 8 bytes; float4 at 16).
- **Alternatives**: a second buffer index for the gradient (more bindings in two pipelines for no gain).

## CMP-008-D4: Scene storage

- **Decision**: `composite.gradientMask`: `{"kind": "linear", "start": {x,y}, "end": {x,y}, "stops":
  [{"position", "alpha"}…]}` or `{"kind": "radial", "center": {x,y}, "radius", "stops": […]}`; every
  field written; unknown kinds kept verbatim with the existing `unsupportedMaskShape` warning;
  `valueClamped` for clamped values and re-sorted stops; `droppedField` for unknown keys, a bad stop
  count or a zero-length linear gradient.
- **Rationale**: mirrors CMP-007 so SCN-012 and QA-004 need no change; reusing the warning kind avoids
  touching the exhaustive issue switches other features also edit.

## CMP-008-D5: Golden

- **Decision**: generator-level golden pattern (as VIS-007): a 1 × 1-style solid layer source written in
  the test (clear to a colour), a gradient in the compositor, captured with `requestFrameCapture` and
  `FrameColorConversion.rgba8`, compared with QA-002's rule per platform class; goldens in
  `GeneratorGoldens/GradientMask/<class>/`, two runs (`gradient-mask-linear`, `gradient-mask-radial`),
  both QA-002 resolutions.
- **Rationale**: avoids adding a scene to the QA-002 suite (its catalog and decision table are shared)
  while still covering the shader on the host and the simulator.

## CMP-008-D6: Inspector editing

- **Decision**: rules in a plain enum (`LayerGradientEdit`) over `SceneComposite`; the view only binds.
  Angle: θ = atan2(Δy, Δx) of end − start in layer fractions; setting it keeps the midpoint and the
  length in fractions. Stop sliders use ACC-005 with identifiers `layerControl.gradientStop<n>.position`
  and `.alpha`; history keys `layer.<kind>.gradientStop<n>.<field>` coalesce a drag. Moving a stop past
  its neighbour re-sorts; the edited stop's index can change, ending that drag's coalescing (accepted).
- **Rationale**: matches CMP-015's split of model and view and keeps the type checker happy.
