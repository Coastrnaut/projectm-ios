# Implementation Plan: ANL-002 Log-frequency Bands

**Branch**: `feature/anl-002` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/016-anl-002-log-frequency-bands/spec.md`

## Summary

Extend the existing `AnalysisFeatures` package (ANL-001); no new package, no AudioCore change.

1. **`BandCount`** (16, 32, 64, 128) and **`BandLayout`**: the precomputed table for one (band count,
   FFT size, sample rate): log-spaced edges 20 Hz … min(20 kHz, Nyquist), per band the first bin,
   the bin count, overlap weights and the scale `1 / (1.5 · min(1, width in bins))` (research
   ANL-002-D1 to D4). Inspectable (edges, centre, width, bins, weights, band of a frequency, owner
   band of a bin). Built in Double, stored as Float.
2. **`BandReducer`**: builds the 20 layouts (4 counts × 5 sizes) of one sample rate at init plus a
   4,097-value power scratch; `reduce(magnitudes:size:bandCount:into:)` sanitizes and squares the
   bins once, then one weighted dot product per band (vDSP `vDSP_dotpr` or a portable loop), times
   the band's scale, square root (research ANL-002-D5). No allocation per frame or per switch.
3. **`BandScale` / `BandMath`**: pure normalizers to 0…1 (linear with a reference, decibel with a
   floor; research ANL-002-D6).
4. **Tests** (written first): layout tests (edges, coverage, no empty band, ownership, errors),
   reducer tests (zero, sanitizing, sine-in-band reads A, sub-bin bands, array vs pointer, switching),
   the multi-tone acceptance matrix (6 tones × 4 counts × 5 sizes × 2 rates, every backend), silence
   through the stream, determinism over whole loops, backend agreement, normalizers.
5. **Bench**: one more section in `Bench/Sources/AnalysisBench/main.swift` (ns per reduction).
6. **Contract**: `contracts/band-reducer.md` (new), referenced from ANL-001's contract hand-off by
   this spec; ANL-001's contract is not changed.

CI needs no change: `AnalysisFeatures` is already in every package loop of `ios-ci.yml` (ANL-001-T22).
`project.yml` and `scripts/test_scripts.py` are not touched.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2

**Primary Dependencies**: Swift stdlib; Accelerate (`vDSP_dotpr`) behind
`canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`; ANL-001's `FFTSize`, `SpectrumBackend`. AudioCore
only in tests (tone generator, catalog). No new dependency.

**Storage**: none (nothing persisted).

**Testing**: XCTest. `swift test` on the macOS host, also with `-Xswiftc -DANALYSIS_NO_ACCELERATE`;
`xcodebuild test -scheme AnalysisFeatures` on the iOS 27.2 simulator; Linux in CI.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+, Linux (CI).

**Project Type**: SwiftPM library package within the iOS app repository.

**Performance Goals**: a reduction costs a small fraction of the spectrum it reduces (at most
~4,100 multiply-adds plus 128 square roots); reported by the bench, never asserted.

**Constraints**: per-frame path allocation-, lock-, log- and I/O-free (Constitution VII); the reducer
is not `Sendable` and is confined to the analysis worker; nothing into projectM (VIII, ADR-0008
decision 5); every test runs on Linux.

**Scale/Scope**: about 350 lines of production Swift, 600 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Swift stdlib and Accelerate's public `vDSP_dotpr` | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI, no labels | Pass (n/a) |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Inside `AnalysisFeatures`; consumes only ANL-001's public types | Pass |
| VII Real-time safety | Tables and scratch built at init; reduce reads/writes preallocated memory only; runs on the analysis worker | Pass |
| VIII ProjectM fidelity | Feeds only native generators and the modulation graph (ADR-0008 decision 5); package not linked by the app; projectM keeps its own analysis | Pass |
| IX Dependencies | None added; formulas written in-house | Pass |
| X Evidence | Host, Linux shape and simulator tests; bench on host; no device claim | Pass |
| Privacy | Nothing stored, recorded or sent | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/016-anl-002-log-frequency-bands/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/band-reducer.md
```

### Source Code (repository root)

```text
Packages/AnalysisFeatures/
  Sources/AnalysisFeatures/
    BandLayout.swift      (BandCount, BandLayoutError, BandLayout)
    BandReducer.swift     (BandReducer, portable and vDSP dot products)
    BandMath.swift        (BandScale, BandMath normalizers)
  Tests/AnalysisFeaturesTests/
    BandLayoutTests.swift  BandReducerTests.swift  BandAcceptanceTests.swift
    BandTestSupport.swift  (independent edge/ownership oracle, multi-tone builder)
  Bench/Sources/AnalysisBench/main.swift   (band reduction section)
```

**Structure Decision**: extend `AnalysisFeatures` (the roadmap's analysis package); three new source
files, ANL-001 files unchanged.

## Test design (deterministic)

- Inputs: AUD-016 `ToneGenerator` sines (bit-identical generator), the catalog silence fixture, and
  closed-form synthetic spectra; no randomness except ANL-001's fixed-seed LCG noise.
- The test's oracle recomputes edges (`20 · (upper/20)^(i/B)`) and bin ownership in Double from the
  formulas in the spec, without calling `BandLayout`; the expected band of a tone is the owner of
  the catalog's `nearestBin`.
- Exact equality for zero (`bitPattern == 0`) and determinism (bitwise compare); tolerances only
  for amplitude (2 %), "low" (2 % of tone amplitude) and backend agreement (1e-5·max + 1e-7).
- No wall clock, no timing assertion; the acceptance matrix is printed to the log.
- No Accelerate, AVFAudio or SwiftUI in tests; the whole target also runs with
  `-DANALYSIS_NO_ACCELERATE`. Test classes are not `@MainActor`.
- Red run first: the tests are written against missing symbols and fail to compile (recorded in
  tasks.md).
- Runtime budget: the acceptance suite analyses first windows (cheap) and whole loops only for the
  determinism check at two sizes per rate; total runtime is measured and reported.

## Persistence and rollback

No persistence, no migration, no stored settings. Rollback is reverting the feature's commits: the
package is not linked by the app and no existing file's behaviour changes (only new files plus a
bench section), so removal restores ANL-001 exactly.

## Complexity Tracking

None.
