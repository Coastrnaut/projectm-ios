# Implementation Plan: ANL-001 Windowed FFT

**Branch**: `feature/anl-001` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-anl-001-windowed-fft/spec.md`

## Summary

1. **AnalysisFeatures** (new package, depends on AudioCore; research ANL-001-D2): `FFTSize`,
   `ChannelMode`, `SpectrumConfiguration`, `SpectrumAnalyzer` (sanitize + periodic Hann + real FFT +
   linear-amplitude scaling), `SpectrumStream` (mono FIFO, hop, frame index and monotonic timestamp,
   pull from a `NormalizedPCMReader`), `SpectrumMath.decibels`. Two FFT backends: vDSP on Apple
   platforms, a portable radix-2 real FFT everywhere (research ANL-001-D3); runtime-selectable for
   tests, Accelerate compiled out with `-DANALYSIS_NO_ACCELERATE`.
2. **AudioCore** (minimal): an optional analysis tap in `NormalizedPCMRing` (research ANL-001-D7),
   off by default, so projectM's input is unchanged.
3. **Tests**: AUD-016 fixture acceptance (every sine fixture × 5 sizes × 2 rates; sweeps; silence),
   determinism, normalization, sanitizing, backend agreement, reference DFT, streaming/hop/size
   changes, tap behaviour.
4. **Bench**: `AnalysisBench` executable for CPU per frame and an Instruments allocation check.
5. **CI**: `AnalysisFeatures` added to every package loop in `.github/workflows/ios-ci.yml`.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2

**Primary Dependencies**: Foundation-free core (Swift stdlib + `Synchronization` via AudioCore);
Accelerate (vDSP) behind `canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`. No new dependency.

**Storage**: none (nothing persisted).

**Testing**: XCTest. `swift test` on the macOS host, also with `-Xswiftc -DANALYSIS_NO_ACCELERATE`;
`xcodebuild test` on the iOS 27.2 simulator; Linux in CI. AudioCore also with
`-DAUDIOCORE_NO_AVFAUDIO`.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (package platforms match AudioCore), Linux (CI).

**Project Type**: SwiftPM library package within the iOS app repository.

**Performance Goals**: 8,192-point frame well under 1 % of one core in real time at the default hop
on the host (reported by the bench, research ANL-001-D9).

**Constraints**: per-frame path allocation-, lock- and I/O-free (Constitution VII); runs on an
analysis worker, never on the audio callback or main thread; nothing into projectM (VIII).

**Scale/Scope**: about 600 lines of production Swift, 700 lines of tests, 20 lines in AudioCore.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Accelerate/vDSP C API, Swift stdlib, `Synchronization`; no private API, no `dlopen` | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI, no labels | Pass (n/a) |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Analysis in its own package; AudioCore change is a format-agnostic tap; no platform capture types | Pass |
| VII Real-time safety | Analysis on a worker; per-frame path preallocated; tap uses the existing bounded drop-oldest SPSC ring, only written on the existing work-queue producer | Pass |
| VIII ProjectM fidelity | Measured need recorded (research ANL-001-D1: no spectrum/beat getter in the 68 exported functions); projectM keeps `projectm_pcm_add_float`; nothing passed back (ANL-001-R12, ADR-0008 decision 5) | Pass |
| IX Dependencies | None added; FFT written in-house from the textbook radix-2 algorithm (no copied third-party code, so no license question) or Apple's Accelerate | Pass |
| X Evidence | Unit tests on host, Linux shape and simulator; CPU from a host bench; no device claim | Pass |
| Privacy | Nothing stored, recorded or sent; privacy policy unchanged | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/014-anl-001-windowed-fft/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/spectrum-analyzer.md
```

### Source Code (repository root)

```text
Packages/AnalysisFeatures/
  Package.swift
  Sources/AnalysisFeatures/
    FFTSize.swift  SpectrumConfiguration.swift  HannWindow.swift
    PortableRealFFT.swift  AcceleratedRealFFT.swift
    SpectrumAnalyzer.swift  SpectrumStream.swift  SpectrumMath.swift
  Sources/AnalysisBench/main.swift
  Tests/AnalysisFeaturesTests/
    FFTSizeTests.swift  SpectrumAnalyzerTests.swift  BackendAgreementTests.swift
    ReferenceDFTTests.swift  FixtureAcceptanceTests.swift  SpectrumStreamTests.swift
    TestSupport.swift
Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift   (analysis tap)
Packages/AudioCore/Tests/AudioCoreTests/AnalysisTapTests.swift
.github/workflows/ios-ci.yml   (AnalysisFeatures in the five package loops)
```

`project.yml` is unchanged (the app does not link the package yet). `AppCoordinator.swift`,
`scripts/test_scripts.py` and CaptureKit are not touched.

**Structure Decision**: new `AnalysisFeatures` package per the roadmap layout (research ANL-001-D2),
with a minimal AudioCore extension for the tap.

## Test design (deterministic)

- Inputs are AUD-016 fixtures (bit-identical generator) or closed-form synthetic signals built in
  the tests; no randomness except a fixed-seed LCG for noise.
- Exact equality for determinism (bitwise compare of Float arrays), exact bin indices for peaks;
  tolerances only where floating point needs them (scale ±1e-4, backend/DFT agreement 1e-5·peak).
- No wall clock: frame timestamps come from an injected counter clock; CPU is measured only by the
  bench.
- No Accelerate, AVFAudio or SwiftUI types in tests outside `#if` guards; the whole test target is
  run with `-DANALYSIS_NO_ACCELERATE`.
- Red run first: tests are written against missing symbols and fail to compile (recorded in
  tasks.md).

## Persistence and rollback

No persistence, no migration. Rollback is reverting the feature's commits: the package is not
linked by the app, and the AudioCore tap is off by default, so removing it changes no behaviour.

## Complexity Tracking

None.
