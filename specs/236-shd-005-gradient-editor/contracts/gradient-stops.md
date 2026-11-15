# Contract: SHD-005 gradient stops

## G1 Palette file (`projectm-ios.palettes`, version 1)
An entry MAY carry `"positions": [int…]`, `"alphas": [int…]`, `"interpolation": "srgb"|"step"`. Each is written only
when it differs from the default; a palette without detail encodes byte-identically to UIX-011. Invalid detail →
the entry is damaged (dropped, counted).

## G2 Evaluation (CPU and GPU)
For sorted stops s₀…sₙ₋₁ and t: t < p₀ → s₀; find the last i with pᵢ ≤ t; if i = n−1 → sₙ₋₁; else f = (t − pᵢ)/(pᵢ₊₁ − pᵢ):
Smooth = lerp(linᵢ, linᵢ₊₁, f); sRGB = decode(lerp(encᵢ, encᵢ₊₁, f)); Step = linᵢ; alpha = lerp(aᵢ, aᵢ₊₁, f) (Step: aᵢ).

## G3 Material layer
`ProceduralMaterialLayer.setGradient(_ ramp: GradientRamp?)` — only `material.gradient` reads it; nil (default)
draws the SHD-001 picture unchanged. Output premultiplied: (rgb × brightness × a, a).

## G4 App
Palette editor (gradient style, user palette): Interpolation picker `paletteInterpolationPicker`; per stop
sliders `paletteStop<i>.position` / `paletteStop<i>.alpha` (ACC-005, 1 % steps, spoken as percent); stop label
"Stop i of n, <colour name>".
