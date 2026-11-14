# Implementation Plan: ANL-014 Loudness Envelope

**Branch**: `feature/anl-014` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/094-anl-014-loudness-envelope/spec.md`

## Summary

A `LoudnessEnvelope` in `Packages/AnalysisFeatures`, configured by a `LoudnessConfiguration`
(`.standard`: 44.1 kHz, −60…0 LKFS, attack 100 ms, release 400 ms) and an FFT size, reads ANL-001
magnitudes per frame. At `init` it builds the K-weighting power table for that size (one
`[Float]` of N/2 + 1 entries; `KWeighting` designs the BS.1770 shelf and high-pass for the rate,
typed steps). Per frame: z = Σ w_k·m_k² / 3 (bins 1…N/2), L = −0.691 + 10·log10 z (−120 at
silence), target n = clamp((L + 60)/60, 0, 1), then ANL-003's one-pole attack/release with
`SmoothingTimes.coefficient` (Δt = hop / rate), first frame snapped, exact 0 below 0.001. The
ANL-016 pipeline runs it per frame and carries `loudness` and `loudnessDecibels` in every
`AnalysisFrame`, resetting per session. MOD-002 gets `AudioFeatureSource.loudness`
(`audio.loudness`) and SHD-009 opcode 16; the native visual feeds the envelope to its bindings.

1. **Package `Packages/AnalysisFeatures`** (pure Swift; one pass over ≤ 4,097 bins):
   - `KWeighting.swift` (new): BS.1770 stage parameters, biquad design for a rate, power response
     at a frequency, the per-bin table. Contract C1.
   - `LoudnessEnvelope.swift` (new): `LoudnessConfigurationError`, `LoudnessConfiguration`
     (`.standard`, validating init, `normalized(decibels:)`), `LoudnessReading`, `LoudnessEnvelope`
     (`process(_:magnitudes:)`, `reset()`, `reading`, static `level(magnitudes:weights:)`). Contract C2.
   - `AnalysisBusTypes.swift`: `AnalysisFrame.loudness`, `AnalysisFrame.loudnessDecibels` (init
     parameters defaulted, so existing callers compile; `loudnessDecibels` defaults to −120).
   - `AnalysisPipelineConfiguration.swift`: `loudness: LoudnessConfiguration = .standard`, rate
     checked like the others; the pipeline builds the envelope for the spectrum's size. `AnalysisPipeline.swift`: owns
     the envelope, resets it per session, runs it per frame. Contract C3.
   - Tests: `LoudnessEnvelopeTests.swift` (weights against BS.1770 reference points, calibration,
     step lag, bounds, weighting order, monotonic, silence, pipeline).
2. **Package `Packages/ParameterGraph`**: `AudioFeatureSource.loudness`, `AudioFeatureFrame.loudness`,
   `ExpressionOpcode.loudness = 16`. Contract C4.
3. **Package `Packages/VisualGenerators`** (`VisualBandFeed`): `LiveBandFrameInfo.loudness`.
4. **App**: `NativeSpectrumHost` passes the last envelope read to `AudioFeatureFrame`;
   `applyModulation(bands:kick:centroid:loudness:timeNanoseconds:)` (defaulted). Test:
   `AudioFeatureBindingAppTests.testLoudnessBindsAndDrivesTheGlow`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2; CI also builds with
Xcode 26 and Linux Swift.

**Primary Dependencies**: existing AnalysisFeatures (ANL-001 spectra, ANL-003 `SmoothingTimes`),
AudioCore, ParameterGraph, VisualGenerators. No new dependency.

**Storage**: none new; a scene binding may store `audio.loudness` (existing format, MOD-013).

**Testing**: XCTest. `swift test --package-path Packages/AnalysisFeatures` on the host and in the
Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`); ParameterGraph; dependants VisualGenerators,
PerformanceControl, Compositor, SceneFormat, RenderGoldens, ShowControl; app unit tests
(`-only-testing:projectM-iOSTests`) on a dedicated iOS 27.2 simulator "ANL14 iPhone 17", created and
deleted for this row.

**Target Platform**: iOS/iPadOS 26.0+; packages also macOS 15 and Linux.

**Performance Goals**: per frame (86 Hz): 1,024 multiply-adds, one log10, one exp: about 1-2 µs on
the analysis worker, never the audio callback. The table (4 KB at 2,048 points) is built once.

**Constraints**: owner rule 7 (the Linux-shape suite is about 62-67 s; additions a few hundred ms:
the step test streams 1.5 s of audio through `SpectrumStream`, the rest are single windows or
direct magnitude vectors); explicit closure types, typed arithmetic steps (biquad formulas split
into typed lets); no C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock
assertions; no Simulator panel tool (rule 8).

**Scale/Scope**: ~250 lines of production code, ~300 of tests.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: plain Swift arithmetic (`tan`, `cos`, `log10`, `exp` from the C library modules already used). |
| VI. Modular boundaries | Pass: the envelope lives in AnalysisFeatures; ParameterGraph stays independent (plain Float on the frame); AudioCore's meter is untouched. |
| VII. Real-time audio safety | Pass: analysis worker only; the table is allocated in `init`; `process` allocates, locks, logs nothing. |
| VIII. Upstream projectM fidelity | Pass: nothing reaches projectM (ADR-0008 decision 5). |
| X. Evidence-based quality | Pass: deterministic synthetic-PCM tests; the simulator only for the app binding test. |

Post-design re-check: unchanged. No ADR: no default is overridden; the frame fields, source and
opcode extend existing contracts additively, and the meter keeps its behavior.

## Project Structure

```text
specs/094-anl-014-loudness-envelope/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/loudness-envelope.md
└── checklists/requirements.md
Packages/AnalysisFeatures/Sources/AnalysisFeatures/
├── KWeighting.swift, LoudnessEnvelope.swift                      (new)
├── AnalysisBusTypes.swift, AnalysisPipeline.swift, AnalysisPipelineConfiguration.swift (edited)
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/LoudnessEnvelopeTests.swift (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift (edited)
Packages/ParameterGraph/Sources/ParameterExpression/{CompiledExpression,ExpressionCompiler}.swift (edited)
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift (edited)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Apps/projectM-iOS/Tests/AudioFeatureBindingAppTests.swift (edited)
```

## Complexity Tracking

None.
