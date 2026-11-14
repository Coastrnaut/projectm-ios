# Data Model: ANL-013 Stereo Correlation

## StereoCorrelationConfiguration (value, code-only)

| Field | Default | Rule |
|---|---|---|
| sampleRate | 44,100 | finite, > 0 |
| blockFrames | 1,024 | 16…65,536 |
| timeConstant | 0.1 s | finite, > 0 |
| floorDecibels | −70 | finite, < 0; floorMeanSquare = 0.5·10^(floor/10) |
| raiseBelow | −0.5 | −1 < raiseBelow < clearAbove < 1 |
| clearAbove | −0.3 | |
| holdSeconds | 1.0 | finite, > 0; holdBlocks = ceil(hold·rate / blockFrames) (44) |

Derived: decay a = exp(−blockFrames / (timeConstant·sampleRate)).

## StereoCorrelationReading

- `correlation: Float` (−1…1; 0 without signal)
- `hasSignal: Bool` (both channels above the floor)
- `phaseInverted: Bool` (the warning)
- `.none` = (0, false, false)

## StereoCorrelationMeter (value type, worker-confined)

State: block sums (Double ×3) and frame count; smoothed sums (×3) and weight; raise and clear block counters; `reading`. `append(interleaved:frames:channels:)`, `reset()`.

## Frame fields

- `AnalysisFrame.correlation: Float`, `.phaseInverted: Bool`
- `LiveBandFrameInfo.correlation`, `.phaseInverted`
- `AudioFeatureFrame.correlation: Float?` (raw r); `AudioFeatureSource.correlation` value (r+1)/2

## App state

- `AppCoordinator.stereoPhaseWarning: Bool` (observable), `stereoPhase: PhaseWarningAnnouncementThrottle` (last raise announcement time, whether the current raise was announced).
- Status rows X3a, X3b (kind `source`, cause system).
