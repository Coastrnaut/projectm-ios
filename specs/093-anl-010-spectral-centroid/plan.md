# Implementation Plan: ANL-010 Spectral Centroid

**Branch**: `feature/anl-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/093-anl-010-spectral-centroid/spec.md`

## Summary

A `SpectralCentroidEstimator` in `Packages/AnalysisFeatures`, configured by a
`SpectralCentroidConfiguration` (`.standard`: 20 Hz to Nyquist, −70 dB floor, log normalization
50 Hz–10 kHz), reads ANL-001 magnitudes per frame and computes the power-weighted centroid
C = Σ f_k·m_k² / Σ m_k² over the bins a shared `SpectralBinRange` selects (whole bins, DC excluded,
the frame's own size and rate). Above the floor it returns C in Hz and
n = clamp(log2(C/50)/log2(200), 0, 1); at or below it holds the last values (0 and 0 before any
signal). No smoothing. The ANL-016 pipeline runs it on every frame and carries `centroidHz` and
`centroid` in every `AnalysisFrame`, resetting it per session. MOD-002 gets
`AudioFeatureSource.centroid` (`audio.centroid`) and SHD-009 opcode 15; the native visual feeds the
normalized value to its bindings.

1. **Package `Packages/AnalysisFeatures`** (pure Swift; no Accelerate needed: one pass over ≤ 4,096
   bins):
   - `SpectralBinRange.swift` (new): the whole bins of a frequency range at a size and rate, DC
     excluded; the helper ANL-011 (rolloff) and ANL-012 (flatness) will reuse. Contract C1.
   - `SpectralCentroid.swift` (new): `SpectralCentroidConfigurationError`,
     `SpectralCentroidConfiguration` (`.standard`, validating init, `normalized(hz:)`,
     `floorPower`), `SpectralCentroidReading`, `SpectralCentroidEstimator` (`process(_:magnitudes:)`,
     `reset()`, `reading`, static `measure(magnitudes:size:sampleRate:range:)`). Contract C2.
   - `AnalysisBusTypes.swift`: `AnalysisFrame.centroidHz`, `AnalysisFrame.centroid` (init
     parameters defaulted to 0, so existing callers compile).
   - `AnalysisPipelineConfiguration.swift`: `centroid: SpectralCentroidConfiguration = .standard`,
     rate checked like the others. `AnalysisPipeline.swift`: owns the estimator, resets it per
     session, runs it per frame. Contract C3.
   - Tests: `SpectralCentroidTests.swift` (single-window fixtures through `SpectrumAnalyzer`: tone
     ladder, noise, two tones, sizes and rates, levels, silence rule, configuration, bin range;
     one short pipeline run).
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.centroid` (`audio.centroid`, reads
   `AudioFeatureFrame.centroid`), `AudioFeatureFrame.centroid: Float?`;
   `ExpressionOpcode.centroid = 15` (compiler and evaluator); tests in `AudioFeatureSourceTests`,
   `AudioFeatureModulatorTests`, `ExpressionEvaluationTests`. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.centroid`.
4. **App**: `NativeSpectrumHost` keeps the last centroid read and passes it in
   `AudioFeatureFrame(bands:kick:centroid:)`; `applyModulation(bands:kick:centroid:timeNanoseconds:)`
   (defaulted to nil). Test: `AudioFeatureBindingAppTests` gains "Centroid binds and drives the
   glow".

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2; CI also builds with
Xcode 26 and Linux Swift.

**Primary Dependencies**: existing AnalysisFeatures, AudioCore (ring, test fixtures), ParameterGraph,
VisualGenerators. No new dependency.

**Storage**: none new; a scene binding may store the source ID `audio.centroid` (existing format,
MOD-013).

**Testing**: XCTest. `swift test --package-path Packages/AnalysisFeatures` on the host and in the
Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`); ParameterGraph and VisualGenerators suites on the
host; the dependants VisualGenerators, PerformanceControl, Compositor, SceneFormat, RenderGoldens
and ShowControl built and tested as ANL-007 did; app unit tests (`-only-testing:projectM-iOSTests`)
on a dedicated iOS 27.2 simulator "ANL10 iPhone 17", created and deleted for this row.

**Target Platform**: iOS/iPadOS 26.0+; packages also macOS 15 and Linux.

**Performance Goals**: per frame (86 Hz): one pass of two multiply-adds over the analysed bins
(1,022 at N = 2,048), one log2: about 1-2 µs on the analysis worker, never the audio callback.

**Constraints**: owner rule 7 (the AnalysisFeatures Linux-shape suite already takes about 67 s; the
new tests add a few hundred ms: single windows through the analyzer rather than streams, one
pipeline run of ≤ 0.5 s of audio); explicit closure types, typed arithmetic steps; no C stdio
globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; no Simulator panel
tool (rule 8).

**Scale/Scope**: ~200 lines of production code, ~250 of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: plain Swift (Foundation-free arithmetic, `log2` from the C library modules already used). |
| VI. Modular boundaries | Pass: the estimate lives in AnalysisFeatures; ParameterGraph stays independent of analysis types (the frame carries a plain Float). |
| VII. Real-time audio safety | Pass: runs on the analysis worker; the estimator is a value with no buffers; `process` allocates, locks, logs nothing. |
| VIII. Upstream projectM fidelity | Pass: nothing reaches projectM (ADR-0008 decision 5). |
| X. Evidence-based quality | Pass: deterministic synthetic-PCM tests; the simulator only for the app binding test. |

Post-design re-check: unchanged. No ADR: no default is overridden; the frame fields, source and
opcode extend existing contracts additively.

## Project Structure

```text
specs/093-anl-010-spectral-centroid/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/spectral-centroid.md
└── checklists/requirements.md
Packages/AnalysisFeatures/Sources/AnalysisFeatures/
├── SpectralBinRange.swift, SpectralCentroid.swift              (new)
├── AnalysisBusTypes.swift, AnalysisPipeline.swift, AnalysisPipelineConfiguration.swift (edited)
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SpectralCentroidTests.swift (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift (edited)
Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift (edited)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift (edited)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift (edited)
```

## Complexity Tracking

None.
