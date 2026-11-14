# Implementation Plan: ANL-013 Stereo Correlation

**Branch**: `feature/anl-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/196-anl-013-stereo-correlation/spec.md`

## Summary

A new value type `StereoCorrelationMeter` (file `StereoCorrelation.swift`) in AnalysisFeatures reads
interleaved stereo chunks, accumulates Σ L·R, Σ L², Σ R² per 1,024-frame block in Double, smooths the
sums (τ = 0.1 s on the sample clock), and publishes r = S_LR / √(S_LL·S_RR) in −1…1 (0 at or below
the −70 dB per-channel floor), plus a phase-inversion warning with threshold and time hysteresis
(raise r < −0.5 for 44 blocks, clear r > −0.3 for 44 blocks) (research ANL-013-D1 to D5). The
ANL-016 pipeline feeds it every chunk it reads before the mono mix and carries `correlation` and
`phaseInverted` in every frame. MOD-002 gets `AudioFeatureSource.correlation` (`audio.correlation`,
value (r + 1)/2, SHD-009 opcode 34); `LiveBandFrameInfo` and `NativeSpectrumHost` feed it to the
bindings and report warning changes; the app shows the warning in the source status and the
performance overlay and announces it as status events X3a/X3b, throttled.

1. **Package `Packages/AnalysisFeatures`**:
   - `StereoCorrelation.swift` (new): configuration (errors), reading, meter. Contract C1-C2.
   - `AnalysisBusTypes.swift`, `AnalysisPipelineConfiguration.swift`, `AnalysisPipeline.swift`: frame
     fields, configuration (sample-rate check), meter fed per chunk, reset per session. Contract C3.
   - Tests: `StereoCorrelationTests.swift`.
2. **Package `Packages/ParameterGraph`**: source, frame field, opcode 34, compiler/evaluator, closed-set test. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.correlation`, `.phaseInverted`.
4. **App**: `NativeSpectrumHost` (value, reset, `onPhaseWarningChange`); `AppCoordinator+StereoPhase.swift`
   (new: state, throttle, status texts, overlay line); `SourceStatusIndicator.text(… phaseWarning:)`;
   `StatusEventCatalog.stereoPhase(_:)` (X3a, X3b); `PerformanceOverlay` stereo line; `inspectorName`
   "Correlation"; contract row in ACC-011's status-events contract; app tests. Contract C5.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only.
**Storage**: none new; a scene binding may store `audio.correlation`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape, ParameterGraph and VisualGenerators on the host, app unit tests on simulator "ANL13 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS host, Linux for packages.
**Performance Goals**: three Double multiply-adds per stereo frame; one sqrt per 1,024 frames.
**Constraints**: Constitution VII (no allocation, lock, log, clock in processing); VIII (nothing to projectM).
**Scale/Scope**: ~14 source files changed, 2 new sources, 2 new test files.

## Constitution Check

- I (public APIs, compliance): pure Swift; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): value type, no buffers; nothing on the audio callback (the pipeline's worker). PASS.
- VIII (engine boundary): values never reach projectM. PASS.
- X (evidence): synthetic PCM; the simulator only hosts app unit tests. PASS.
- Accessibility (FR-070, ACC-011): the warning is text (not colour), in the indicator's label, announced through the router. PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/196-anl-013-stereo-correlation/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{StereoCorrelation,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/StereoCorrelationTests.swift
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift
Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift
Packages/ParameterGraph/Tests/{ParameterGraphTests,ParameterExpressionTests}/…
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Coordinators/{AppCoordinator,AppCoordinator+StereoPhase,StatusEvents,ParameterInspectorModel}.swift
Apps/projectM-iOS/Views/{SourceStatusIndicator,PerformanceOverlay,VisualizerView}.swift
Apps/projectM-iOS/Tests/{AudioFeatureBindingAppTests,StereoPhaseWarningTests}.swift
specs/100-acc-011-captioned-status-events/contracts/status-events.md (rows X3a, X3b)
```

## Complexity Tracking

None.
