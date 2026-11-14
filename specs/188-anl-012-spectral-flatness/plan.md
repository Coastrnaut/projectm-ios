# Implementation Plan: ANL-012 Spectral Flatness

**Branch**: `feature/anl-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/188-anl-012-spectral-flatness/spec.md`

## Summary

A new value type `SpectralFlatnessEstimator` (file `SpectralFlatness.swift`) beside ANL-011's
rolloff computes the Wiener entropy of each ANL-001 spectrum over ANL-010's `SpectralBinRange`:
F = exp(mean(ln(P_k + ε))) / mean(P_k), P_k = m_k², ε = 10⁻¹²·mean(P_k), clamped to 0…1, 0 at
or below the −70 dB floor (research ANL-012-D1 to D6). The total power uses `vDSP_svesq` when
Accelerate is compiled in, a portable loop otherwise; the log sum is a portable Double loop. The
ANL-016 pipeline runs it on the frame's existing magnitudes after the rolloff and carries
`flatness` in every frame. MOD-002 gets `AudioFeatureSource.flatness` (`audio.flatness`, SHD-009
opcode 33); `LiveBandFrameInfo.flatness` and `NativeSpectrumHost.applyModulation(…flatness:…)` feed
it to the native visual's bindings; UIX-003's `inspectorName` reads "Flatness". Exactly ANL-011's
set of files.

1. **Package `Packages/AnalysisFeatures`**:
   - `SpectralFlatness.swift` (new): configuration (errors), reading, estimator, static `measure`. Contract C1-C2.
   - `AnalysisBusTypes.swift`, `AnalysisPipelineConfiguration.swift`, `AnalysisPipeline.swift`: frame
     field, configuration (sample-rate check), estimator, reset, value in the frame. Contract C3.
   - Tests: `SpectralFlatnessTests.swift` (sine vs noise acceptance, flat = 1, silence, NaN,
     backends, determinism, one pipeline run).
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.flatness`, `AudioFeatureFrame.flatness`;
   `ExpressionOpcode.flatness = 33`; compiler and evaluator cases; the closed-opcode-set test. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.flatness`.
4. **App**: `NativeSpectrumHost` keeps and passes the value; `inspectorName` case "Flatness"; app test
   `testFlatnessBindsAndDrivesTheGlow`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only (Accelerate optional, behind `ANALYSIS_NO_ACCELERATE`).
**Storage**: none new; a scene binding may store `audio.flatness`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`),
ParameterGraph and VisualGenerators on the host, app unit tests on simulator "ANL12 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS host, Linux for packages.
**Performance Goals**: one sum of squares plus one Double log pass over ≤ 1,024 bins per frame at N = 2,048; no extra FFT, no buffer.
**Constraints**: Constitution VII (no allocation, lock, log, clock per frame); VIII (nothing to projectM).
**Scale/Scope**: ~10 source files changed, 1 new source and 1 new test file.

## Constitution Check

- I (public APIs, compliance): pure Swift and public vDSP; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): a value type with no buffers; `process` allocates, locks, logs and reads no clock. PASS.
- VIII (engine boundary): analysis values never reach projectM. PASS.
- X (evidence): acceptance from synthetic PCM and reference spectra; the simulator only hosts app unit tests. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/188-anl-012-spectral-flatness/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{SpectralFlatness,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralFlatnessTests.swift
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
