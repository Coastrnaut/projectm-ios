# ADR-0037: Blend Mode Colour Space

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: CMP-004 (`specs/099-cmp-004-blend-mode-library`)
- **Constitution**: VI (modular boundaries), X (evidence-based quality; an ADR for a default)
- **Builds on**: ADR-0013 (unified layer protocol: linear premultiplied `rgba16Float` pictures and
  composite), CMP-003 (opacity), CMP-005 (transforms), ADR-0028 (scene document: `composite.blend`)
- **Amends**: ADR-0013's composite contract gains blend modes; ADR-0028's list of drawn blend names

## Context

CMP-004 adds the blend modes add, screen, multiply, overlay and difference to normal. The compositor
stores pictures and the composite in linear light, premultiplied, and lets the output format encode
to sRGB. The W3C Compositing and Blending Level 1 equations do not fix a colour space, and the result
of screen, overlay and difference depends strongly on it: two 50 % greys screened in linear light
show about 66 % on screen instead of the 75 % every design tool and browser shows. Normal "over" has
always been linear here, and the existing goldens depend on it.

## Decision

1. **Equations**: W3C separable blend functions with source-over, premultiplied:
   co = cs·(1 − αb) + cb·(1 − αs) + αs·αb·B(Cb, Cs); αo = αs + αb·(1 − αs).
2. **Blend function in encoded space**: B runs on straight colours (unpremultiplied), clamped to
   0…1 and sRGB-encoded; its result is decoded to linear light.
3. **Coverage in linear light**: the source-over terms (the first two, and the weighting by alpha)
   stay in the compositor's linear premultiplied space with the unclamped values.
4. **Add** is the separable B = min(1, Cb + Cs) inside the same formula ("Linear Dodge (Add)"), not
   Porter-Duff plus.
5. **Normal keeps its path**: fixed-function premultiplied "over", unchanged; with B = Cs the formula
   reduces to it, so the definition is consistent.
6. **Drawing**: a non-normal layer reads the backdrop in a shader, drawing into a second pooled
   composite that then swaps with the first (no framebuffer fetch: the iOS Simulator and non-Apple
   GPUs lack it).

## Consequences

- Opaque results equal design tools and browsers for the same encoded colours; partial alpha mixes
  coverage in linear light like every normal layer here (a browser mixes it in sRGB).
- Normal-only stacks and every existing golden are bit-identical.
- Each non-normal layer costs one extra full-screen pass (at most eight layers).
- `LayerBlend` (plain Swift) is the reference the GPU tests compare against within 1e-3 linear and
  1/255 encoded.
- Values above 1 (bright glows) are clamped only inside B; where layers do not overlap they keep
  their brightness.

## Alternatives

- **Everything in linear light**: simplest, but screen, overlay and difference look nothing like the
  modes users know.
- **Everything in encoded space** (browser behaviour): would change every existing composite and
  golden and contradict ADR-0013's linear contract.
- **Porter-Duff plus for add**: alpha adds, unlike the other modes, and colour grows without bound in
  the half-float composite.
