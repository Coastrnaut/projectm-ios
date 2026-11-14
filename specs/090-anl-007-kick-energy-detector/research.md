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

- **Decision**: L = 10·log10(max(P, 10^−12)) clamped to ≥ floor (−70 dB). Reference = the minimum L
  of the preceding r = size/hop frames (clamped 1…8; 4 at 2,048/512). Detection value D = L −
  reference. Threshold = max(6 dB, median(D) + 4·MAD(D)) over the preceding W = round(1.0 s · R /
  hop) values of D (86 at hop 512, clamped 1…128), kept in a ring plus a sorted copy (insert and
  remove by shifting: O(W)); MAD computed per frame into a scratch array with insertion sort. An
  empty window gives median 0, MAD 0 (threshold 6 dB).
- **Rationale**: a constant gain adds the same dB to L and its reference, so D is unchanged
  whenever both are above the floor; kicks rising from silence clear the threshold on the same
  frame at −30 and −6 dBFS when starts are hop-aligned (the first frame of a 55 Hz burst at
  −30 dBFS reads about −45 dB, 25 dB above the floor). The reference spans one window so it lies
  outside the 75 % overlap of the frames that already contain the hit. A kick train's D is about
  −1.3 dB per frame (its decay) except for a few spike frames per beat, so median and MAD stay
  small; noise gives D a wide distribution and lifts the threshold.
- **Rejected after a design review (before coding)**: median and MAD of the level itself. A
  decaying kick spans ~40 dB of level within each beat, so the level MAD is ~10 dB and a 4·MAD
  threshold (~40 dB) would suppress every kick. Also rejected: mean + k·σ (spikes inflate it); a
  slow exponential envelope ratio (masks the next kick after a loud one); ANL-004's linear flux of
  decibel-normalized bands (depends on the −70 dB normalization floor, so not level-independent).

## ANL-007-D3: Floor and dominance

- **Decision**: floor −70 dB (band level re a full-scale sine); dominance: 10·log10(P_band /
  P_total) ≥ −20 dB.
- **Rationale**: 16-bit TPDF dither (≈ −96 dBFS RMS, white) puts about −119 dB into 40–150 Hz;
  digital silence reads the clamp. An abrupt 5 kHz or 1 kHz burst leaks energy into the low bins
  through its step onset (≈ 1/Δf skirt); white noise's share of 40–150 Hz is 110/22,050 ≈ −23 dB.
  Both fall below −20 dB, so neither can fire however loud. A kick under an equally loud pad has a
  share around −3 to −10 dB.
- **Limitation**: a kick more than ~20 dB below the rest of the mix is not reported (spec edge case).

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
  constant. Likely values (not implemented): ANL-008 ≈ 150–2,500 Hz with dominance off or low and a
  shorter refractory; ANL-009 ≈ 5–16 kHz, refractory ≈ 30 ms, bounded event counts via the
  refractory period. Uncertainty for ANL-008 can come from `strength − threshold` on the event.
