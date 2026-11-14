# Implementation Plan: ANL-011 Spectral Rolloff

**Branch**: `feature/anl-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/182-anl-011-spectral-rolloff/spec.md`

## Summary

A new value type `SpectralRolloffEstimator` (file `SpectralRolloff.swift`) beside ANL-010's
centroid computes the power-percentile frequency of each ANL-001 spectrum over ANL-010's
`SpectralBinRange`, with in-bin linear interpolation (research ANL-011-D2), a configurable fraction
p (0.85; 0.5…0.99), log normalization 50 Hz–20 kHz and 0 at silence. The total power uses
`vDSP_svesq` when Accelerate is compiled in, the portable loop otherwise; the cumulative scan is
portable. The ANL-016 pipeline runs it on the frame's existing magnitudes after the centroid and
carries `rolloffHz` and `rolloff` in every frame. MOD-002 gets `AudioFeatureSource.rolloff`
(`audio.rolloff`, SHD-009 opcode 19); `LiveBandFrameInfo.rolloff` and
`NativeSpectrumHost.applyModulation(…rolloff:…)` feed it to the native visual's bindings; UIX-003's
`inspectorName` reads "Rolloff". Exactly ANL-010's set of files.

1. **Package `Packages/AnalysisFeatures`**:
   - `SpectralRolloff.swift` (new): configuration (errors), reading, estimator, static `measure`. Contract C1-C2.
   - `AnalysisBusTypes.swift`, `AnalysisPipelineConfiguration.swift`, `AnalysisPipeline.swift`: frame
     fields, configuration (sample-rate check), estimator, reset, value in the frame. Contract C3.
   - Tests: `SpectralRolloffTests.swift` (reference spectra, fractions, silence, NaN, backends,
     determinism, one pipeline run).
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.rolloff`, `AudioFeatureFrame.rolloff`;
   `ExpressionOpcode.rolloff = 19`; compiler and evaluator cases. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.rolloff`.
4. **App**: `NativeSpectrumHost` keeps and passes the value; `inspectorName` case "Rolloff"; app test
   `testRolloffBindsAndDrivesTheGlow`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only (Accelerate optional, behind `ANALYSIS_NO_ACCELERATE`).
**Storage**: none new; a scene binding may store `audio.rolloff`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`),
ParameterGraph and VisualGenerators on the host, app unit tests on simulator "ANL11 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS host, Linux for packages.
**Performance Goals**: one sum of squares plus a partial scan over ≤ 1,024 bins per frame at N = 2,048; no extra FFT, no buffer.
**Constraints**: Constitution VII (no allocation, lock, log, clock per frame); VIII (nothing to projectM).
**Scale/Scope**: ~10 source files changed, 1 new source and 1 new test file.

## Constitution Check

- I (public APIs, compliance): pure Swift and public vDSP; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): a value type with no buffers; `process` allocates, locks, logs and reads no clock. PASS.
- VIII (engine boundary): analysis values never reach projectM. PASS.
- X (evidence): acceptance from analytic reference spectra; the simulator only hosts app unit tests. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/182-anl-011-spectral-rolloff/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{SpectralRolloff,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralRolloffTests.swift
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift
Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift
Packages/ParameterGraph/Tests/{ParameterGraphTests,ParameterExpressionTests}/…
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift
Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift
```

## Complexity Tracking

None.
