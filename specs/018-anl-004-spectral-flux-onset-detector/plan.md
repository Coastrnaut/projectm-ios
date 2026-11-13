# Implementation Plan: ANL-004 Spectral Flux Onset Detector

**Branch**: `feature/anl-004` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-anl-004-spectral-flux-onset-detector/spec.md`

## Summary

Extend the existing `AnalysisFeatures` package (ANL-001, ANL-002); no new package, no AudioCore
change, no app change.

1. **ANL-001 deltas (additive, defaults keep today's behavior)**:
   - `SpectrumFrame.hop` (new stored property; the public initializer gains `hop: Int? = nil`,
     nil = size/2), filled by `SpectrumStream.nextFrame()` with the hop it advanced by.
   - `SpectrumLeadIn` (`.none` default, `.silence`) on `SpectrumStream.init`: with `.silence` the
     FIFO starts (at init and after `reset()`) with `size − hop` zeros and the first frame index is
     `−(size − hop)` (research ANL-004-D4).
2. **`OnsetDetectorConfiguration`** + **`OnsetDetectorConfigurationError`**: validated parameters
   (sample rate, band count, floor, offset, multiplier, window, minimum inter-onset interval) with
   the defaults of spec Clarifications (research ANL-004-D3).
3. **`OnsetEvent`**: sequence, sample index, frame index, strength, threshold, sample rate, timestamp.
4. **`SpectralFluxOnsetDetector`**: owns a `BandReducer` for its sample rate and preallocated
   buffers (band values, previous normalized bands, current normalized bands, a 128-value flux
   history). `process(_:magnitudes:) -> OnsetEvent?` per frame: validate → reduce to bands →
   normalize (decibels with the floor) → rectified difference and mean (vDSP `vDSP_vsub`,
   `vDSP_vthres`, `vDSP_sve`, or portable loops) → threshold from the history mean → arm/IOI
   rule → event. `reset()`, `lastFlux`, `lastThreshold`, `processedFrames`, `ignoredFrames`.
5. **Tests first**: stream deltas, configuration validation, detector unit behaviour (synthetic
   spectra), fixture acceptance (pulses × sizes × hops × rates × backends, printed matrix), silence
   and below-floor noise, sines and sweeps, quieter pulses and unit impulses, loud noise bound,
   determinism and backend agreement.
6. **Bench**: one more section (ns per `process` call, 2,048 and 8,192 points, both backends).
7. **Contract**: `contracts/onset-detector.md` (new) plus an "Amended by ANL-004" note in ANL-001's
   contract for the two stream deltas.

CI needs no change: `AnalysisFeatures` is already in every package loop of `ios-ci.yml`.
`project.yml` and `scripts/test_scripts.py` are not touched.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2

**Primary Dependencies**: Swift stdlib; Accelerate (`vDSP_vsub`, `vDSP_vthres`, `vDSP_sve`) behind
`canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`; ANL-001's stream and ANL-002's `BandReducer` and
`BandMath`. AudioCore in tests only (catalog fixtures). No new dependency.

**Storage**: none (nothing persisted).

**Testing**: XCTest. `swift test` on the macOS host, also with `-Xswiftc -DANALYSIS_NO_ACCELERATE`;
`xcodebuild test -scheme AnalysisFeatures` on the iOS 27.2 simulator; Linux in CI.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+, Linux (CI).

**Project Type**: SwiftPM library package within the iOS app repository.

**Performance Goals**: one `process` costs one band reduction plus ~64 `log10f` and a few 64-value
vector operations: a small fraction of the spectrum it reads; reported by the bench, never asserted.

**Constraints**: per-frame path allocation-, lock-, log- and I/O-free (Constitution VII); the
detector is not `Sendable` and is confined to the analysis worker; nothing into projectM (VIII,
ADR-0008 decision 5); every test runs on Linux; no wall-clock or scheduling assertions.

**Scale/Scope**: about 300 lines of production Swift, 700 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Swift stdlib and Accelerate's public vDSP functions | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI, no labels | Pass (n/a) |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Inside `AnalysisFeatures`; consumes ANL-001/ANL-002 public types; stream deltas are additive | Pass |
| VII Real-time safety | All memory allocated in `init`; `process` reads/writes preallocated memory only; returns an optional value, never an array | Pass |
| VIII ProjectM fidelity | Onsets feed only native generators and the modulation graph (ADR-0008 decision 5; measured need: projectM exposes no beat output); package not linked by the app | Pass |
| IX Dependencies | None added; flux and thresholding written in-house from published formulas | Pass |
| X Evidence | Host, Linux shape and simulator tests; bench on host; no device claim | Pass |
| Privacy | Nothing stored, recorded or sent | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/018-anl-004-spectral-flux-onset-detector/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/onset-detector.md
```

### Source Code (repository root)

```text
Packages/AnalysisFeatures/
  Sources/AnalysisFeatures/
    SpectrumStream.swift              (delta: SpectrumFrame.hop, SpectrumLeadIn)
    OnsetDetectorConfiguration.swift  (configuration, errors, OnsetEvent)
    SpectralFluxOnsetDetector.swift   (detector, portable and vDSP flux)
  Tests/AnalysisFeaturesTests/
    SpectrumStreamLeadInTests.swift  OnsetConfigurationTests.swift  OnsetDetectorTests.swift
    OnsetAcceptanceTests.swift       OnsetTestSupport.swift
  Bench/Sources/AnalysisBench/main.swift   (onset section)
```

**Structure Decision**: extend `AnalysisFeatures` (the roadmap's analysis package); two new source
files and one additive change to `SpectrumStream.swift`.

## Test design (deterministic)

- Inputs: the AUD-016 catalog loops (bit-identical generator) at 44.1 and 48 kHz, closed-form
  synthetic spectra, and the test target's fixed-seed LCG noise; no other randomness.
- Ground truth: `ReferenceToneFixture.onsetFrames(sampleRate:)` (the catalog's documented frames).
  Matching: walk events and onsets in order; an event matches the first unmatched onset within
  ±hop; misses and unmatched events are counted separately; the largest |error| is reported.
- Exact checks: zero events and `lastFlux == 0` bitwise for silence and below-floor noise; event
  lists compared field by field (strength by bit pattern) for repeated runs; across backends
  everything but strength exact, strength within 1e-4.
- No wall clock, no timing assertion; streams use `clock: { 0 }`; the matrix is printed to the log.
- No Accelerate, AVFAudio or SwiftUI in tests; the whole target also runs with
  `-DANALYSIS_NO_ACCELERATE`. Test classes are not `@MainActor`; no `setUp`/`tearDown` state.
- Red run first: the tests are written against missing symbols and fail to compile (recorded).
- Runtime budget: the full matrix (90 pulse runs per backend, plus sines, sweeps, silence and
  noise) analyses ~10 s loops with the release-like inner loops of ANL-001; total test time is
  measured on the host and simulator and reported. Mono loops are generated once per fixture and
  rate and reused.

## Persistence and rollback

No persistence, no migration, no stored settings. Rollback is reverting the feature's commits: the
package is not linked by the app; the stream deltas default to today's behavior (every existing
test passes unchanged), so removal restores ANL-002's state exactly.

## Complexity Tracking

None.
