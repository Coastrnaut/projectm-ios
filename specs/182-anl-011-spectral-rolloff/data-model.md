# Data Model: ANL-011 Spectral Rolloff

## SpectralRolloffConfiguration (value, Sendable, Hashable)

| Field | Default | Rule |
|---|---|---|
| sampleRate | 44,100 | finite, > 0 (`invalidSampleRate`) |
| lowerFrequency | 20 Hz | finite, > 0, < Nyquist (`invalidFrequencyRange`) |
| upperFrequency | nil (Nyquist) | nil or > lower; clipped to Nyquist |
| fraction | 0.85 | finite, 0.5…0.99 (`invalidFraction`) |
| floorDecibels | −70 | finite, < 0 (`invalidFloor`) |
| normalizationLower / Upper | 50 / 20,000 Hz | finite, 0 < lower < upper (`invalidNormalizationRange`) |
| floorPower (derived) | 1.5·10^(floor/10) | — |

## SpectralRolloffReading (value)

`hz: Float`, `normalized: Float` (0…1), `hasSignal: Bool`; `.none` = 0, 0, false. At silence the reading is `.none`.

## SpectralRolloffEstimator (value, not shared across threads)

`configuration`, `backend` (resolved `SpectrumBackend`), `reading`; `reset()` → `.none`;
`process(frame, magnitudes:)`; static `measure(magnitudes:range:fraction:binWidth:nyquist:backend:) -> (hz, power)`.

## AnalysisFrame (ANL-016) additions

`rolloffHz: Float` (0 at silence), `rolloff: Float` (normalized, 0 at silence). Both default 0.

## MOD-002 / SHD-009

`AudioFeatureSource.rolloff` (`audio.rolloff`), `AudioFeatureFrame.rolloff: Float?`, `ExpressionOpcode.rolloff = 19`,
`LiveBandFrameInfo.rolloff: Float`.
