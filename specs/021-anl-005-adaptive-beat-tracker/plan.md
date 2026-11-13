# Implementation Plan: ANL-005 Adaptive Beat Tracker

**Branch**: `feature/anl-005` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/021-anl-005-adaptive-beat-tracker/spec.md`

## Summary

Extend the existing `AnalysisFeatures` package (ANL-001, ANL-002, ANL-004); no new package, no
change to any existing type, no AudioCore or app change.

1. **`BeatTrackerConfiguration`** + **`BeatTrackerConfigurationError`**: validated sample rate,
   tempo range, preferred tempo, window, timing tolerance and silence timeout (spec Clarifications;
   research ANL-005-D5).
2. **`BeatEstimate`** (tempo, period, anchor, next beat, confidence, matched beats, onsets in
   window, sample rate, position) and **`BeatEvent`** (sequence, sample index, tempo, period,
   confidence, sample rate).
3. **`AdaptiveBeatTracker`**: preallocated onset ring (64), comb-score histogram (561 bins at
   0.25 BPM for 60–200), preference table and scratch. `add(_ onset: OnsetEvent)` → comb histogram
   (scalar accumulation, fixed order) → preference multiply + first-maximum (vDSP `vDSP_vmulD`,
   `vDSP_maxviD`, `vDSP_vclrD`, or portable loops) → hysteresis → anchor search → three
   least-squares fits → estimate and confidence factors. `advance(to:) -> BeatEvent?` updates
   freshness, the silence timeout and reports a crossed beat. `process(_ frame:, onset:)` does both
   for one spectrum frame. `reset()`, counters.
4. **Tests first** (owner rule 7: short, representative): configuration validation; unit
   behaviour on synthetic onset lists (exact periods, octave choice, missing beats, ordering and
   rate checks, beat reporting once, jumps, reset, timeout, random onsets); acceptance through the
   real pipeline on five representative pulse runs, the 120→132 change and the gap; determinism
   (two runs of one case) and backend agreement (one case).
5. **Contract**: `contracts/beat-tracker.md` (new).

CI needs no change: `AnalysisFeatures` is already in every package loop of `ios-ci.yml`.
`project.yml`, `.github/workflows/ios-ci.yml` and `scripts/test_scripts.py` are not touched.
`Packages/VisualGenerators` is not touched.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, strict concurrency), Xcode 27.2

**Primary Dependencies**: Swift stdlib and the platform C math library (`exp2`, `log2` through `Darwin`/`Glibc`/`Musl`, as `SpectrumMath.swift` does; research ANL-005-D6); Accelerate (`vDSP_vclrD`, `vDSP_vmulD`, `vDSP_maxviD`) behind
`canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE`; ANL-004's `OnsetEvent` and ANL-001's
`SpectrumFrame`. AudioCore in tests only (catalog fixtures). No new dependency.

**Storage**: none (nothing persisted).

**Testing**: XCTest. `swift test` on the macOS host, also with `-Xswiftc -DANALYSIS_NO_ACCELERATE`;
`xcodebuild test -scheme AnalysisFeatures` on the iOS 27.2 simulator; Linux in CI.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+, Linux (CI).

**Project Type**: SwiftPM library package within the iOS app repository.

**Performance Goals**: per onset at most 64·63/2 pairs × 4 harmonics × a few bins, a 64² anchor
search and three 64-point fits: well under a millisecond on the host at the onset rates ANL-004
produces (≤ 20/s); `advance` is O(1). Reported, never asserted.

**Constraints**: add/advance allocation-, lock-, log- and I/O-free (Constitution VII); the tracker
is not `Sendable` and is confined to the analysis worker; nothing into projectM (VIII, ADR-0008
decision 5); every test runs on Linux; no wall-clock or scheduling assertions; new tests about
1–2 s each and under 20 s together (owner rule 7).

**Scale/Scope**: about 400 lines of production Swift, 450 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Swift stdlib, platform math and Accelerate's public vDSP functions | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI, no labels | Pass (n/a) |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Inside `AnalysisFeatures`; consumes ANL-004/ANL-001 public types; no existing type changes | Pass |
| VII Real-time safety | All memory allocated in `init`; add/advance read and write preallocated memory only; `advance` returns an optional value | Pass |
| VIII ProjectM fidelity | Beats feed only native generators and the modulation graph (ADR-0008 decision 5; projectM exposes no beat output); package not linked by the app | Pass |
| IX Dependencies | None added; comb histogram and least squares written in-house from published methods | Pass |
| X Evidence | Host, Linux shape and simulator tests; no device claim | Pass |
| Privacy | Nothing stored, recorded or sent | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/021-anl-005-adaptive-beat-tracker/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/beat-tracker.md
```

### Source Code (repository root)

```text
Packages/AnalysisFeatures/
  Sources/AnalysisFeatures/
    BeatTrackerConfiguration.swift  (configuration, errors, BeatEstimate, BeatEvent)
    AdaptiveBeatTracker.swift       (tracker, portable and vDSP histogram steps)
  Tests/AnalysisFeaturesTests/
    BeatTrackerConfigurationTests.swift  BeatTrackerTests.swift
    BeatAcceptanceTests.swift            BeatTestSupport.swift
```

**Structure Decision**: extend `AnalysisFeatures` (the roadmap's analysis package) with two new
source files; nothing existing is edited.

## Test design (deterministic)

- Inputs: AUD-016 catalog loops (bit-identical generator), closed-form onset lists (exact sample
  indices) and a fixed-seed LCG for random onsets (exponential gaps, at least 50 ms apart, like
  ANL-004's minimum interval). No other randomness.
- Ground truth: the catalog's onset frames and tempos. "Converged at t": at every frame from t to
  the end, an estimate exists, |BPM − true| ≤ 1.0 and confidence ≥ 0.8; the convergence time is
  the first such frame end (seconds from the stream start). Beat matching: every catalog onset
  after convergence takes the first unused beat event within ±hop; misses and extra beat events
  (after convergence) are counted.
- Exact checks: estimates and beat events compared field by field, doubles by bit pattern, for
  repeated runs and across backends.
- No wall clock; streams use `clock: { 0 }`; results printed (`ANL-005 …` lines).
- No Accelerate, AVFAudio or SwiftUI in tests; the whole target also runs with
  `-DANALYSIS_NO_ACCELERATE`. Test classes are not `@MainActor`; no `setUp`/`tearDown` state; no
  C stdio globals.
- Red run first: tests written against missing symbols fail to compile (recorded in tasks.md).
- Runtime: five 10 s pulse loops, one 20 s change run, one 16 s gap run, one 10 s noise loop
  through the pipeline; unit tests on onset lists cost microseconds. Each test's time is reported.

## Persistence and rollback

No persistence, no migration, no stored settings: the tracker's state is in memory and rebuilt
from audio. Rollback is reverting the feature's commits: two new source files and four new test
files, no existing type changed, the package not linked by the app.

## Complexity Tracking

None.
