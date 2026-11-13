# Research: FX-001 Bloom

Decisions are numbered `FX-001-D1…` so they never collide with feature 001's `R-xx` research
entries. Each records the decision, the rationale and the alternatives considered.

## FX-001-D1 Where the effect code lives

- **Decision**: a third target, `VisualEffects`, in `Packages/VisualGenerators`, added to the
  package's single library product. It depends only on the `VisualGenerators` target. Tests join
  the existing `VisualGeneratorsTests` target.
- **Rationale**: the roadmap prefers extending packages over new ones; the product name, CI's five
  package loops (`-scheme VisualGenerators`, `swift test`) and `project.yml` stay as they are, so no
  shared file changes while ANL-004 is in flight; effects stay independent of the circular spectrum,
  so CMP-001 can move the target into `Packages/Compositor` (or depend on this package) unchanged.
- **Alternatives**: a new `Packages/Compositor` now (five CI loops, `project.yml`, no gain until
  CMP-001); effects inside `CircularSpectrumGenerator` (not reusable by CMP-001); Core Image
  (`CIFilter.bloom`/`CIColorKernel`, see D2).

## FX-001-D2 Metal passes instead of Core Image

- **Decision**: four Metal passes with shader source compiled at runtime from a package constant
  (VIS-001-R17, ADR-0009 decision 3): three compute passes (threshold + downsample, horizontal
  blur, vertical blur) on private `rgba16Float` textures, then one render pass (composite) into the
  output, which may be a `framebufferOnly` drawable.
- **Rationale**: the acceptance needs exact statements (exact black, a finite halo extent, exact
  pass-through, bit-identical reruns). Core Image's bloom uses its own Gaussian with unbounded
  extent rules, its own working color space and tiling, and an `CIColorKernel` covers only the
  per-pixel threshold; with Core Image the halo extent and energy are not ours to bound, and its
  context renders into drawables through its own command buffers. Our passes use only `read` with
  explicit zero padding, so every bound is provable from the shader text.
- **Alternatives**: `CIFilter.bloom()` (unbounded/unspecified extent, no threshold), MPS
  `MPSImageGaussianBlur` (edge mode `.zero` exists, but MPS kernels are unavailable on some
  simulators and its tap count is internal), a mip chain with tent upsampling (fine for looks, harder
  to bound exactly; revisit for PERF-003).

## FX-001-D3 The bloom algorithm and its bounds

Inputs: input image `I` (W × H, linear premultiplied RGBA), parameters intensity `k ∈ [0, 1]`,
radius `ρ ∈ [0.005, 0.06]`, threshold `T ∈ [0.1, 1]`, knee fraction `κ ∈ [0, 1]`, `K = κ·T`.

1. **Threshold (soft knee)**, per pixel, with `b = max(r, g, b)` of the sanitized pixel (NaN/∞ → 0,
   negatives → 0, values capped at 64): `s = clamp(b − T + K, 0, 2K)`, `s = s² / (4K + 1e-5)`,
   `w = max(s, b − T) / max(b, 1e-5)`, `P = I · w` (all four channels). For `b ≤ T − K`, `w = 0`
   exactly (FX-001-R6). `0 ≤ w ≤ 1`, so `P ≤ I` per channel.
2. **Downsample by D** ∈ {2, 4, 8}, the smallest with `ceil(ρ·min(W, H) / D) ≤ 16`; `R =
   clamp(round(ρ·min(W, H) / D), 1, 16)`. Reduced size `w = ceil(W/D)`, `h = ceil(H/D)`. Reduced
   texel = the sum of `P` over its D × D block (pixels outside the image read 0) divided by D².
3. **Separable Gaussian**, `σ = R / 2`, taps `−R…R` (at most 33), weights normalized to sum 1 on the
   CPU, texels outside the reduced image read 0.
4. **Composite**: `O = I + k · G`, where `G` is the bilinear interpolation of the blurred reduced
   image at `u = (x + 0.5)/D − 0.5` (texels outside read 0), with `O.a = min(1, I.a + k·G.a)`.

Bounds (each is a test):

- **Exact black**: `I = 0` ⇒ `P = 0` ⇒ `G = 0` ⇒ `O = 0` (no constant term anywhere).
- **Extent**: a contributing pixel at index `s` reaches reduced texel `⌊s/D⌋`; the blur moves it at
  most `R` texels; bilinear reads texels `x0, x0 + 1` with `x0 = ⌊(p + 0.5)/D − 0.5⌋`. Solving both
  sides gives `|p − s| ≤ (R + 1.5)·D + 0.5 < (R + 2)·D` per axis. **Halo extent `E = (R + 2)·D`
  pixels (Chebyshev distance)**; any pixel at distance ≥ E from every contributing pixel equals the
  input (exactly for `rgba16Float`; within the 8-bit sRGB round trip, at most 1/255, for
  `bgra8Unorm_srgb`; exactly black where the input is black).
- **Not brighter than the patch**: `G` is a convex combination (weights ≥ 0, sum ≤ 1) of `P ≤ I`
  values, so outside the patch `O = k·G ≤ max I` for `k ≤ 1`.
