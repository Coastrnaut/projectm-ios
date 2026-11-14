# Implementation Plan: ANL-008 Mid Transient Detector

**Branch**: `feature/anl-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/137-anl-008-snare-transient/spec.md`

## Summary

ANL-007's `BandTransientDetector` gains a second configuration, `.midTransient` (1,000–4,000 Hz,
70 ms refractory, 80 ms envelope, breadth weight 1), and every transient event gains a confidence
√(margin · breadth′) (research ANL-008-D2). The ANL-016 pipeline runs a second detector instance on
the same magnitudes after the kick, publishes `.transient(band: .midTransient, …, confidence:)`,
and carries `midTransientEnvelope`, `midTransientConfidence` (and their product `midTransient`) in
every frame. MOD-002 gets `AudioFeatureSource.midTransient` (`audio.midTransient`, SHD-009 opcode
17); `LiveBandFrameInfo.midTransient` and `NativeSpectrumHost.applyModulation(…midTransient:…)`
feed it to the native visual's bindings.

1. **Package `Packages/AnalysisFeatures`**:
   - `TransientDetectorConfiguration.swift`: `TransientBand.midTransient`; configuration fields
     `breadthWeight` (0…1) and `confidenceMarginDecibels` (> 0, ≤ 40); `.midTransient` preset;
     `TransientEvent.confidence`. Contract C1.
   - `BandTransientDetector.swift`: `lastConfidence` (held), confidence on each event from the band
     squares already computed (flatness over the band's bins, only on event frames). Contract C2.
   - `AnalysisBusTypes.swift`: `.transient(band:strength:threshold:level:confidence:)`;
     `AnalysisFrame.midTransientEnvelope`, `midTransientConfidence`, computed `midTransient`.
   - `AnalysisPipelineConfiguration.swift` / `AnalysisPipeline.swift`: `midTransient` configuration
     and detector; reset per session; run after the kick; event published after the kick. Contract C3.
   - Tests: `MidTransientTestSupport.swift` (mid-band noise bursts) and `MidTransientDetectorTests.swift`.
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.midTransient`,
   `AudioFeatureFrame.midTransient`; `ExpressionOpcode.midTransient = 17` (compiler and evaluator).
   Minimal lines (MOD-004 edits binding mapping in parallel). Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.midTransient`.
4. **App**: `NativeSpectrumHost` keeps the newest value and passes it to `applyModulation`; app test
   `testMidTransientBindsAndDrivesTheGlow`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only.
**Storage**: none new; a scene binding may store `audio.midTransient`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`),
ParameterGraph and VisualGenerators on the host, app unit tests on simulator "ANL8 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS 15 host, Linux for packages.
**Performance Goals**: one extra band sum per frame (≈ 140 bins at N = 2,048) plus ≈ 140 `log` calls on event frames only; no extra FFT.
**Constraints**: Constitution VII (no allocation, lock, log, clock per frame); VIII (nothing to projectM).
**Scale/Scope**: ~6 source files changed, 2 new test files.

## Constitution Check

- I/II (public APIs, compliance): pure Swift and optional vDSP; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): preallocated; flatness uses the existing squares buffer. PASS.
- VIII (engine boundary): analysis values never reach projectM. PASS.
- Evidence honesty: no instrument identity claimed; simulator used only for app unit tests. PASS.

## Project Structure

```text
specs/137-anl-008-snare-transient/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{TransientDetectorConfiguration,BandTransientDetector,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/{MidTransientTestSupport,MidTransientDetectorTests,KickDetectorTests}.swift
Packages/ParameterGraph/Sources/{ParameterGraph/AudioFeatureSource,ParameterExpression/CompiledExpression,ParameterExpression/ExpressionCompiler}.swift (+ tests)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift
```

## Complexity Tracking

None.
