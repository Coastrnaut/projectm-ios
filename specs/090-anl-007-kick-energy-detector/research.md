# Research: ANL-007 Kick Energy Detector

## ANL-007-D1: Band energy from ANL-001 magnitudes, not ANL-002 bands

- **Decision**: The detector builds its own weight table for one range [lo, hi) per FFT size, using
  ANL-002's rule (bin k covers one bin width centred on k·R/N, bin 1 from 0 Hz; weight = overlap
  fraction), and computes P = Σ w_k·m_k² / 1.5 (1.5 = periodic Hann ENBW in bins), so a full-scale
  sine inside the range reads P ≈ 1 (0 dB). Total frame power uses all bins 1…N/2 with the same
  scale.
- **Rationale**: ANL-002's band edges depend on the user's band count (16-128) and change at run
  time; the kick must not. Power (squared magnitudes) is additive across bins, unlike the band
  reducer's magnitude sums.
- **Alternatives**: reuse `BandReducer` at a fixed count (its edges do not match 40/150 Hz; extra
  work for 128 bands); time-domain biquad filter on PCM (the pipeline only exposes spectra per
  frame; a second PCM path would duplicate the stream).

## ANL-007-D2: Level-independent decision

- **Decision**: L = 10·log10(max(P, 10^−12)) clamped to ≥ floor (−70 dB). Reference = the highest L
  of the preceding r = size/hop frames (clamped 1…8; 4 at 2,048/512); the history is seeded with one
  floor level at creation and reset. Detection value D = L − reference. Threshold = max(9 dB,
  median(D) + 4·MAD(D)) over the preceding W = round(1.0 s · R / hop) values of D (86 at hop 512,
  clamped 1…128), kept in a ring plus a sorted copy (insert and remove by shifting: O(W)); MAD is
  computed per frame into a scratch array with insertion sort. An empty window gives median 0,
  MAD 0.
- **Rationale**: a constant gain adds the same dB to L and its reference, so D is unchanged whenever
  both are above the floor; kicks rising from silence clear the threshold on the same frame at −30
  and −6 dBFS when starts are hop-aligned. The reference spans one window, so it lies outside the
  75 % overlap of the frames that already contain the hit; taking its highest level makes D the
  rise above the recent peak, which background noise reaches only rarely (debug runs: ≤ 5.6 dB
  over 12 s of white noise at two levels), while a kick's first frame rises 16–45 dB. A kick
  train's D is about −1.3 dB per frame (its decay) except at the hits, so median and MAD stay small
  and the 9 dB minimum governs.
- **Rejected**: median and MAD of the level itself (design review before coding: a decaying kick
  spans ~40 dB of level within each beat, so 4·MAD ≈ 40 dB would suppress every kick); the lowest
  level of the window as reference (implementation: noise dips gave D up to 8 dB and a false kick);
  a 6 dB minimum (implementation: white noise reached 6.5 dB once); mean + k·σ; a slow exponential
  envelope ratio; ANL-004's linear flux of decibel-normalized bands (depends on its normalization
  floor, so not level-independent).

## ANL-007-D3: Floor and dominance

- **Decision**: floor −70 dB (band level re a full-scale sine); dominance: the band's share of the
  frame's power increase over the reference frame, 10·log10(ΔP_band / ΔP_total) ≥ −15 dB (0 dB when
  the total rose less than the band; no event when the band or the total did not rise).
- **Rationale**: 16-bit TPDF dither (≈ −96 dBFS RMS, white) puts about −119 dB into 40–150 Hz;
  digital silence reads the clamp. An abrupt 5 kHz or 1 kHz burst leaks energy into the low bins
  through its step onset, but that is a small part of its power increase: measured −37.9 and
  −23.4 dB. A kick's increase is concentrated in band (−0.5 to −2.6 dB in every fixture), also under
  a louder sustained pad, whose absolute share at the kick's first frame was −27 dB (why the share of
  total power was rejected).
- **Limitations**: abrupt 200–300 Hz bursts fire (increase share −6 and −12 dB); a kick whose rise is
  smaller than the rest of the spectrum's simultaneous rise is not reported.

## ANL-007-D4: Arming, refractory, envelope

- **Decision**: fire on the first frame where all conditions hold while armed and at least 100 ms
  after the previous event; any frame with rise > threshold disarms; a frame with rise ≤ threshold
  re-arms. Envelope e ← e·exp(−hop/(0.1·R)) per accepted frame, then e = 1 on an event.
- **Rationale**: ANL-004's arm/disarm rule, proven in its tests; it alone prevents a held tone from
  retriggering (the rise must fall back first, which also happens as the median catches up), and
  the refractory period guards the retrigger when a decaying kick's level crosses back and forth.

## ANL-007-D5: Event timing and frame contiguity

- **Decision**: event sample = `frame.index + size − hop` (first sample of the newest hop),
  ANL-004-R6. Frames at another rate or with a wrong magnitude count are ignored and counted, and
  the next accepted frame only updates the window (no event); a non-contiguous frame or an FFT size
  change does the same.

## ANL-007-D6: Bus and modulation shape

- **Decision**: `AnalysisEventKind.transient(band: TransientBand, strength: Float, threshold: Float,
  level: Float)` (strength = rise in dB, level in dB); `AnalysisFrame.kickEnvelope: Float`.
  `AudioFeatureSource.kick`, ID `audio.kick`; `AudioFeatureFrame.kick: Float?`; SHD-009
  `ExpressionOpcode.kick = 9` (raw value 9 was never used; values are permanent).
- **Rationale**: one generic event kind serves ANL-008/009; they add a `TransientBand` case and a
  frame value. Stable IDs follow MOD-002's `audio.*` scheme so scenes round-trip.

## ANL-007-D7: Reuse for ANL-008 and ANL-009

- **Decision**: the detector type is band-agnostic; the configuration carries the range, floor,
  dominance, baseline window, minimum rise, MAD multiplier, refractory period and envelope time
  constant. Likely values (not implemented): ANL-008 ≈ 150–2,500 Hz with a lower dominance (a snare is
  broadband) and a shorter refractory; ANL-009 ≈ 5–16 kHz, refractory ≈ 30 ms, bounded event counts via the
  refractory period. Uncertainty for ANL-008 can come from `strength − threshold` on the event.
