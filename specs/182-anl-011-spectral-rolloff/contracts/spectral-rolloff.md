# Contract: ANL-011 Spectral Rolloff

- **C1 Measure.** `SpectralRolloffEstimator.measure` over `range` returns (hz, power): power = Σ m_k² (non-finite m → 0); hz per research ANL-011-D2; (0, 0) when the power is 0 or not finite or `range.last ≥ magnitudes.count`. Accelerated and portable results agree within 0.001·Δf; repeated calls are bit-equal.
- **C2 Process.** Frames with another sample rate or a wrong magnitude count leave the reading unchanged. No bin range, power ≤ floorPower, or a non-finite result → `.none`. Otherwise `hz`, `normalized(hz:)`, `hasSignal = true`. No allocation, lock, log or clock.
- **C3 Pipeline.** `AnalysisPipeline` processes every frame's existing magnitudes; `AnalysisFrame.rolloffHz`/`rolloff` carry the reading; a session start resets it; `AnalysisPipelineConfiguration(rolloff:)` must share the spectrum's sample rate (`sampleRateMismatch`).
- **C4 Source.** `AudioFeatureSource.rolloff.id == "audio.rolloff"`, parses back; value = `AudioFeatureFrame.rolloff` (nil or non-finite → 0). `CompiledExpression("audio.rolloff")` emits opcode 19 and evaluates to the frame's value. `inspectorName == "Rolloff"`.
