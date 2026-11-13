# Implementation Plan: SHOW-011 Tap Tempo

**Branch**: `feature/show-011` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/027-show-011-tap-tempo/spec.md`

## Summary

A pure tempo model (`TempoSource`) combines a manual override from taps with the ANL-005 estimate
read from the ANL-016 bus, and answers one question for every consumer: what is the tempo, where
did it come from, how sure is it, and when is the next beat. It lives in a new package
`Packages/PerformanceControl` (the roadmap's home for live-performance rows) with two targets:
`PerformanceControl` (no dependencies: taps, estimate, snapshot) and `PerformanceControlAnalysis`
(depends on AnalysisFeatures: turns bus frames and beat events into estimates and owns a pipeline
for the projectM case). The app adds a `TempoCoordinator` (tap, reset, readout, announcements,
estimate polling, PERF-011 suspension) and a tempo group in the controls overlay. Research:
[research.md](research.md); entities: [data-model.md](data-model.md); API:
[contracts/tempo-source.md](contracts/tempo-source.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode, strict concurrency), Xcode 27.2

**Primary Dependencies**: Swift stdlib; AnalysisFeatures (ANL-005 tracker inside the ANL-016
pipeline) for the analysis target only; SwiftUI/UIKit in the app (`UIAccessibility` announcements).
No new third-party dependency.

**Storage**: none. The manual tempo lives in memory only (SHOW-011-R16).

**Testing**: XCTest. `swift test --package-path Packages/PerformanceControl` on the macOS host and
with `-Xswiftc -DANALYSIS_NO_ACCELERATE` (the Linux shape of its AnalysisFeatures dependency);
`xcodebuild test -scheme PerformanceControl` on an iOS 27.2 simulator; app unit tests for
`TempoCoordinator`; one UI test (`TapTempoUITests`). Linux in CI.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+ (host tests), Linux (CI).

**Project Type**: SwiftPM library package plus the iOS app target.

**Performance Goals**: a tap is a few dozen arithmetic operations; the estimate poll runs at 4 Hz
on the main actor and copies one frame and a handful of events. Not measured (negligible).

**Constraints**: the model reads no clock (times are arguments; SHOW-011-R11); no wall-clock or
scheduling assertions in tests; exactly one pipeline reads the analysis tap at a time; nothing
reaches projectM (VIII, ADR-0008 decision 5); unit tests about 1 s or less, UI test under 30 s
(owner rule 7).

**Scale/Scope**: about 350 lines of package Swift, 250 lines of package tests, 200 lines of app
Swift, 150 lines of app tests; 6 added lines in `LiveBandAnalyzer`, 4 in `CircularSpectrumHost`.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Swift stdlib, SwiftUI, `UIAccessibility.post` | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | "Detected" only for an estimate with confidence ≥ 0.5 (ANL-005's "high"); otherwise "—" | Pass |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Pure model without dependencies; the bus adapter in its own target; the app depends on the package, not the other way | Pass |
| VII Real-time safety | Nothing on the audio callback; the pipeline is ANL-016's (preallocated, its own worker); the poll runs on the main actor, never on the worker | Pass |
| VIII ProjectM fidelity | Tempo feeds the readout and future native consumers only; projectM's PCM path untouched (ADR-0008 decision 5) | Pass |
| IX Dependencies | None added | Pass |
| X Evidence | Host, Linux-shape, simulator and UI tests; no device claim; tap timing on a device is `{device}` and not claimed | Pass |
| Privacy | Nothing stored, recorded or sent | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/027-show-011-tap-tempo/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/tempo-source.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/PerformanceControl/                       # new package
├── Package.swift
├── Sources/PerformanceControl/
│   ├── TapTempoRules.swift                        # range, pause, window, confidence floor
│   ├── TempoSnapshot.swift                        # the read API (Codable)
│   └── TempoSource.swift                          # taps, override, estimate, reset
├── Sources/PerformanceControlAnalysis/
│   ├── TempoEstimateTracker.swift                 # bus frames + beat events → TempoEstimate
│   └── TempoAnalyzer.swift                        # subscription reader; own pipeline for projectM
└── Tests/PerformanceControlTests/
    ├── TapTempoTests.swift
    ├── TempoSourceTests.swift
    └── TempoEstimateTrackerTests.swift
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift   # hook: subscribe/unsubscribe
Apps/projectM-iOS/Coordinators/TempoCoordinator.swift                     # new
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                       # owns it; follow/halt hooks
Apps/projectM-iOS/Visuals/CircularSpectrumHost.swift                      # hook: tempo subscription
Apps/projectM-iOS/Views/TempoControls.swift                               # new
Apps/projectM-iOS/Views/ControlsOverlay.swift                             # one line per layout
Apps/projectM-iOS/Tests/TempoCoordinatorTests.swift                       # new
Apps/projectM-iOS/UITests/TapTempoUITests.swift                           # new
project.yml                                                               # package + app dependency
.github/workflows/ios-ci.yml                                              # package in every loop
```

**Structure Decision**: a new package, as the roadmap proposes for live-performance rows, so the
consumers listed in the spec's hand-off (SHOW-003, SHOW-010, UIX-005, MOD-009, MIDI-010) depend on
one small module and not on the app. AnalysisFeatures stays analysis-only; extending it with
user-tap state would mix concerns.

## Persistence and rollback

Nothing is persisted: the manual tempo, the tap sequence and the estimate live in memory and end
with the process (SHOW-011-R16); `TempoSnapshot` is `Codable` for later show files, but nothing
writes it in this row. Rollback is reverting the feature's commits: the package, the coordinator
and the controls disappear; the analyzer hook is additive and unused without them; the app's
analysis tap then has the circular spectrum as its only reader again.

## Complexity Tracking

No constitution violations to justify.
