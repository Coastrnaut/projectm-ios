# Research: FX-015 Vignette

- **FX-015-D1 — Own output pass, not a grade step.** Decision: `VignettePass` with `cmp_vignette`, a module constant
  appended at `Compositor.init`'s reviewed compile site and in `CompositorShaderSources.archived`; one pooled
  `rgba16Float` picture. Rationale: last in the chain, later spatial effects do not smear the falloff; it is
  reorderable and switchable like FX-006 to FX-012; the shared 96-byte grade block is untouched. Alternatives: a step in
  `cmp_grade_at` (FX-013 made it position-aware): fewer files, but it would sit at Color's place, blurred by the later
  passes, and grow the grade block every output path binds; Core Image `CIVignette` / a `CIColorKernel`: a second
  render path outside the compositor's pool and order, rejected.
- **FX-015-D2 — Falloff shape.** Decision: an ellipse following the frame: d = |((P − C) ÷ (W/2, H/2))| ÷ √2, so the
  frame's corners are at d = 1 from its middle. Alternatives: a circle in pixels (sides of a portrait phone barely
  darken); a circle in the shorter side (corners clip hard).
- **FX-015-D3 — Weight.** Decision: inner = 1 − softness, t = clamp((d − inner) ÷ softness, 0, 1),
  w = t² (3 − 2t), written out (not Metal's `smoothstep`) so the CPU reference uses the same steps. softness 0.1…0.9,
  so the clear core (w = 0 exactly) is at least d < 0.1 and the band never divides by zero.
- **FX-015-D4 — Darken only.** Decision: rgb × (1 − intensity × w), alpha kept, in linear premultiplied light.
  The factor is in [0, 1], so colour never rises, premultiplied colour stays ≤ alpha, finite stays finite, and exactly
  1 where w = 0 (x × 1 = x in IEEE arithmetic): the centre is bit-exact at any intensity. Intensity 0 runs no pass.
- **FX-015-D5 — Block and reference.** `CMPVignette { float2 centre; float2 scale; float inner; float softness;
  float intensity; float pad; }` (32 bytes) with scale = (2 ÷ W, 2 ÷ H) ÷ √2 precomputed on the CPU; the CPU reference
  computes the same Float expressions. GPU and reference agree within half-float rounding (the GPU may fuse
  multiply-adds), so the tests compare with a 2⁻⁹ relative tolerance except where the factor is exactly 1.
- **FX-015-D6 — Settings and scene entry.** Five keys `settings.vignette.{enabled,intensity,softness,centerX,centerY}`
  (Bool and four Doubles; absent or malformed → default, out of range → nearest bound), included in FILE-005 backups
  as visual settings. Scene entry `fx.vignette` with `intensity`, `softness`, `centerX`, `centerY`, written only while
  on, in a new `SceneEffectChain+Vignette.swift` (one case per switch in the shared file).
- **FX-015-D7 — Safety.** No ACC-012 cap: the effect only darkens; the flash guard judges the shown frame.
