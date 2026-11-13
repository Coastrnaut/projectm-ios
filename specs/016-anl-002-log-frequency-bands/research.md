# Research: ANL-002 Log-frequency Bands

Decisions are numbered `ANL-002-D1…`. Each lists the decision, the rationale and the alternatives
considered. Spec clarifications of 2026-11-13 summarize D1 to D4, D6 and D7.

## ANL-002-D1: Logarithmic scale, 20 Hz to min(20 kHz, Nyquist)

- **Decision**: Edge i of B bands = `20 · (upper / 20)^(i/B)`, upper = min(20,000, R/2). At 44.1 and
  48 kHz upper = 20 kHz, so the ratio per band is 1000^(1/B): 1.540 (16 bands, 0.62 octave),
  1.241 (32), 1.114 (64), 1.055 (128, about 1/13 octave).
- **Rationale**: The row is "Log-frequency bands". Equal ratios give equal band counts per octave
  (musical intervals and pink noise read evenly), the formula is closed-form so consumers and tests
  recompute it, and 20 Hz to 20 kHz is the conventional audible range.
- **Alternatives**: Mel (`2595·log10(1 + f/700)`) and Bark: closer to critical bands, but near-linear
  below ~700 Hz and with differing published constants; they would contradict the row title.
  Starting the bands at the first bin instead of 20 Hz: the band edges would depend on the FFT size,
  so a kick detector's band would move when the size changes.

## ANL-002-D2: Bins as intervals, overlap weights, DC excluded

- **Decision**: Bin k (1 ≤ k < N/2) covers `[(k − ½)Δ, (k + ½)Δ]`, Δ = R/N; bin 1 covers `[0, 1.5Δ]`;
  the Nyquist bin covers `[(N/2 − ½)Δ, N/2·Δ]`; bin 0 (DC) covers nothing. The weight of bin k in
  band b is `|[lo_b, hi_b] ∩ interval_k| / |interval_k|`. Weights of one bin over all bands sum to the
  fraction of its interval inside 20 Hz…upper (≤ 1), so no energy is counted twice.
- **Rationale**: A piecewise-constant power density is the simplest model that splits a bin at a band
  edge in proportion, is exact for wide bands, and gives every band some bin (no empty band). DC is
  an offset, not audio; extending bin 1 down to 0 Hz keeps the lowest bands populated at 512 and
  1,024 points, where 20 Hz is below half a bin (Δ/2 = 43 Hz and 21.5 Hz at 44.1 kHz).
- **Alternatives**: Nearest-bin assignment (each bin to the band containing its centre): narrow bands
  get no bin and are empty. Triangular (mel-style) filters: overlapping bands, same empty-band
  problem at small N, harder to state. Interpolating the magnitude at band centres: ignores energy in
  wide bands.

## ANL-002-D3: Energy sum normalized by the Hann ENBW

- **Decision**: `value_b = sqrt( Σ_k w_bk · m_k² · s_b )` with `s_b = 1 / (1.5 · min(1, W_b))`,
  W_b = Σ_k w_bk (band width in bins).
- **Rationale**: ANL-001 scales a bin-centred sine of amplitude A to read A at its bin; with the
  periodic Hann window the neighbours read A/2, and for any tone position the sum of bin powers is
  A² times the window's equivalent noise bandwidth, 1.5 bins (Parseval). Dividing by 1.5 makes a sine
  anywhere inside a wide band read A: the band value is the amplitude of the sine that carries the
  band's power. Additive power suits ANL-007 (bass energy) and MOD-015.
- **Alternatives**: Mean magnitude (RMS over bins): a tone in a 100-bin band would read A/10. Peak:
  not additive, ignores spread energy.

## ANL-002-D4: Sub-bin bands scaled to one bin

- **Decision**: For W_b < 1, the scale uses W_b instead of 1 (`min(1, W_b)`), so the band reads the
  weighted mean power of the bins it touches, divided by 1.5.
- **Rationale**: Without it a band 0.06 bins wide (128 bands at 512 points near 100 Hz) would read
  √0.06 ≈ 0.25 of its neighbour only because it is narrow: visual bars would sag at the low end at
  small sizes. With it, neighbouring narrow bands inside one bin read the same value — the true
  resolution of that FFT size — and the scale is continuous at W_b = 1.