- **Monotone**: for a rectangle the whole pipeline is separable; each 1-D factor is a block-coverage
  sequence (log-concave) convolved with a truncated Gaussian (log-concave) and linearly
  interpolated, hence unimodal with its mode inside the patch: it does not increase moving away.
- **Energy**: the block sum, the normalized blur with zero padding and the bilinear enlargement
  (each reduced texel's tent weights sum to D² over the image interior, less at the borders) never
  add energy, so `Σ(O − I) ≤ k · Σ P` (per channel, so also for luminance).
- **Identity**: `k = 0` or disabled ⇒ the effect is pass-through: the chain skips it; a direct
  `encode` copies (blit when the output is not `framebufferOnly`, else a copy render pass).
- **Determinism**: fixed pass order, fixed weights computed once per parameter change, no atomics,
  no randomness, `read` only (no sampler filtering) ⇒ identical bits on the same device.

## FX-001-D4 Reduce flashing sees the glow (exact CPU model)

- **Decision**: `VisualGenerators` gains a protocol `FrameLuminanceTransfer` ("the mean relative
  luminance a flat region of this pixel color contributes after the downstream effects") and the
  generator an optional `downstreamLuminance`. For bloom, `T(c) = Y(c) + k·Y(P(c))` (Y = Rec. 709
  relative luminance, P the threshold of D3), an upper bound by the energy bound of D3. When set,
  the generator's mean luminance at gain g is `Σ area_k/A · T(g·α_k·c_k + (1 − α_k)·bg) +
  (uncovered/A) · T(bg)`, nondecreasing in g, and `FlashSafetyLimiter.gain(frameTime:enabled:
  luminanceAtGain:)` picks the largest feasible g by 24 bisection steps (precision 6e-8; no
  allocation; a non-escaping closure). With no downstream model, the VIS-001 path is unchanged.
- **Rationale**: the limiter's bound then holds on the composited picture (FX-001-R10). Errors of
  the model only go one way (energy lost off-frame or clamped at 1.0 on an 8-bit target is light not
  shown), and they change slowly under the limiter; the GPU test measures the composited frames.
- **Alternatives**: a `(1 + k)` multiplier (actual luminance can jump when bars cross the threshold),
  a GPU read-back (a frame late, stalls), limiting in the bloom pass (the bloom cannot see the
  previous frame's luminance without a reduction pass; FX-019 may add one).

## FX-001-D5 Parameter ranges and defaults

- Intensity 0…1, default 0.5: capped at 1 so the halo never outshines its source (D3).
- Radius 0.005…0.06 of the shorter side, default 0.02: about 24 px on an iPhone 15 at full scale,
  up to 71 px; the tap budget (16 per side at D ≤ 8) covers 0.06 up to a 2,133 px shorter side
  (iPad Pro 13" is 2,064 px).
- Threshold 0.1…1.0, default 0.7; knee fraction 0…1, default 0.5 (not shown in Settings).
- Glow off by default (Clarifications).
- Clamping: out of range → nearest bound; NaN → default. Shared by the app's settings and the
  chain description's decoder.

## FX-001-D6 Chain description for FX-020

- **Decision**: `EffectChainDescription { formatVersion: 1, effects: [EffectDescription] }`, where an
  `EffectDescription` encodes as `{"id": "fx.bloom", "parameters": {...}}`. Unknown identifiers are
  kept as `.unknown(id)` and skipped when building a chain (forward compatibility); a newer
  `formatVersion` fails decoding. The app does not store a chain yet: the four glow settings are the
  user's controls and map to a one-effect chain.
- **Alternatives**: persisting the chain JSON in UserDefaults now (FX-020 and SCN rows own scene
  documents).

## FX-001-D7 Failure boundary and test hook

- **Decision**: the host builds the bloom effect when it is created; a failure leaves the host
  rendering without glow and sets `glowUnavailable`. Settings shows "Glow isn't available on this
  device." (`glowUnavailableFooter`) and VoiceOver announces it when the user turns Glow on. DEBUG
  launch argument `-uitestGlowFailure` forces the failure. The circular spectrum view's
  accessibility value reports "Glow on", "Glow off" or "Glow unavailable" so UI tests can see the
  state without pixels.

## FX-001-D8 Frame path and resources

- Intermediate textures (`EffectChain`'s source image in the output's format; bloom's reduced and
  blur images in `rgba16Float`, `.private`) are created by `prepare(width:height:)` only when the
  size or format changes; per frame nothing is created (uniforms go through `setBytes`, Metal's
  per-encoder inline data). Successive command buffers on one queue run in order, so reusing the
  intermediates each frame needs no extra synchronization.
- Glow off (or intensity 0): the chain has no active effect and the generator draws straight into
  the drawable, exactly as VIS-001 (FX-001-S7).
- PERF-003 (adaptive quality) can lower `D` or `R` through the same plan; PERF-004 (texture pool)
  can replace `prepare`'s allocations; FX-019 can read the same luminance transfer for its envelope.
