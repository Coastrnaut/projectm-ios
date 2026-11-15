# Research: VIS-014 Kaleidoscope Field

- **VIS-014-D1 Source and reuse.** No kaleidoscope or mirror effect exists (FX-020 has only bloom; the mandala
  mirrors geometry). VIS-013's noise field is a procedural, smooth, band-driven picture with a reviewed compile
  site; folding its domain gives a kaleidoscope with no texture sampling. Decision: a fold mode of
  `NoiseFieldGenerator`. Alternatives: a new generator (second compile site, duplicated noise path); a post effect
  over any visual (needs an offscreen copy and edge handling; FX-020 chain is bloom-only today).
- **VIS-014-D2 Fold.** p = pixel − centre over the shorter side; θ = atan2(p.y, p.x) − rotation; w = 2π/N;
  a = θ − w·floor(θ / w) ∈ [0, w); φ = |a − w/2| ∈ [0, w/2]; folded = |p|·(cos φ, sin φ). φ is continuous in θ
  everywhere (the reflection's kink is at a = w/2, the wrap a = 0 ↔ w maps both to w/2), 2π is a multiple of w so
  atan2's ±π cut is invisible, and |p| → 0 maps every angle to the origin. Symmetries: θ → θ + w (rotation) and
  θ → 2·(rotation + k·w/2) − θ (mirror) leave φ unchanged.
- **VIS-014-D3 Turning.** spin target = 0.1 + 0.3 × low rad/s (≤ 0.4), one-pole τ 0.25 s on frame time,
  × 0.5 with Reduce Motion; rotation += spin × min(Δt, 1 s) on the injected clock, never backwards, wrapped to
  [0, 2π) (keeps Float precision on long sessions). The source drift, warp and brightness are VIS-013's.
- **VIS-014-D4 Seam measure.** For each boundary/axis angle α_k = rotation + k·π/N and radii 0.12…0.45 of the
  shorter side, sample the frame bilinearly at α_k ± δ (δ = 1.5 px / r) and at α_k; interior reference at
  α_k + π/(2N) ± δ. Mean |side difference| and mean |centre − sides' mean| must each be ≤ the interior mean.
- **VIS-014-D5 Symmetry measure.** Render 128 × 128 rgba16Float with 1 octave, frequency 2 (smooth source);
  for pixels with 0.08 ≤ r ≤ 0.45, compare with the bilinear sample of the rotated (2π/N) and mirrored point; mean
  abs difference ≤ 1/255; the other count's rotation must give ≥ 4 times that.
- **VIS-014-D6 Two entry points.** First tried: a `if (u.wedges >= 1.5)` branch inside `vis_noise_fragment`. The
  64 × 64 digests still matched, but the noise field's goldens showed 1 and 3 pixels changed by 1/255 (the compiler
  scheduled the plain path differently). Decision: a separate `vis_kaleido_fragment` entry point; the plain entry
  point's output is again identical to VIS-013's goldens.
