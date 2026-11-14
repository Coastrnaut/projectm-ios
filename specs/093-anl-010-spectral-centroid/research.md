# Research: ANL-010 Spectral Centroid

Decisions D1-D5 restate the Clarifications with their evidence; D6-D8 are design decisions.

## ANL-010-D1: Power weighting

- **Decision**: C = Σ f_k·m_k² / Σ m_k².
- **Rationale**: Reference script (pure-Python radix-2 FFT, periodic Hann, the ANL-001 scaling
  being irrelevant to a ratio), run 2026-11-13 during clarify:

  | FFT size, rate | 100 | 200 | 400 | 800 | 1,600 | 3,200 | 6,400 Hz |
  |---|---|---|---|---|---|---|---|
  | 512, 44.1 kHz | 110.9 | 200.0 | 400.0 | 800.0 | 1,600.0 | 3,200.0 | 6,400.0 |
  | 2,048, 44.1 kHz | 100.0 | 200.0 | 400.0 | 800.0 | 1,600.0 | 3,200.0 | 6,400.0 |
  | 8,192, 44.1 kHz | 100.0 | 200.0 | 400.0 | 800.0 | 1,600.0 | 3,200.0 | 6,400.0 |
  | 512, 48 kHz | 115.4 | 200.1 | 400.0 | 800.0 | 1,600.0 | 3,200.0 | 6,400.0 |
  | 2,048, 48 kHz | 100.0 | 200.0 | 400.0 | 800.0 | 1,600.0 | 3,200.0 | 6,400.0 |

  The tones were not bin-centred (phase 0.3 rad, arbitrary frequencies). Hann's power response
  |W(δ)|² is symmetric and band-limited, so its discrete first moment around the tone is exact;
  the only bias is at 512 points and 100 Hz, where the main lobe reaches the excluded DC bin. Two
  tones 500 Hz + 2 kHz at amplitudes 0.5 and 0.25 read 800.0 Hz (prediction Σa²f/Σa² = 800).
  A 100 Hz tone plus uniform noise 54 dB below read 100.03 Hz power-weighted, 385 Hz
  magnitude-weighted.
- **Alternatives**: magnitude weighting (noise-floor sensitive), log-magnitude weighting (no
  physical meaning, undefined at 0).

## ANL-010-D2: Analysed range and normalization

- **Decision**: whole bins from max(1, ⌈20·N/R⌉) through N/2; n = clamp(log2(C/50)/log2(200), 0, 1).
- **Rationale**: see Clarifications. White noise's expected power-weighted centroid over bins
  k₀…N/2 with flat expected power is the mean bin frequency, (k₀ + N/2)/2 · R/N ≈ 11,035 Hz at
  44.1 kHz and N = 2,048 (the Nyquist bin's half scaling shifts it by under 0.01 %); single frames
  of seeded uniform noise ranged 10,613–11,340 Hz (10 seeds), within 5 %.
- **Alternatives**: fractional edge weights as ANL-002 (no measurable effect on a mean over a
  1,000-bin range, and extra tables); a linear normalization (squeezes music into the bottom).

## ANL-010-D3: Silence

- **Decision**: floor −70 dB of the range's power re a full-scale sine (Σ m² ≤ 1.5·10^(−7));
  hold below it; 0/0 before any signal.
- **Rationale**: Clarifications. A bin-centred unit sine reads 1 at its bin and 0.5 at each
  neighbour under ANL-001's scaling, so its power sum is 1 + 2·0.25 = 1.5 (off-centre the Hann
  power sum is the same, by Parseval). A ±1 LSB 16-bit dither is about −96 dB, well below.

## ANL-010-D4: No smoothing

- **Decision**: none in the estimator; MOD-002's binding envelope smooths.

## ANL-010-D5: Source and opcode

- **Decision**: `audio.centroid`, opcode 15 (the lowest unused raw value; 10-14 are arithmetic).

## ANL-010-D6: A value type, no Accelerate

- **Decision**: `SpectralCentroidEstimator` is a struct holding only the configuration and the
  last reading; the sum is a plain loop accumulating in Double.
- **Rationale**: no buffers to preallocate (Constitution VII trivially), identical results on the
  host and in the Linux shape, and the loop over ~1,000 bins costs about a microsecond; Double
  accumulation keeps 1,000-term sums exact enough for the 1 % tolerance with any input.

## ANL-010-D7: Shared range helper for ANL-011/012

- **Decision**: `SpectralBinRange(lowerFrequency:upperFrequency:size:sampleRate:)` returns the
  first and last whole bin (DC excluded) or nil when the range holds no bin. Rolloff (cumulative
  power to a percentile) and flatness (geometric/arithmetic mean of power) iterate the same bins;
  each will add its own estimator next to this one. Nothing else is shared yet (no speculative
  abstractions).

## ANL-010-D8: Frames that do not match

- **Decision**: a frame whose sample rate differs from the configuration's, or whose magnitude
  count is not `size.binCount`, leaves the reading unchanged (as ANL-004 and ANL-007 ignore
  mismatched frames). Non-finite magnitudes count as 0.
