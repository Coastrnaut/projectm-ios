# Research: FX-017 Film grain

## FX-017-D1 — An own output pass, last in the chain

- **Decision**: `FilmGrainPass` with `cmp_film_grain`, one pooled `rgba16Float` picture, appended after Vignette as
  `fx.filmGrain`; source spliced at the existing compile site in `Compositor.init` and listed in
  `CompositorShaderSources.archived`.
- **Rationale**: grain is a texture over the finished picture; later blurs, warps or the mosaic would smear or enlarge
  it, and the vignette would darken its bright speckles away at the edges. FX-015 and FX-016 already prove the pattern
  (pool, order walk, Color folding, release rules).
- **Alternatives**: a step of the output pass (`cmp_output`): rejected, it would run on every output path (also with
  grain off) and change the archive key of the always-on pipeline; Core Image `CIRandomGenerator`: rejected, a second
  render path outside the pool and not exact across GPUs.

## FX-017-D2 — Integer PCG hash

- **Decision**: `pcg(v) = w' where s = v × 747796405 + 2891336453; w = ((s >> ((s >> 28) + 4)) ^ s) × 277803737;
  w' = (w >> 22) ^ w` (32-bit wrapping; Jarzynski and Olano's PCG hash). The grain value of channel ch at cell (cx, cy)
  is `h = pcg(cx + pcg(cy + pcg(frame + pcg(seed × 4 + ch))))` with wrapping additions; seed ≤ 9999, so seed × 4 + ch
  never collides between channels.
- **Rationale**: integer arithmetic is exact on every GPU and in Swift (`&*`, `&+`), so the noise is identical bit for
  bit; PCG has good avalanche at 2 multiplies per round. A floating-point `fract(sin(...))` hash differs between GPUs
  (sin precision) and is ruled out by the brief.
- **Alternatives**: xxHash32 (more operations, no gain at this use), a noise texture (allocation and a fixed pattern).

## FX-017-D3 — Noise and blend

- **Decision**: n = Float(h >> 8) × 2⁻²³ − 1 (exact, in [−1, 1), 2²⁴ values, mean −2⁻²⁴); scale = opacity × 0.08
  (Float, computed once on the CPU into the block); d = (scale × n) × alpha; out = max(c + d, min(c, 0)); alpha kept.
  Monochrome: one value for r, g, b (channel 0); colour: channels 0, 1, 2. The shader returns its input when scale is 0.
- **Rationale**: uniform zero-mean noise keeps the average brightness; additive in linear light is what the other
  output effects use; × alpha keeps premultiplied colour valid (no colour where alpha is 0); the floor keeps black from
  going negative without changing values that were already negative, and at d = 0 the expression is exactly c for
  every finite c. The 0.08 bound keeps the peak change small (no ACC-012 cap needed; the flash guard still measures the
  shown frame). With half-float output, a GPU may fuse the add into an FMA, so the output is compared within one
  half-float step; the noise itself is compared exactly (D5).
- **Alternatives**: multiplicative grain (c × (1 + d)): invisible in blacks and not zero-mean in absolute brightness;
  Gaussian noise (Box-Muller needs log/cos, not exact across GPUs).

## FX-017-D4 — Grain frame, rate cap and accessibility

- **Decision**: grain frame = 0 when static, Reduce flashing (the frame context's flag) or Reduce Motion (the app's
  effective value turns `animated` off) is on; otherwise UInt32(truncatingIfNeeded: presentationTimeNanoseconds ÷
  41 666 667). One step is at least 1⁄24 s of presentation time, so the grain changes at most 24 times a second whatever
  the display rate; the same presentation time always gives the same grain.
- **Rationale**: stateless and driven by CMP-001's injected clock, so tests and goldens are deterministic and no
  wall-clock is read. Reduce Motion: static grain rather than a halved rate, the conservative choice (ACC-001 treats
  continuous motion as optional); Reduce flashing: whole-frame texture changes at 24 Hz are a flicker, so they also
  stop, and the compositor applies it directly from the frame context (also on outputs the app does not reach).
- **Alternatives**: the compositor's frame index (rate would follow the display, 120 Hz strobing); a user rate control
  (more surface, no clear need).

## FX-017-D5 — CPU reference and exact GPU check

- **Decision**: `FilmGrain.hash`, `noise`, `referencePixel` and `reference` in plain Swift (Linux). The GPU test compiles
  `CompositorShaders.source + FilmGrainPass.source` plus a small test kernel that writes `cmp_grain_hash` and
  `cmp_grain_noise` for a grid of cells into a buffer, through the compositor's own `CompositorShaders.library` (safe
  math), and compares exactly. The test file is under `Tests/`, outside the compliance scan of app sources; the app
  compiles no new library.
- **Rationale**: half-float output alone cannot prove the noise is exact; reading the integers back does.

## FX-017-D6 — Settings and scenes

- **Decision**: keys `settings.filmGrain.enabled` (Bool, off), `.opacity` (0…1, 0.3), `.size` (1…3, 1), `.color`
  (Bool, false = monochrome), `.seed` (0…9999, 1), `.animated` (Bool, false); NaN → default, out of range → nearest,
  fractions rounded. Scene entry `fx.filmGrain` with `opacity`, `size`, `color` (0/1), `seed`, `animated` (0/1),
  written only while on.
- **Rationale**: the sibling effects' pattern (FX-015, FX-016); every key is in FILE-005's included list (a visual
  setting) and in the privacy allow-list.

## FX-017-D7 — Golden images

- **Decision**: besides the vignette-style scene tests (zero equals no chain, round trip), a stored golden of the
  plasma scene with grain (opacity 0.6, size 2, colour, seed 7, static) at both golden resolutions in
  `GeneratorGoldens/FilmGrain/<platform class>/`, compared with QA-002's rule and recorded with `GOLDEN_RECORD=1`.
- **Rationale**: the acceptance asks for stable snapshots; a stored image catches any change to the hash or the blend.
