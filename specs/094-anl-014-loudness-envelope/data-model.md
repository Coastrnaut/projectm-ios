# Data Model: ANL-014 Loudness Envelope

## LoudnessConfiguration (value, validated)

| Field | Type | Default | Rule |
|---|---|---|---|
| sampleRate | Double | 44,100 | finite, > 0 (and K-weighting's shelf below Nyquist: rate > 3,364 Hz) |
| floorDecibels | Double | −60 | finite, < ceiling |
| ceilingDecibels | Double | 0 | finite |
| times | SmoothingTimes | attack 0.1 s, release 0.4 s | ANL-003's clamp to 0…2 s |

`normalized(decibels:)` = clamp((L − floor)/(ceiling − floor), 0, 1); non-finite → 0.

## LoudnessReading (value)

| Field | Type | Meaning |
|---|---|---|
| decibels | Float | the frame's unsmoothed K-weighted level, LKFS-like dB, −120 at silence; always finite |
| envelope | Float | the smoothed normalized value, 0…1 |

`.silent` = (−120, 0).

## LoudnessEnvelope (state, one owner)

- `configuration`, `size: FFTSize` (init parameter), `weights: [Float]` (N/2 + 1 entries, built in `init`), `reading`, `primed: Bool`.
- `reset()`: reading = `.silent`, primed = false (the next frame snaps).
- `process(frame, magnitudes)`: frames with another rate, size or magnitude count leave the reading
  unchanged.

## AnalysisFrame (extended)

- `loudness: Float` (default 0), `loudnessDecibels: Float` (default −120).

## AudioFeatureFrame / AudioFeatureSource (extended)

- `AudioFeatureFrame.loudness: Float?`; `AudioFeatureSource.loudness`, ID `audio.loudness`.

## LiveBandFrameInfo (extended)

- `loudness: Float = 0`.
