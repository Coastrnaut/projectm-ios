# Data Model: ANL-010 Spectral Centroid

## SpectralBinRange (value)

| Field | Type | Rule |
|---|---|---|
| `first` | Int | max(1, ⌈lower·N/R⌉); DC never included |
| `last` | Int | min(N/2, ⌊upper·N/R⌋) |

Created by `init?(lowerFrequency:upperFrequency:size:sampleRate:)`; nil when `first > last` or an
input is not finite and positive.

## SpectralCentroidConfiguration (value, validated)

| Field | Default | Rule |
|---|---|---|
| `sampleRate` | 44,100 Hz | finite, > 0 |
| `lowerFrequency` | 20 Hz | finite, > 0, < Nyquist |
| `upperFrequency` | nil (Nyquist) | nil or finite and > `lowerFrequency`; clipped to Nyquist |
| `floorDecibels` | −70 dB | finite, < 0 |
| `normalizationLower` | 50 Hz | finite, > 0 |
| `normalizationUpper` | 10,000 Hz | finite, > `normalizationLower` |

Derived: `floorPower` = 1.5 · 10^(floor/10) (Σ m² at the floor); `normalized(hz:)`.
Errors (`SpectralCentroidConfigurationError`): `invalidSampleRate`, `invalidFrequencyRange`,
`invalidFloor`, `invalidNormalizationRange`.

## SpectralCentroidReading (value)

| Field | Type | Meaning |
|---|---|---|
| `hz` | Float | centroid in Hz; the held value at silence; 0 before any signal |
| `normalized` | Float | 0…1 log mapping of `hz`; held / 0 likewise |
| `hasSignal` | Bool | true when this frame was above the floor |

`SpectralCentroidReading.none` = (0, 0, false).

## SpectralCentroidEstimator (value, mutable)

State: the configuration and the last reading. Transitions per frame:

- matching frame, range power > floor → new reading (`hasSignal` true);
- matching frame, power ≤ floor → previous `hz`/`normalized`, `hasSignal` false;
- mismatched frame (rate, magnitude count) → reading unchanged;
- `reset()` → `.none`.

## AnalysisFrame (extended)

`centroidHz: Float` and `centroid: Float` (normalized), both defaulted to 0 in `init`.

## AudioFeatureFrame / AudioFeatureSource (extended)

`AudioFeatureFrame.centroid: Float?` (nil when not fed); `AudioFeatureSource.centroid`, ID
`audio.centroid`, reads it (nil or non-finite → 0). `ExpressionOpcode.centroid = 15`.

## LiveBandFrameInfo (extended)

`centroid: Float = 0`, copied from the bus frame.