- **Consequence**: Band powers no longer sum to the total power where bands are narrower than a bin.
  Documented in the contract; ANL-007 and ANL-009 read wide-enough bands or sum powers themselves.

## ANL-002-D5: Table layout and the per-frame path

- **Decision**: Per layout, flat arrays: `firstBin[B]`, `binCount[B]`, `offset[B]`, `weights[total]`,
  `scale[B]` (Float). The reducer holds all 20 layouts of its rate and a 4,097-Float power scratch.
  Per frame: one pass `p_k = m_k²` (m sanitized: non-finite or ≤ 0 → 0, clamped to 1e15 so the square
  and sums stay finite), then per band a dot product of its weights with `p[firstBin…]` — `vDSP_dotpr`
  on the accelerated path, an ordered Float loop on the portable one — times `scale`, `sqrt`, and a
  finite guard. Total weight entries ≤ bins + 2·B.
- **Rationale**: One square pass shared by all bands; each band is a contiguous dot product, which
  vDSP does well and the portable loop does deterministically. Precomputing all counts and sizes
  (about 25,000 Floats in total at one rate) makes switching free and allocation-free.
- **Alternatives**: A dense B × bins matrix with `vDSP_mmul`: 128 × 4,097 = 524k Floats and mostly
  zeros. Lazy table creation on first use: allocates on the worker at a switch.

## ANL-002-D6: Output scale and normalizers

- **Decision**: Linear values out of the reducer. `BandMath.normalizedLinear(v, reference: 1)` =
  clamp(v / reference, 0, 1); `BandMath.normalizedDecibels(v, floorDecibels: −80)` =
  clamp((20·log10 v − floor) / −floor, 0, 1), with v ≤ 0 → 0; invalid reference (≤ 0, non-finite) or
  floor (≥ 0, non-finite) gives 0. `BandMath.normalize(_:count:scale:)` applies one in place.
- **Rationale**: Linear keeps the reducer exact and additive; visuals want a decibel-like mapping;
  −80 dB covers music's useful range above a 16-bit noise floor without lighting bars on dither.
  Adaptive gain belongs to ANL-003/MOD-015.

## ANL-002-D7: The multi-tone fixture and the expected band

- **Decision**: Built in the test target: `ToneGenerator` mono sines at 100, 440, 1,000, 1,500 Hz
  (the catalog's sine frequencies) plus 5,000 and 12,000 Hz, amplitude 0.15 each, summed in Float in
  a fixed order. The expected band of a tone is the owner of the catalog's `nearestBin` (the band with
  the largest weight of that bin, lower band on a tie), computed by the test's own oracle. Checks:
  (a) expected band ≥ 0.35·A; (b) "strict" combinations — the tone's main lobe `[f − 2.5Δ, f + 2.5Δ]`
  inside the expected band and no other tone's lobe touching that band — read A within 2 % and are
  the largest band among those touching the lobe; (c) bands that do not touch `[f − 4Δ, f + 4Δ]` of any
  tone read ≤ 0.02·A.
- **Rationale**: The catalog stays at version 1 (no golden-hash churn). (a) holds for any edge
  placement: the owner gets at least half of the peak bin (≥ 0.72 A² at worst-case scalloping),
  giving ≥ 0.49 A in a wide band, more in a narrow one. (b) is the exact amplitude law of D3 where the
  FFT can resolve the band. (c) is Hann sidelobe leakage (below −40 dB beyond 3.5 bins).
- **Alternatives**: A new catalog fixture (version 2): changes the golden hashes of AUD-016 for no
  analysis benefit. Requiring the expected band to be the global maximum in every combination: false
  at small FFT sizes, where many bands share one bin.

## ANL-002-D8: Sample-rate validity

- **Decision**: Layouts and reducers reject sample rates below 8,000 Hz or not finite
  (`BandLayoutError.invalidSampleRate`). 8 kHz is AudioCore's lowest `ToneFormat` rate; its Nyquist,
  4 kHz, still leaves 7.6 octaves above 20 Hz.
- **Rationale**: Below that the band range shrinks towards nothing; the app's stream is 44.1 kHz.
