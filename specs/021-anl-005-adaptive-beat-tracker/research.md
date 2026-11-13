# Research: ANL-005 Adaptive Beat Tracker

Decisions taken under owner rule 4 (best judgement). The prototype is a Python model of the
tracker fed with onset times that reproduce ANL-004's timing rule (an event at the start of the
hop that contains the click, or one hop later; 0.5 probability each, the worst plausible jitter),
run on 2026-11-13 in `.build/scratch/` (not committed). Its numbers chose the parameters below;
the Swift tests then measure the real pipeline (results in tasks.md and the final report).

## ANL-005-D1 — Input: onset events, not the onset-strength function

- **Decision**: consume ANL-004 `OnsetEvent`s (sample index, sample rate) plus the stream
  position. Strength is not used.
- **Rationale**: the row says "from onset intervals"; event times are exact on the sample clock;
  the per-onset work is bounded by the onset count (≤ 64 in the window) instead of running every
  frame; SHOW-011 can feed taps through the same call. Not weighting by strength keeps the accented
  fixture from favouring the bar or half tempo.
- **Alternatives**: autocorrelation of the per-frame detection value (ANL-004 `lastFlux`) over a
  6 s buffer — needs a frame-rate buffer, ties the result to the hop, and costs a 500-lag
  autocorrelation per frame; a dynamic-programming tracker (Ellis 2007) — offline by design.

## ANL-005-D2 — Tempo: comb histogram of inter-onset intervals with 1/n weights

- **Decision**: every pair of onsets ≤ 4 s apart votes for periods interval/n, n = 1…4, weight
  1/n × triangular kernel (± timing tolerance on the interval) × recency 2^(−age/2 s), on a
  0.25 BPM grid over 60–200 BPM; × preference exp(−½ log2(BPM/120)²); first maximum.
- **Rationale**: for a regular train with M onsets in the window, the true period collects
  Σ (M−n)/n over n = 1…4; double tempo collects only even multiples at half weight; half tempo
  collects only every other interval. Prototype: 120 and 132 BPM always picked correctly, never
  60/66 or 240. The preference only decides near-ties (it is 0.76 at 200 BPM and 0.61 at 60).
  Hysteresis at 0.9 keeps a locked tempo when the histogram wobbles.
- **Alternatives**: consecutive intervals only (median IOI) — one missed onset doubles the
  interval; resonating comb-filter banks (Scheirer 1998) — per-frame cost on the strength signal.

## ANL-005-D3 — Phase and fine tempo: anchored least squares

- **Decision**: anchor = the onset with the largest recency-weighted number of onsets within 2τ
  of the coarse grid through it (later onset on ties); then three unweighted least-squares fits of
  time against beat number k over on-grid onsets (2τ, then τ, τ). τ = 35 ms.
- **Rationale**: the 0.25 BPM grid alone is too coarse at 120 BPM (±0.125 BPM, and its peak is
  biased by the kernel); a least-squares slope over ~12 beats with ±1 hop jitter gives errors of
  0.0–0.5 BPM in the prototype (hops 256–1,024). Recency-weighted fits (tried first) lost accuracy
  at hop 1,024 (132.0 → 133.9 BPM at 48 kHz) because the effective number of points shrank; the
  unweighted fit fixed it. The first, wider pass is needed because an anchor onset itself can be a
  hop off, so neighbours can be two hops off the provisional grid.
- **Alternatives**: phase-locked loop on each onset — converges slower and needs gain tuning;
  Kalman filter on (phase, period) — more parameters, same result on synthetic data.

## ANL-005-D4 — Confidence: precision × coverage × support × freshness

- **Decision**: as spec ANL-005-R7; "high" = 0.5.
- **Rationale**: prototype on random onsets (exponential gaps ≥ 50 ms, rates 1–16/s, 5 seeds ×
  30 s): the first version (recency-weighted precision, half-beat onsets neutral, support full at
  6 beats) reached 0.56. Unweighted precision over the whole window, coverage over the window's
  span, no neutral half-beats and support full at 8 beats bring the maximum to 0.40 (rate 2/s),
  0.26 (1/s), 0.38 (4/s), 0.36 (8/s), 0.34 (16/s), while every pulse run reaches 1.0 within 3 s
  of the start. Off-beat onsets in real music therefore lower confidence; ANL-006 may refine.
- **Alternatives**: histogram peak-to-mean ratio — depends on the onset count and window;
  residual RMS — penalises large hops on clean pulses.

## ANL-005-D5 — Parameters and limits

- **Decision**: window 6 s (≤ 64 onsets), timing tolerance 35 ms, silence timeout 4 s, tempo
  range 60–200 BPM (preferred 120). Supported hops ≤ 1,024 samples.
- **Rationale**: prototype convergence (±1 BPM, confidence ≥ 0.8, to the end) at 2.3–3.2 s for
  120 and 132 BPM at hops 256–1,024, both rates; the 120→132 change re-converges 4.5 s after the
  change (the 6 s window must be mostly new onsets for precision ≥ 0.8), hence the 6 s target.
  35 ms covers one hop of 1,024 samples at 44.1 kHz (23.2 ms) with margin; at hop 2,048 the jitter
  exceeds it. 4 s timeout = 8 beats at 120 BPM.

## ANL-005-D6 — Accelerate and determinism

- **Decision**: vDSP only for exact element-wise steps: `vDSP_vclrD` (clear), `vDSP_vmulD`
  (preference), `vDSP_maxviD` (first maximum). All sums, the kernel accumulation and the fits are
  scalar `Double` loops in a fixed order on both paths. `exp2`/`log2`/`exp` come from the platform
  C math library; the preference table is computed once in `init`.
- **Rationale**: element-wise IEEE products and a first-maximum search have one correct answer,
  so the two paths give bit-identical results (ANL-005-R12), unlike vDSP sums whose order may
  differ (ANL-004 needed a 1e-4 strength tolerance). Repeated runs are bit-identical because
  nothing depends on time, threads or randomness. Results may differ between platforms' math
  libraries in the last bit of `exp2`; tests compare within one build only.
