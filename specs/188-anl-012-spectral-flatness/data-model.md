# Data Model: ANL-012 Spectral Flatness

## SpectralFlatnessConfiguration (value, Sendable, Hashable)

| Field | Default | Rule |
|---|---|---|
| sampleRate | 44,100 | finite, > 0 (`invalidSampleRate`) |
| lowerFrequency | 20 Hz | finite, > 0, < Nyquist (`invalidFrequencyRange`) |
| upperFrequency | nil (Nyquist) | nil or > lower; clipped to Nyquist |
| floorDecibels | −70 | finite, < 0 (`invalidFloor`) |
| floorPower (derived) | 1.5·10^(floor/10) | — |

Static `relativeEpsilon = 1e-12` (ε = relativeEpsilon × mean bin power).

## SpectralFlatnessReading (value)

`flatness: Float` (0…1), `hasSignal: Bool`; `.none` = 0, false. At silence the reading is `.none`.

## SpectralFlatnessEstimator (value, not shared across threads)

`configuration`, `resolvedBackend`, `reading`; `reset()` → `.none`; `process(frame, magnitudes:)`;
static `measure(magnitudes:range:backend:) -> (flatness, power)`.

## AnalysisFrame (ANL-016) addition

`flatness: Float` (0 at silence), default 0.

## MOD-002 / SHD-009

`AudioFeatureSource.flatness` (`audio.flatness`), `AudioFeatureFrame.flatness: Float?`,
`ExpressionOpcode.flatness = 33`, `LiveBandFrameInfo.flatness: Float`.
