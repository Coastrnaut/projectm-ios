# Research: SHD-006 Noise Editor

## SHD-006-D1 — Where the parameters live
- **Decision**: Noise Flow's SHD-003 metadata (slots 6-10), `octaves` widened to 1…8.
- **Rationale**: one parameter mechanism (registry, controls, scenes, slot check); the material already draws fBm
  with a warp, so the new parameters replace its literals.
- **Alternatives**: a new material (8-parameter cap forces dropping scale/tint/brightness); a second uniform block
  like SHD-005's ramp (bypasses metadata, needs a second storage path).

## SHD-006-D2 — The parameter cap
- **Decision**: 16 for every material; `MatUniforms` holds 16 `float4` (272 bytes, `setFragmentBytes` limit 4 KB).
- **Rationale**: smallest change that keeps "parameter i is slot i"; no material's existing picture changes.
- **Alternatives**: per-slot packing (`component` key) breaks the slot model in values, controls and the scan.

## SHD-006-D3 — Seeded hash
- **Decision**: integer lattice hash. `cell & 4095` per axis (24 bits) XOR `key · 0x9E3779B9`, key = seed |
  octave << 16 | field << 19 (field 0 = noise, 1/2 = warp x/y), then the "lowbias32" finalizer
  (`x ^= x >> 16; x *= 0x7FEB352D; x ^= x >> 15; x *= 0x846CA68B; x ^= x >> 16`), value = `(x >> 8) / 2²⁴`.
- **Rationale**: exact on every GPU and the CPU (integer ops), independent of coordinate magnitude, seeds give
  distinct masks (multiplication by an odd constant is a bijection), period 4096 cells is far beyond the view.
- **Alternatives**: offsetting the domain by a seed-derived translation (the old float hash degrades at large
  coordinates; seeds would only translate the same field).

## SHD-006-D4 — fBm and warp
- **Decision**: `fbm(q) = Σᵢ gainⁱ · noise(qᵢ, key(seed, i, field)) / Σᵢ gainⁱ`, `qᵢ₊₁ = qᵢ · lacunarity + (17.1, 9.2)`,
  up to 8 octaves. Warp: `wq = q · warpFrequency`, `w = (fbm(wq + (3.1, 7.7), field 1), fbm(wq + (8.3, 2.8), field 2))`,
  `n = fbm(q + warpAmount · (w − 0.5), field 0)`; warp skipped when the amount is 0. Low cost: `n = fbm(q)` with
  ≤ 3 octaves.
- **Rationale**: standard fBm (normalised so brightness does not depend on octaves or gain); 2-D warp avoids the
  old diagonal-only shift.

## SHD-006-D5 — Stable reference per GPU class
- **Decision**: FNV-1a 64 of the raw rgba16Float readback (64 × 64) per `MTLDevice.name`, three settings; plus a
  tolerant signature (±0.02) valid on any GPU. Unknown device name → the exact check is skipped with the digest
  printed.
- **Rationale**: bit identity is only promised on the same GPU class (roadmap acceptance); a tolerant golden still
  catches regressions on CI's paravirtual GPU.

## SHD-006-D6 — Monotonic measures
- **Decision**: high-frequency energy = mean |L(x+1,y) − L(x,y)| + |L(x,y+1) − L(x,y)| of the noise value n over a
  128 × 128 CPU-reference grid (and on the GPU picture for octaves); warp distance = mean |n_warp − n_nowarp|.
- **Rationale**: neighbour differences grow with finer, stronger detail; measured on the CPU reference (exact,
  Linux) and spot-checked on the GPU.

## SHD-006-D7 — Editor placement and preview
- **Decision**: Settings › Noise editor; preview by `MaterialPreviewRenderer` (one frame at phase 0 into a
  256 × 256 rgba16Float picture, read back, encoded to sRGB with FrameCapture's conversion).
- **Rationale**: material layers are not drawn by the visualizer yet, so the preview is the visible result; using
  the layer's own pipeline makes the preview the same code the tests pin.

## SHD-006-D8 — Randomize seed
- **Decision**: `NoiseSeedSequence`: counter c (from 1), seed = lowbias32(c) & 0xFFFF; skip the current seed.
- **Rationale**: deterministic, testable without a system RNG.
