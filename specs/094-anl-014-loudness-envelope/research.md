# Research: ANL-014 Loudness Envelope

All Technical Context items are resolved; the spec's Clarifications fix the product decisions.
These notes record the technical ones.

## ANL-014-D1 Placement

- **Decision**: compute in `AnalysisPipeline` from the spectra, on the analysis copy.
- **Rationale**: bindings are fed from the bus; the analysis copy is post channel selection, trim
  and gate; the existing `LevelMeter` feeds fixed-threshold classification and evidence exports and
  must not change.
- **Alternatives**: extend `LevelMeter`/`AudioAnalyzer` (raw sink, main-actor capture side, no path
  to bindings); a separate time-domain tap consumer (the tap has one consumer, the pipeline).

## ANL-014-D2 K-weighting in the frequency domain

- **Decision**: per-bin power weights |H_shelf(e^{jω})|²·|H_hp(e^{jω})|², ω = 2π·k/N, computed once
  per FFT size from the biquads designed for the rate with libebur128's formulas:
  - shelf: f0 = 1,681.974450955533 Hz, G = 3.999843853973347 dB, Q = 0.7071752369554196;
    K = tan(π·f0/R), Vh = 10^(G/20), Vb = Vh^0.4996667741545416, a0 = 1 + K/Q + K²,
    b = [(Vh + Vb·K/Q + K²), 2(K² − Vh), (Vh − Vb·K/Q + K²)]/a0, a = [1, 2(K² − 1)/a0, (1 − K/Q + K²)/a0];
  - high-pass: f0 = 38.13547087602444 Hz, Q = 0.5003270373238773; K, a as above, b = [1, −2, 1].
  - |B(e^{jω})|² = b0² + b1² + b2² + 2(b0·b1 + b1·b2)·cos ω + 2·b0·b2·cos 2ω (same for A).
- **Rationale**: exact power response of the standard's filters at each bin; no per-sample work;
  identical across backends; at 48 kHz the design reproduces BS.1770's table to about 1e-8.
- **Check points** (spec S3, tests): weight at 997 Hz ≈ +0.69 dB, so a full-scale 997 Hz sine
  reads −3.01 LKFS; 100 Hz < 1 kHz < 2 kHz in weight.
- **Alternatives**: time-domain biquads (needs samples), A-weighting, unweighted (Clarifications).

## ANL-014-D3 Mean-square from Hann magnitudes

- ANL-001 magnitudes scale a bin-centred full-scale sine to 1 (neighbours 0.5): Σ m² = 1.5 = 3 ×
  the sine's mean square 0.5. For white noise of variance σ², E[Σ m²] = 3σ² as well (Parseval with
  the Hann window's Σw² = 3N/8 and the 4/N magnitude scale). So z = Σ w_k·m_k² / 3. DC (k = 0) is
  excluded (the high-pass removes it anyway); the Nyquist bin is included.

## ANL-014-D4 Smoothing and lag

- **Decision**: smooth the normalized target with `SmoothingTimes.coefficient` (ANL-003), attack
  0.1 s, release 0.4 s, Δt = frame.hop / rate. Snap on the first frame; exact 0 below 0.001 when
  the target is 0; clamp after every step.
- **Lag model**: the 2,048-sample window spreads a step over 4 frames; since the target is in dB,
  the windowed power reaches 90 % of a 30 dB step (−3 dB of the final power) once about half of
  the Hann-weighted window covers the new level, i.e. about 2 frames after the step enters; the
  smoother then adds about its 90 % time. The documented lag is the measured value of the whole
  chain (Implementation results), tested within one frame.

## ANL-014-D5 Opcode and source

- `ExpressionOpcode.loudness = 16` (1-15 and 20-32 are taken; 16-19 free). `audio.loudness`.

## ANL-014-D6 Test cost

- Weighting, calibration, bounds and order use single windows through `SpectrumAnalyzer` (each a
  2,048-point FFT); the step test streams 1.5 s (≈ 130 frames) through `SpectrumStream`; one
  pipeline run of ≤ 0.6 s of audio. Expected total well under 0.5 s in the Linux shape.
