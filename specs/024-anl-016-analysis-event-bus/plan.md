# Implementation Plan: ANL-016 Analysis Event Bus

**Branch**: `feature/anl-016` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/024-anl-016-analysis-event-bus/spec.md`

## Summary

Extend existing packages; no new package, no new dependency, no app or CaptureKit change.

1. **AudioCore (prerequisite delta, ANL-016-R9)**: `NormalizedPCMRing` gains a session generation
   (`Atomic<UInt64>`), increased by `reset()` after the tap is drained (not by `discardBuffered()`);
   a new public protocol `AnalysisSessionReporting` (`analysisSessionGeneration`) that the tap
   reader adopts. Existing behavior is unchanged.
2. **AnalysisFeatures, new files**:
   - `AnalysisBusTypes.swift`: `AnalysisTimestamp`, `AnalysisFrame`, `AnalysisEvent` +
     `AnalysisEventKind`, `AnalysisSessionChange`, `AnalysisBusError`.
   - `AnalysisPipelineConfiguration.swift`: spectrum configuration, band count, band floor, onset and
     beat configurations; validation (sample rates agree).
   - `AnalysisSubscription.swift`: per-subscriber latest-frame slot and bounded drop-oldest event
     ring, one `Mutex` each.
   - `AnalysisPipeline.swift`: the worker (serial `DispatchQueue`, optional 10 ms timer), the
     session/clock/ID state, the chunked read loop with generation checks, the publish fan-out.
3. **VisualGenerators / `VisualBandFeed` only (ANL-016-R16)**: `LiveBandAnalyzer` owns a pipeline
   and one subscription; `output` becomes a small `LiveBandOutput` with the same
   `readLatest(into:capacity:)` call shape, so `CircularSpectrumHost` compiles unchanged.
   `SpectrumBandFeed` stays (tested, documented as the reference path). The test helper in
   `BandFeedTests.swift` follows the output type.
4. **Tests first** (owner rule 7): AudioCore generation test; AnalysisFeatures bus tests (ordering
   and IDs, restart/switch/detach, straddling chunk, overflow, unsubscribe, determinism, clock
   mapping, subscriber limit); VIS-001 band-feed tests unchanged in intent.
5. **Contract**: `contracts/analysis-event-bus.md`.

CI needs no change: AudioCore, AnalysisFeatures and VisualGenerators are already in every package
loop of `ios-ci.yml`. `project.yml`, `AppCoordinator.swift`, `.github/workflows/ios-ci.yml` and
`scripts/test_scripts.py` are not touched.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 language mode, strict concurrency), Xcode 27.2

**Primary Dependencies**: Swift stdlib, `Synchronization` (`Atomic`, `Mutex`; macOS 15/iOS 18+,
Linux Swift 6), `Dispatch`; AnalysisFeatures' own stream, reducer, detector, tracker; AudioCore's
ring, tap, `MonotonicClock` and AUD-016 tone generator (tests). No new dependency.

**Storage**: none (nothing persisted; ANL-016-R17).

**Testing**: XCTest. `swift test` on the macOS host for AudioCore, AnalysisFeatures (also with
`-Xswiftc -DANALYSIS_NO_ACCELERATE`) and VisualGenerators (also with `-DVISUAL_NO_METAL
-DANALYSIS_NO_ACCELERATE`); `xcodebuild test -scheme AnalysisFeatures` on the `TestSpeed iPhone 17`
simulator (iOS 27.2); Linux in CI.

**Target Platform**: iOS/iPadOS 26.0+, macOS 15+, Linux (CI).

**Project Type**: SwiftPM library packages within the iOS app repository.

**Performance Goals**: per spectrum frame (hop 512 = 11.6 ms of audio) one extra band reduction
plus a fan-out to ≤ 16 subscriptions (a 128-float copy each); negligible next to the FFT.
Reported, never asserted.

**Constraints**: no allocation, logging or I/O per step after creation (VII); locks held only for
constant-size copies; the worker never calls subscriber code; nothing into projectM (VIII,
ADR-0008 decision 5); every test runs on Linux; no wall-clock or scheduling assertions; tests
driven synchronously; new tests about 1–2 s each (owner rule 7).

**Scale/Scope**: about 600 lines of production Swift, 400 lines of tests, 40 lines in AudioCore,
80 lines changed in VisualBandFeed.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Swift stdlib, Synchronization, Dispatch | Pass |
| II Capture feasibility | No capture change; the ring's existing reset is the restart signal | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | No UI, no labels | Pass (n/a) |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Bus in AnalysisFeatures (depends on AudioCore only, not CaptureKit); the visual depends on the bus, not the other way | Pass |
| VII Real-time safety | Nothing runs on the audio callback; the producer side of the ring gains one atomic increment in `reset()` (not on the write path); the worker preallocates everything; bounded queues with tested overflow policy (drop-oldest events, latest-wins frames); start/stop idempotent and synchronous | Pass |
| VIII ProjectM fidelity | Bus items feed only native visuals and the future modulation graph (ADR-0008 decision 5); projectM's PCM path untouched | Pass |
| IX Dependencies | None added | Pass |
| X Evidence | Host, Linux-shape and simulator tests; no device claim | Pass |
| Privacy | Nothing stored, recorded or sent | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/024-anl-016-analysis-event-bus/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/analysis-event-bus.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift          # session generation (edit)
Packages/AudioCore/Tests/AudioCoreTests/NormalizedPCMRingTests.swift   # or a new small test file
Packages/AnalysisFeatures/Sources/AnalysisFeatures/
├── AnalysisBusTypes.swift                 # new
├── AnalysisPipelineConfiguration.swift    # new
├── AnalysisSubscription.swift             # new
└── AnalysisPipeline.swift                 # new
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/
├── AnalysisBusTestSupport.swift           # new
├── AnalysisSubscriptionTests.swift        # new
└── AnalysisPipelineTests.swift            # new
Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift      # on the bus (edit)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/BandFeedTests.swift    # helper type (edit)
```

**Structure Decision**: extend AnalysisFeatures (the roadmap's home for "timestamped feature
frames"); keep it free of CaptureKit by reading the restart signal from AudioCore's tap.

## Persistence and rollback

Nothing is persisted: sessions, IDs and queues live in memory and restart with the process.
Rollback is reverting the feature's commits; the circular spectrum then returns to its own timer
and stream, and the ring's generation counter disappears (no consumer outside this feature).

## Complexity Tracking

No constitution violations to justify.
