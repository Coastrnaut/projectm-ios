# Research: ANL-004 Spectral Flux Onset Detector

Decisions are numbered ANL-004-D1… and cited from the spec, plan and code.

## ANL-004-D1: detection function

- **Decision**: half-wave-rectified spectral flux on ANL-002 log-frequency bands (64 by default),
  each band mapped to 0…1 by `BandMath.normalizedDecibels` with the detector's floor (−70 dBFS):
  `flux(t) = (1/B) Σ_b max(0, c_b(t) − c_b(t−1))`, `c_b = clamp((20·log10 v_b − floor)/−floor, 0, 1)`.
- **Rationale**: Böck, Krebs and Schedl ("Evaluating the online capabilities of onset detection
  methods", ISMIR 2012) and Dixon ("Onset detection revisited", DAFx 2006) report spectral flux as
  the best simple onset function, and the log-compressed, filterbank ("LogFiltSpecFlux") variant as
  the best online one. ANL-002's bands are such a filterbank. Sine-equivalent band amplitudes make
  broadband noise levels almost independent of the FFT size; the decibel mapping makes the flux
  independent of playback level (a pulse train at −6 and at −20 dBFS gives the same pattern); the
  floor turns silence and quiet noise into exact zeros. The value is bounded to 0…1, a ready
  strength for VIS-008.
- **Alternatives**: linear-magnitude flux (level-dependent, a loud sustained note masks a quiet
  attack); log flux on bins (a per-bin floor moves with the FFT size because per-bin noise
  magnitude scales with 1/√N; 4,097 logs per frame at 8,192 points); complex-domain or phase
  deviation (needs phases ANL-001 does not keep; worse on noisy input).

## ANL-004-D2: threshold and peak picking

- **Decision**: `threshold(t) = δ + κ · mean(flux over the preceding W frames)`, δ = 0.06, κ = 1.5,
  W = round(0.1 s · rate / hop) clamped to 1…128. Event at frame t when `flux(t) > threshold(t)`,
  the detector is armed, and `sample(t) − sample(previous event) ≥ 0.05 s · rate`. Any frame above
  its threshold disarms; a frame at or below re-arms. No look-ahead.
- **Rationale**: the adaptive mean term suppresses steady flux (sweeps, noise) and the offset is
  the absolute part that, with the floor, makes silence silent. Firing on the rising edge of each
  flux peak bounds the timing error by construction (D5), whereas the flux maximum of a click can
  arrive two hops later at hop ≤ N/4 (the Hann weight keeps rising while the click moves toward
  the window centre). Arming replaces a long refractory time: a click is visible for up to N/hop
  frames, and the detector stays disarmed while the flux keeps rising.
- **Alternatives**: local maximum with one frame of look-ahead (timing beyond one hop at hop N/4
  and N/8 in the prototype); moving median (no measurable gain on the fixtures; the mean is simpler
  and maps to `vDSP_meanv`); fixed threshold (fires on every frame of a loud sweep).

## ANL-004-D3: parameter values (prototype sweep, 2026-11-13)

A throw-away prototype (scratch package in `.build/scratch/proto`, not committed) ran the same
pipeline over every fixture × 5 sizes × hops N/2, N/4, N/8 × 44.1/48 kHz, plus seeded noise at
seven levels, a single-sample impulse train and pulse trains at lower levels:

| Floor dB | δ | κ | W s | Fixture failures | Notes |
|---|---|---|---|---|---|
| −60 | 0.03 | 1 | 0.1 | 1 (accent, N 8192, hop N/8: 2 late) | weak accents near the floor |
| −70 | 0.03–0.04 | 1 | 0.1 | 1 (`sweep-linear` 44.1 k N 512: 2nd event) | offset too low |
| −80 | 0.03 | 1 | 0.1 | 3 sweep extras | floor too low |
| −68 … −75 | 0.05–0.07 | 0.5–2 | 0.1 | 0 | stable region |
| **−70** | **0.06** | **1.5** | **0.1** | **0** | chosen: centre of the region; unit impulses pass at N/2, N/4 |
| −70 | 0.06 | 2 | 0.2 | 0 | fewer noise events, but 6 unit-impulse failures |

With the chosen values, steady white noise at 0.1 and 0.3 peak (−20 and −10 dBFS) produced the
start event plus at most 21 spurious events per 10 s at 512 points, at most 2 at 1,024 points and
none at 2,048 points and above; noise at 0.01 peak (−40 dBFS) and below produced none at all. 2 ms
pulses at 0.1 peak (−20 dBFS) were all matched at hops N/2 and N/4 at every size; at 0.05 peak the
8,192-point windows started to miss pulses (the floor), which sets the documented detection level.

## ANL-004-D4: stream lead-in and frame hop

- **Decision**: `SpectrumStream(…, leadIn: .silence)` pre-fills `size − hop` zeros at init and on
  `reset()`; frame indices start at `−(size − hop)`. `SpectrumFrame` carries `hop`.
- **Rationale**: without a lead-in, sample 0 lies only in frame 0, at window position 0 where the
  periodic Hann weight is 0, so an onset at the start of a stream is invisible (the prototype
  confirmed it). With the lead-in every sample passes through positions `size − hop`,
  `size − 2·hop`, …, like any other sample, and frame j's newest hop is exactly `[j·hop, (j+1)·hop)`.
  Carrying the hop in the frame lets the detector apply the timing rule and detect gaps without a
  second copy of the configuration.
- **Alternatives**: padding in tests only (production would differ from what is tested); a
  detector-owned stream (duplicates ANL-001 and breaks the pull-from-frames contract).

## ANL-004-D5: timing rule and tolerance

- **Decision**: event sample index = `frame.index + size − hop`; tolerance |event − onset| ≤ hop.
- **Rationale**: a click first appears in the newest hop of frame j (position ≥ size − hop). If the
  detector fires at frame j, the error is 0…hop − 1 (event at or before the click); if the click's
  first appearance is too weak (Hann edge) and it fires at j + 1, the click lies in the hop before
  that frame's newest hop, error −hop…−1. Two frames in, the click's window weight is at least
  sin²(π·hop/size): 1 at N/2, 0.5 at N/4, 0.15 at N/8, which is why the guarantee is stated for
  N/2 and N/4 and the catalog pulses (well above the floor) also pass at N/8.

## ANL-004-D6: vDSP and portable paths

- **Decision**: band reduction uses ANL-002's per-path code; normalization uses scalar `log10f` on
  both paths (vForce's `vvlog10f` could differ in the last bit and move a threshold decision);
  difference, rectification and sum use `vDSP_vsub`, `vDSP_vthres` (threshold 0) and `vDSP_sve`
  on the accelerated path and ordered loops on the portable path; the history mean is an ordered
  loop on both (at most 128 values).
- **Rationale**: the paths may differ only by summation order (~1e-7 relative); events must be
  identical, which the acceptance verifies on every fixture.
