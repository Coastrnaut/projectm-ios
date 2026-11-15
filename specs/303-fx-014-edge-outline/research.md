# Research: FX-014 Edge Outline

All decisions by Claude under owner rule 4 (best judgement); 2026-11-15.

## FX-014-D1: Own pass, the FX-012 pattern

- **Decision**: `EdgeOutlinePass` with `cmp_edge_outline`, one pooled `rgba16Float` picture taken on the first active
  frame and returned when inactive, at a size change and with the compositor; the source is spliced after
  `MosaicPass.source` at the existing compile site and listed in `CompositorShaderSources.archived`.
- **Rationale**: an edge filter reads neighbouring pixels, so it cannot live in the per-pixel output pass; five effects
  proved the pattern. `CIColorKernel` (named in the roadmap row) is a per-pixel kernel and cannot read neighbours; a
  Core Image Sobel would need a second render stack and a new compile path.
- **Alternatives**: Core Image `CIEdges` / `CISobelGradients` (no exact threshold, own colour handling, a second
  context); a compute kernel (a second pipeline kind for no gain).

## FX-014-D2: Sobel on linear luminance

- **Decision**: luminance Y = 0.2126 R + 0.7152 G + 0.0722 B of the composite's linear premultiplied colour; Sobel
  Gx = (tr + 2 mr + br) − (tl + 2 ml + bl), Gy = (bl + 2 bm + br) − (tl + 2 tm + tr); strength = √(Gx² + Gy²) ÷ 4.
- **Rationale**: the value the chain carries; no transfer function in the pass (independent of FX-013's display
  stage); a 0 → 1 step gives strength 1 so the threshold reads as a contrast. Identical neighbours give identical
  luminance, so both sums are equal and the strength is 0.
- **Alternatives**: display-encoded luminance (perceptually even, but needs the encode function and couples to the
  output pass); per-channel maximum (colour edges at equal luminance; three times the work, harder to reason about).

## FX-014-D3: Threshold and soft mask

- **Decision**: mask = smoothstep(t, t + 0.1, strength), t in 0.02…1 (default 0.2); a non-finite strength gives 0.
- **Rationale**: exact 0 at or below the threshold (the "threshold above contrast → nothing" rule is exact); a short
  fixed band softens aliasing on soft edges; the lower bound 0.02 is far above any rounding residue.
- **Alternatives**: a hard step (aliased lines on gradients); a user-set softness (one more control for little gain).

## FX-014-D4: Overlay keeps the input exactly where the mask is 0

- **Decision**: overlay returns the input pixel unchanged when the mask is 0, else mix(input, colour, mask) with the
  outline colour opaque (alpha 1). Outline only: mix(opaque black, colour, mask).
- **Rationale**: flat pictures are bit-identical in overlay by construction, not by arithmetic luck.

## FX-014-D5: Width by tap distance, clamped taps

- **Decision**: taps at ±width pixels (1…3), each clamped to [0, size − 1].
- **Rationale**: one rule, nine reads whatever the width; a step is outlined on 2 × width pixels; clamping makes the
  border of a flat picture flat (no frame edge outline).
- **Alternatives**: dilating a 1-pixel mask (needs a second pass or 9 × 9 reads).

## FX-014-D6: Colour, CPU reference and ACC-012

- **Decision**: colour stored as sRGB hex; converted once on the CPU to linear (IEC 61966-2-1 piecewise) and passed in
  the 32-byte block; under an intensity limit below 1 the linear colour is multiplied by the limit (ACC-012-R4, as
  FX-010 scales Echo's weight). The CPU reference uses the same formula in Float; tests compare masks (outlined or not)
  and exact pixels on exactly representable pictures.
- **Rationale**: the outline is the only part of this effect that can add brightness; the flash guard still judges the
  frame (FX-019).

## FX-014-D7: Scene entry in its own file

- **Decision**: `SceneEffectChain+EdgeOutline.swift` holds the parameters and the read/write rules (one case per switch
  in `SceneEffectChain.swift`); `SceneSourceSafetyTests` lists the new file.
