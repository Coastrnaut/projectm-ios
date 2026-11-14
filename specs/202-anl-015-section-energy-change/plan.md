# Implementation Plan: ANL-015 Section Energy Change

**Branch**: `feature/anl-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/202-anl-015-section-energy-change/spec.md`

## Summary

A new value type `SectionChangeDetector` (file `SectionEnergyChange.swift`) in AnalysisFeatures reads
ANL-014's per-frame K-weighted level, keeps the last 35 frame powers in a fixed inline buffer, and
derives the slow level (dB of their mean power), a reference level (settled over the first 2 s,
then an 8 s one-pole follower, frozen while a change is pending), and a change state machine: enter
at ±6 dB, hold beyond ±3 dB, fire after a 2.0 s dwell counted in samples, then a 4.0 s refractory
(research ANL-015-D1 to D5). Each fired change is a `SectionChange` value (direction, slow level,
old reference, start and confirmation samples) and sets a 0…1 envelope to 1 that decays with a
1.0 s time constant. The ANL-016 pipeline runs it on every frame after the loudness envelope, carries
`sectionChangeEnvelope` and `sectionLevelDecibels` in every frame, and publishes
`AnalysisEventKind.sectionChange` after the frame's other events. MOD-002 gets
`AudioFeatureSource.sectionChange` (`audio.sectionChange`, SHD-009 opcode 35); `LiveBandFrameInfo`
and `NativeSpectrumHost` feed it to the bindings; the inspector names it "Section change".

1. **Package `Packages/AnalysisFeatures`**:
   - `SectionEnergyChange.swift` (new): configuration (errors), direction, change, detector. Contract C1-C3.
   - `AnalysisBusTypes.swift`, `AnalysisPipelineConfiguration.swift`, `AnalysisPipeline.swift`: event
     kind, frame fields, configuration (sample-rate and hop check), detector per frame, reset per session. Contract C4.
   - Tests: `SectionEnergyChangeTests.swift`; the event-kind switch in the test support if exhaustive.
2. **Package `Packages/PerformanceControl`** (`PerformanceControlAnalysis.TempoEstimateTracker`): add the new kind to its exhaustive switch (ignored).
3. **Package `Packages/ParameterGraph`**: source, frame field, opcode 35, compiler/evaluator, tests. Contract C5.
4. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.sectionChange`.
5. **App**: `NativeSpectrumHost` (value, reset, feed); `ParameterInspectorModel.inspectorName` "Section change"; app unit test in `AudioFeatureBindingAppTests`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only.
**Storage**: none new; a scene binding may store `audio.sectionChange`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape (`-DANALYSIS_NO_ACCELERATE`), ParameterGraph and PerformanceControl on the host, app unit tests on simulator "ANL15 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS host, Linux for packages.
**Performance Goals**: per frame (every 11.6 ms) one `pow`, one `log10`, 35 Double adds; negligible next to the FFT.
**Constraints**: Constitution VII (no allocation, lock, log, clock in processing); VIII (nothing to projectM).
**Scale/Scope**: ~12 source files changed, 1 new source, 1 new test file.

## Constitution Check

- I (public APIs, compliance): pure Swift; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): value type whose 35-entry history is allocated once at creation and written in place (one owner, never copied); runs on the pipeline worker, never on the audio callback. PASS.
- VIII (engine boundary): values never reach projectM. PASS.
- X (evidence): synthetic PCM; the simulator only hosts app unit tests; real-music behaviour is a device observation. PASS.
- Accessibility (ACC-011): no status text added (a musical event, not status; spec Clarifications). PASS.

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/202-anl-015-section-energy-change/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{SectionEnergyChange,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/SectionEnergyChangeTests.swift
Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift
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
