# Implementation Plan: ANL-007 Kick Energy Detector

**Branch**: `feature/anl-007` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/090-anl-007-kick-energy-detector/spec.md`

## Summary

A reusable `BandTransientDetector` in `Packages/AnalysisFeatures`, configured by a
`TransientDetectorConfiguration` (`.kick` = 40–150 Hz), reads ANL-001 magnitudes per frame, sums
the band's power with ANL-002's fractional bin weights, and fires when the band level rises
max(6 dB, 4·MAD) above the median of the preceding 1 s, above a −70 dB floor, holding at least
−20 dB of the frame's power, armed and outside a 100 ms refractory period. It keeps a 0…1
envelope (1 on an event, 100 ms time constant). The ANL-016 pipeline runs it after the onset
detector, publishes `AnalysisEventKind.transient(band: .kick, …)` and carries `kickEnvelope` in
every `AnalysisFrame`. MOD-002 gets `AudioFeatureSource.kick` (`audio.kick`) and SHD-009 opcode 9;
the native visual feeds the envelope to its bindings.

1. **Package `Packages/AnalysisFeatures`** (pure Swift, Accelerate optional):
   - `TransientDetectorConfiguration.swift`: `TransientBand` (`kick`), `TransientDetectorConfigurationError`,
     `TransientDetectorConfiguration` (`.kick`, validating init, `baselineFrames(hop:)`,
     `refractorySamples`, `envelopeDecay(hop:)`), `TransientEvent`. Contract C1.
   - `BandTransientDetector.swift`: per-size weight tables built in `init`; `process(_:magnitudes:)`,
     `reset()`, `envelope`, `lastLevel`, `lastRise`, `lastThreshold`, `lastShare`, counters.
     Contract C2.
   - `AnalysisBusTypes.swift`: `AnalysisEventKind.transient(band:strength:threshold:level:)`;
     `AnalysisFrame.kickEnvelope` (init parameter defaulted to 0, so existing callers compile).
   - `AnalysisPipelineConfiguration.swift`: `kick: TransientDetectorConfiguration = .kick`, rate
     checked like the others. `AnalysisPipeline.swift`: owns the detector, resets it per session,
     runs it per frame, publishes the event after the beat. Contract C3.
   - Tests: `TransientTestSupport.swift` (fixtures: decaying sine bursts on hop-aligned starts,
     sustained tones, seeded noise; a runner through a lead-in stream) and
     `KickDetectorTests.swift` (acceptance, level independence, kick under a pad, sustained bass,
     silence/dither/noise, refractory, configuration validation, pipeline end-to-end).
2. **Package `Packages/PerformanceControl`**: `TempoEstimateTracker.observe` ignores `.transient`
   (one case added to its exhaustive switch).
3. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.kick` (`audio.kick`, reads
   `AudioFeatureFrame.kick`), `AudioFeatureFrame.kick: Float?`; `ExpressionOpcode.kick = 9`
   (compiler and evaluator); tests in `AudioFeatureSourceTests`, the opcode list in
   `ExpressionPathologicalTests`, an expression test. Contract C4.
4. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.kickEnvelope`.
5. **App**: `NativeSpectrumHost` keeps the last kick envelope read and passes it in
   `AudioFeatureFrame(bands:kick:)`; `applyModulation(bands:kick:timeNanoseconds:)` (kick defaulted
   to nil). Test: `AudioFeatureBindingAppTests` gains "Kick binds and drives the glow".

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2; CI also builds with
Xcode 26 and Linux Swift.

**Primary Dependencies**: existing AnalysisFeatures, AudioCore (test fixtures, ring), ParameterGraph,
VisualGenerators, PerformanceControl. No new dependency.

**Storage**: none new; a scene binding may store the source ID `audio.kick` (existing format, MOD-013).

**Testing**: XCTest. `swift test --package-path Packages/AnalysisFeatures` on the host and in the
Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`); ParameterGraph, PerformanceControl and
VisualGenerators suites on the host (VisualGenerators also `-DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE`); app unit tests (`-only-testing:projectM-iOSTests`) on a dedicated
iOS 27.2 simulator "ANL7 iPhone 17", created and deleted for this row.

**Target Platform**: iOS/iPadOS 26.0+; packages also macOS 15 and Linux.

**Performance Goals**: per frame (86 Hz): one weighted sum over ≤ 8 bins at N=2048 (≤ 26 at
8,192), one sum of squares over the frame's bins (1,025 at N=2048), an insertion into an 86-entry
sorted window and one 86-entry deviation selection: on the order of 10 µs, on the analysis
worker, never the audio callback.

**Constraints**: owner rule 7 (the AnalysisFeatures Linux-shape suite already takes about 81 s,
so the new tests must add only a few hundred milliseconds: ≤ 4 s of synthetic audio each, a few
representative cases, no sweeps); explicit closure types, typed arithmetic steps; no C stdio
globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; no Simulator panel
tool (rule 8).

**Scale/Scope**: one detector per pipeline; ~350 lines of production code, ~300 of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Swift, optional Accelerate (`vDSP_svesq`) behind the existing flag. |
| VI. Modular boundaries | Pass: detection in AnalysisFeatures; ParameterGraph stays independent of analysis types (the frame carries a plain Float). |
| VII. Real-time audio safety | Pass: runs on the analysis worker; all buffers preallocated in `init`; `process` allocates, locks, logs nothing. |
| VIII. Upstream projectM fidelity | Pass: nothing reaches projectM (ADR-0008 decision 5). |
| X. Evidence-based quality | Pass: deterministic synthetic-PCM tests with sample clocks and fixed seeds; the simulator only for the app binding test. |

Post-design re-check: unchanged (no ADR needed: no default is overridden; the new event kind and
source extend existing contracts additively).

## Project Structure

```text
specs/090-anl-007-kick-energy-detector/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/transient-detector.md
└── checklists/requirements.md
Packages/AnalysisFeatures/Sources/AnalysisFeatures/
├── TransientDetectorConfiguration.swift   (new)
├── BandTransientDetector.swift            (new)
├── AnalysisBusTypes.swift, AnalysisPipeline.swift, AnalysisPipelineConfiguration.swift (edited)
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/
├── TransientTestSupport.swift, KickDetectorTests.swift (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift (edited)
Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift (edited)
Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift (edited)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift (edited)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift (edited)
```

## Complexity Tracking

None.
