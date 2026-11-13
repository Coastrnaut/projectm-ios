# Research: CMP-005 Transform Controls

Decisions taken by Claude under owner rule 4 (best judgement). The spec's Clarifications record the
product-level answers; this file records the technical ones.

## CMP-005-D1: Matrix convention

- **Decision**: For output aspect `a = width ÷ height` (pixels), `N = diag(a, 1)`, anchor `p₀`,
  move `t`, `L = R(θ)·S(sx, sy)` with `R(θ) = [[cos θ, −sin θ], [sin θ, cos θ]]`:
  `q = N⁻¹·(N·p₀ + L·(N·p − N·p₀)) + t`, i.e. the affine matrix `M = [[A, b], [0, 0, 1]]` with
  `A = N⁻¹·L·N = [[L₀₀, L₀₁ ÷ a], [L₁₀ · a, L₁₁]]` and `b = p₀ + t − A·p₀`. `p` and `q` are
  normalized (0…1, y down). Positive θ turns +x towards +y: clockwise on screen.
- **Rationale**: the anchor maps exactly to `p₀ + t` (CMP-005-R2); rotation happens in square units,
  so a quarter turn keeps pixel lengths on any aspect; with θ = 0, s = 1, t = 0 the formula yields
  exactly `A = I`, `b = 0` (cos 0 = 1, sin 0 = 0, `p₀ − 1·p₀ = 0` in IEEE arithmetic), so the
  identity holds for every anchor (CMP-005-R3). The matrix is computed element by element in this
  fixed order (no general matrix product), so equal inputs give bit-equal outputs on every host.
- **Alternatives**: a pixel-space matrix (the old placeholder: output-size dependent);
  rotation in normalized units (skews on non-square outputs); `simd_double3x3` (fine, but not on
  Linux without a shim, and the element order would be implicit).

## CMP-005-D2: Ranges and validation

- **Decision**: translation and anchor components clamped to −10…10, scale components to 0.05…20,
  rotation any finite value kept as given. Any non-finite component: `LayerTransformError`
  (`nonFiniteTranslation`, `nonFiniteScale`, `nonFiniteRotation`, `nonFiniteAnchor`) from the
  throwing initializer; nothing is stored. `isIdentity` = move 0, scale 1, rotation 0.
- **Rationale**: the MOD-001/CMP-003 convention (clamp finite, refuse non-finite). Scale ≥ 0.05
  keeps `det A = sx·sy ≥ 0.0025`, so the inverse is always well defined. ±10 is far beyond any
  useful placement (ten outputs away) yet keeps numbers small.

## CMP-005-D3: Saved form and exact round trip

- **Decision**: `Codable` with keys `version` (Int, must be 1), `translation` {x, y}, `scale`
  {x, y}, `rotation` (radians), `anchor` {x, y}. Encoding writes every field. Decoding requires
  `version == 1` (else `DecodingError.dataCorrupted` with "unsupported LayerTransform version"),
  reads missing fields as identity defaults, refuses non-finite values and clamps the rest.
- **Rationale**: Foundation's `JSONEncoder` writes a `Double` with the shortest representation that
  reads back to the same value, and `JSONDecoder` parses it back correctly rounded, so every finite
  double round-trips bit for bit (checked by test on 1,000 pseudo-random transforms with a fixed
  seed, plus edge values: −0, the smallest scale, values like 0.1 and π/7). The matrix is derived,
  not stored (spec Clarifications). Field names are SCN-001-ready: a scene's layer entry embeds the
  object unchanged.

## CMP-005-D4: Drawing a transformed layer

- **Decision**: a second fragment function `cmp_over_transformed` with the same vertex stage and
  blend state, taking `{ float4 row0; float4 row1; float opacity; }` by `setFragmentBytes`. The rows
  are the inverse matrix in **pixel** space, `P = D·M⁻¹·D⁻¹` with `D = diag(W, H)`, computed on the
  CPU in Double and rounded to Float once per draw. The fragment's `position.xy` is the output
  pixel's centre (x + 0.5, y + 0.5), so the source point in layer pixels is `src = P·(position.xy, 1)`. The picture is sampled at `src ÷ (W, H)` with a `constexpr sampler`
  (`filter::linear`, `address::clamp_to_zero`), then sanitized and multiplied by opacity exactly as
  `cmp_over`. Layers with `isIdentity` keep `cmp_over` (no pipeline change).
- **Rationale**: `clamp_to_zero` returns (0, 0, 0, 0) outside the texture, which is transparent in
  premultiplied alpha, so nothing smears; rgba16Float is filterable on every Apple GPU. The identity
  path stays bit-identical (CMP-005-R7). One extra pipeline state built at init, none per frame.
- **Alternatives**: a vertex-transformed quad (cheaper fill for small layers but needs a vertex
  buffer or more vertex logic; the full-screen triangle with clamp-to-zero is simpler and the cost
  difference is measured with CMP-002-T15); computing the inverse in the shader (per-pixel work and
  float precision for no gain).

## CMP-005-D5: Transform changes at apply

- **Decision**: each `LayerRecord` keeps the entry's `LayerTransform`; `apply` copies the entry's
  transform into kept records (equal stacks are still a no-op), new records start with theirs. No
  animation.
- **Rationale**: a transform-only edit then creates, prepares and releases nothing (CMP-005-R8), and
  the next frame shows it.

## CMP-005-D6: Not here

- Transform animation (modulation, keyframes): MOD/UIX rows.
- Mirroring: a later, explicit flip control.
- Aspect fitting of sources whose content is not output-shaped: CMP-006 builds on the matrix.
- Group transforms: CMP-011 composes matrices (`LayerTransformMatrix` multiply is provided).
