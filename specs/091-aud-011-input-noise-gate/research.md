# Research: AUD-011 Input Noise Gate

Each decision lists what was chosen, why, and what was rejected.

## AUD-011-D1 Position in the chain

- **Decision**: tap → channel selection (AUD-009) → trim (AUD-008) → gate → `WaveformTap` → pipeline.
- **Rationale**: the threshold is measured on exactly what the analysis sees; the trim cannot lift
  a noise floor over a gate that sits after it; the oscilloscope shows the gated signal.
- **Alternatives**: before the trim (the effective threshold would move with the trim and a +24 dB
  boost could push noise through); inside the pipeline (several consumers, VIS-003's tap would miss it).

## AUD-011-D2 Which sources

- **Decision**: active only while the source is Microphone (flag set by `AppCoordinator.start`,
  cleared by `stop`); the setting itself is global.
- **Rationale**: the row targets ambient mic noise; capture and playback have no noise floor and a
  gate would only cut fades and quiet passages from the visuals.
- **Alternatives**: all sources (harms quiet music); per-source settings (no use case).

## AUD-011-D3 Detector

- **Decision**: peak envelope e = max(peak(frame), e·r), r = exp(−1/(0.010·44,100)) ≈ 0.99773.
- **Rationale**: same unit as the classifier (peak dBFS, FR-011); instant reaction to onsets (an
  RMS window would add its length to the opening time); a 1 kHz tone's ripple between peaks is
  < 0.02 dB; low-frequency ripple is absorbed by the hold.
- **Alternatives**: windowed RMS (latency); a smoothed RMS (slow attack); no envelope (per-sample
  zero crossings would re-arm and expire the hold inside one period at low frequencies).

## AUD-011-D4 Law and closed level

- **Decision**: open at T, close at T − 6 dB; attack linear 0→1 in 5 ms (221 frames), hold 100 ms
  (4,410 frames), release linear 1→0 in 150 ms (6,615 frames); closed gain 0 (full mute).
- **Rationale**: the acceptance requires a gated silence fixture (exact zeros); linear ramps of at
  least 221 frames keep the gain change per frame ≤ 1/221, far from a click in spectra; hold
  bridges the gaps between peaks of low notes and short pauses, so the gate does not chatter.
- **Alternatives**: a range floor (e.g. −40 dB; residual noise still moves the bars); exponential
  ramps (never reach exactly 1 or 0, which breaks bit-exact unity and exact zeros).

## AUD-011-D5 Defaults and bounds

- **Decision**: off; T = −50 dBFS (−80…−20); H = 6 dB (0…20); attack 5 ms (0.5…50); hold 100 ms
  (0…1,000); release 150 ms (10…2,000). Settings exposes on/off and T only.
- **Rationale**: −50 dBFS peak sits above a quiet room through the built-in microphone in
  measurement mode (≈ −60…−55 dBFS) and below normal music; it also equals the classifier's
  "active" threshold, so the visuals open when the indicator says "Listening". Fixed times keep the
  UI to two controls.
- **Alternatives**: exposing times (four more sliders to test and label for little value).

## AUD-011-D6 State on toggles and sessions

- **Decision**: inactive keeps no state; becoming active or a new session generation (ANL-016-R9)
  starts closed with e = 0. The threshold is re-read each read; `powf` runs only when it changed.
- **Rationale**: a quiet room stays gated from the first frame; no stale envelope from another source.
- **Alternatives**: start open (a burst of room noise on enable).
