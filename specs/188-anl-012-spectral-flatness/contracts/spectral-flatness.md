# Contract: ANL-012 Spectral Flatness

- **C1 Measure.** `SpectralFlatnessEstimator.measure` over `range` returns (flatness, power): power = Σ m_k² (non-finite m → 0); A = power / K; flatness = clamp(exp(mean(ln(P_k + 10⁻¹²·A))) / A, 0, 1); (0, 0) when the power is 0 or not finite or `range.last ≥ magnitudes.count`. Accelerated and portable results agree within 10⁻⁶; repeated calls are bit-equal.
- **C2 Process.** Frames with another sample rate or a wrong magnitude count leave the reading unchanged. No bin range, power ≤ floorPower, or a non-finite result → `.none`. Otherwise `flatness`, `hasSignal = true`. No allocation, lock, log or clock.
- **C3 Pipeline.** `AnalysisPipeline` processes every frame's existing magnitudes; `AnalysisFrame.flatness` carries the reading; a session start resets it; `AnalysisPipelineConfiguration(flatness:)` must share the spectrum's sample rate (`sampleRateMismatch`).
- **C4 Source.** `AudioFeatureSource.flatness.id == "audio.flatness"`, parses back; value = `AudioFeatureFrame.flatness` (nil or non-finite → 0). `CompiledExpression("audio.flatness")` emits opcode 33 and evaluates to the frame's value. `inspectorName == "Flatness"`.
