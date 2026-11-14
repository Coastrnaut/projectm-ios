# Data Model: ANL-007 Kick Energy Detector

## TransientBand (enum, Sendable, Hashable, CaseIterable)

`kick` (40–150 Hz). ANL-008/009 add cases.

## TransientDetectorConfiguration (struct, Sendable, Hashable)

| Field | Kick default | Valid range |
|---|---|---|
| `band` | `.kick` | any case |
| `sampleRate` | 44,100 Hz | finite, ≥ 8,000 |
| `lowerFrequency` / `upperFrequency` | 40 / 150 Hz | 20 ≤ lower < upper ≤ rate/2 |
| `floorDecibels` | −70 | −120…−20 |
| `dominanceDecibels` | −20 | −60…0 |
| `baselineSeconds` | 1.0 (window of detection values for median/MAD) | > 0, ≤ 2 (window clamped to 1…128 frames) |
| `minimumRiseDecibels` | 6 | > 0, ≤ 40 |
| `deviationMultiplier` | 4 | 0…20 |
| `refractorySeconds` | 0.1 | 0…2 |
| `envelopeSeconds` | 0.1 | > 0, ≤ 5 |

Derived: `baselineFrames(hop:)` = round(baselineSeconds · rate / hop) clamped to 1…128;
`refractorySamples` = round(refractorySeconds · rate); `envelopeDecay(hop:)` =
exp(−hop / (envelopeSeconds · rate)).

## TransientEvent (struct, Sendable, Hashable)

`band`, `sequence` (1, 2, 3…; not restarted by `reset()`), `sampleIndex` (frame.index + size − hop),
`frameIndex`, `strength` (rise over baseline, dB), `threshold` (dB), `level` (band level, dB),
`sampleRate`, `timestampNanoseconds`; `seconds`.

## BandTransientDetector state (class, not Sendable; worker-confined)

Weight tables per FFT size (first bin, weights), level history (8), detection-value ring (128) +
sorted window (128) + deviation scratch (128), count/next, armed, hasEvent, lastEventSample, envelope, contiguity (previous index,
hop, size), needsBaseline, counters (processed, ignored, eventCount), last values (level, rise,
threshold, share).

Transitions per accepted frame: compute L, share → (baseline frame?) restart the level history with L, no event →
D = L − min(recent levels), median and MAD of the D window, threshold → push D and L → decay envelope → armed logic → event (envelope =
1). `reset()`: empty window, armed, no previous event, envelope 0, last values 0; keeps sequence
and counters.

## Bus additions

- `AnalysisEventKind.transient(band:strength:threshold:level:)`.
- `AnalysisFrame.kickEnvelope: Float` (0…1).
- `AnalysisPipelineConfiguration.kick: TransientDetectorConfiguration`.

## Modulation additions

- `AudioFeatureSource.kick` — ID `audio.kick`; value = `AudioFeatureFrame.kick` (nil or non-finite → 0).
- `ExpressionOpcode.kick = 9` (stack effect +1, cost 1).
- `LiveBandFrameInfo.kickEnvelope: Float`.
