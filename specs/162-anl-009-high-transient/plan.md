# Implementation Plan: ANL-009 High-Frequency Transient Detector

**Branch**: `feature/anl-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/162-anl-009-high-transient/spec.md`

## Summary

ANL-007's `BandTransientDetector` gains a third configuration, `.highTransient` (6,000–16,000 Hz,
dominance −6 dB, 40 ms refractory, 50 ms envelope, breadth weight 1), and a general event-rate cap
(`maximumEventsPerSecond`, research ANL-009-D2) that only the high transient uses (12). The ANL-016
pipeline runs a third detector instance on the same magnitudes after the mid transient, publishes
`.transient(band: .highTransient, …)` and carries `highTransientEnvelope`, `highTransientConfidence`
(and their product `highTransient`) in every frame. MOD-002 gets `AudioFeatureSource.highTransient`
(`audio.highTransient`, SHD-009 opcode 18); `LiveBandFrameInfo.highTransient` and
`NativeSpectrumHost.applyModulation(…highTransient:…)` feed it to the native visual's bindings;
UIX-003's `inspectorName` names it. Exactly ANL-008's set of files.

1. **Package `Packages/AnalysisFeatures`**:
   - `TransientDetectorConfiguration.swift`: `TransientBand.highTransient`; field
     `maximumEventsPerSecond` (0…64, error `.invalidMaximumEventRate`), `rateWindowSamples`;
     `.highTransient` preset; `.kick`/`.midTransient` get 0. Contract C1.
   - `BandTransientDetector.swift`: a preallocated ring of the last N event samples;
     `rateLimitedEvents`; the cap checked after the refractory test; reset clears the ring. Contract C2.
   - `AnalysisBusTypes.swift`, `AnalysisPipelineConfiguration.swift`, `AnalysisPipeline.swift`:
     frame fields, configuration, detector, reset, publish after the mid transient. Contract C3.
   - Tests: `HighTransientTestSupport.swift` (high-pass noise clicks, continuous high noise, a
     1 s span counter) and `HighTransientDetectorTests.swift`.
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.highTransient`,
   `AudioFeatureFrame.highTransient`; `ExpressionOpcode.highTransient = 18`. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.highTransient`.
4. **App**: `NativeSpectrumHost` keeps and passes the value; `ParameterInspectorModel.inspectorName`
   case; app test `testHighTransientBindsAndDrivesTheGlow`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0), Xcode 27.2; CI also Xcode 26 and Linux Swift.
**Primary Dependencies**: existing packages only.
**Storage**: none new; a scene binding may store `audio.highTransient`.
**Testing**: XCTest; AnalysisFeatures on the host and in the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`),
ParameterGraph and VisualGenerators on the host, app unit tests on simulator "ANL9 iPhone 17" (iOS 27.2).
**Target Platform**: iOS 26+ (app), macOS 15 host, Linux for packages.
**Performance Goals**: one extra band sum per frame (≈ 465 bins at N = 2,048), flatness only on event frames, the cap check is O(1); no extra FFT.
**Constraints**: Constitution VII (no allocation, lock, log, clock per frame); VIII (nothing to projectM).
**Scale/Scope**: ~10 source files changed, 2 new test files.

## Constitution Check

- I/II (public APIs, compliance): pure Swift and optional vDSP; no networking. PASS.
- VI (module boundaries): ParameterGraph stays independent of AnalysisFeatures (a Float in the frame). PASS.
- VII (real-time): the rate ring is allocated in `init`; `process` stays allocation-free. PASS.
- VIII (engine boundary): analysis values never reach projectM. PASS.
- Evidence honesty: no instrument identity claimed; simulator used only for app unit tests. PASS.

## Project Structure

```text
specs/162-anl-009-high-transient/  spec, plan, research, data-model, contracts/, quickstart, tasks
Packages/AnalysisFeatures/Sources/AnalysisFeatures/{TransientDetectorConfiguration,BandTransientDetector,AnalysisBusTypes,AnalysisPipeline,AnalysisPipelineConfiguration}.swift
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/{HighTransientTestSupport,HighTransientDetectorTests}.swift
Packages/ParameterGraph/Sources/{ParameterGraph/AudioFeatureSource,ParameterExpression/CompiledExpression,ParameterExpression/ExpressionCompiler}.swift (+ tests)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Apps/projectM-iOS/Coordinators/ParameterInspectorModel.swift, Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift
```

## Complexity Tracking

None.
