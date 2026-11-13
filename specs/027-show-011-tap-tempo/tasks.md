# Tasks: SHOW-011 Tap Tempo

**Input**: `specs/027-show-011-tap-tempo/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first. Every test injects times (no wall clock, no sleeps); each runs in about a
second or less on the host, the package suite in under a minute, the UI test in under 30 s
(owner rule 7). Logs go to `.build/scratch/`. Device-only checks are tagged `{device}` and are not
run by this row.

Format: `- [ ] SHOW-011-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [ ] SHOW-011-T01 Record the baseline before any change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`; note results here.
- [ ] SHOW-011-T02 Create `Packages/PerformanceControl/Package.swift`: tools 6.0, platforms iOS 26 / macOS 15, one library product `PerformanceControl` with targets `PerformanceControl` (no dependencies) and `PerformanceControlAnalysis` (depends on `PerformanceControl`, `AnalysisFeatures`, `AudioCore`), test target `PerformanceControlTests`; empty source stubs so the package resolves.

## Phase 2: Foundational (tests first)

- [ ] SHOW-011-T03 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TapTempoTests.swift` (US1, US3): four taps 500 ms apart → `.established(bpm: 120)`, origin manual, confidence 1, anchor = last tap; taps 1-3 → `.counting(taps: n, of: 4)` and origin unchanged; alternating ±20 ms errors → within ±4 BPM at tap 4 and ±1 BPM at tap 8; further taps → `.refined`; an interval "shorter than 300 ms" → `.tooFast`, tap ignored, count unchanged; an interval "longer than 1 s and at most 2 s" → `.tooSlow`, count 1; an interval "longer than 2 s" → `.counting(taps: 1, of: 4)`; a manual tempo survives a restart until the new sequence's fourth tap replaces it; never a manual BPM outside 60-200.
- [ ] SHOW-011-T04 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoSourceTests.swift` (US2, US5): no input → `TempoSnapshot.none`; a confident estimate (≥ 0.5) → estimated with its BPM, confidence, period and anchor; confidence below 0.5 → none; reset with a confident estimate → estimated; reset without → none; reset clears the sequence (next tap counts 1); an estimate never overrides manual; `nextBeat(atOrAfter:)` of a manual 120 BPM tempo is last tap + k·500 ms (before, at and after the anchor); `beatPhase(at:)` 0.5 halfway; snapshot JSON round trip unchanged.
- [ ] SHOW-011-T05 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoEstimateTrackerTests.swift` (US2, US5): frames with `bpm` and confidence give an estimate without a beat time; a beat event sets the beat host time to event host time − (session sample − beat sample)/rate; a frame with `bpm == nil` clears the estimate; `sessionStarted`/`sessionEnded` clear it; `clear()` clears it. Events and frames are built by hand (no pipeline audio).
- [ ] SHOW-011-T06 Record the red run (T03-T05 fail to compile against the missing symbols) in `.build/scratch/show011-red.log`.
- [ ] SHOW-011-T07 Implement `Packages/PerformanceControl/Sources/PerformanceControl/TapTempoRules.swift` and `TempoSnapshot.swift` (contracts/tempo-source.md; rules "4 taps, 60-200 BPM, 2 s pause, 8 taps, 0.5").
- [ ] SHOW-011-T08 Implement `Packages/PerformanceControl/Sources/PerformanceControl/TempoSource.swift`: least-squares period over the last "at most 8" taps (research SHOW-011-D1), limits and sequences (D2), reset, estimate (confidence floor 0.5); T03 and T04 pass.
- [ ] SHOW-011-T09 Implement `Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift` and `TempoAnalyzer.swift` (`TempoSubscriptionReader`, `TempoAnalyzer` with its own ANL-016 pipeline; D3, D4); T05 passes.
- [ ] SHOW-011-T10 Run the package on the host, with `-Xswiftc -DANALYSIS_NO_ACCELERATE`, and on the iOS 27.2 simulator; record counts and per-test durations.

## Phase 3: User Story 1 + 2 in the app (P1)

- [ ] SHOW-011-T11 [P] [US1] Add the hook to `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`: `subscribe(eventCapacity:)`, `unsubscribe(_:)`, `sampleRate` (additive; existing tests unchanged).
- [ ] SHOW-011-T12 [US1] Write `Apps/projectM-iOS/Tests/TempoCoordinatorTests.swift`: with an injected clock and announcer, four taps → snapshot manual 120, announcement "Tempo set to 120 BPM"; tap value "Tap 2 of 4"; reset → "Manual tempo cleared. No tempo" and origin none; reset with an injected estimate → "Manual tempo cleared. Detected tempo 126 BPM"; too fast → "Tap slower"… (texts per contracts/tempo-source.md); readout texts; `-uitestTapInterval` synthetic clock steps.
- [ ] SHOW-011-T13 [US1] Implement `Apps/projectM-iOS/Coordinators/TempoCoordinator.swift`: `TempoSource` owner, announcements, readout texts, estimate polling at 250 ms while a feed runs (D5), `PresentationBoundResource`, own `TempoAnalyzer` for projectM, external subscription for the circular spectrum.
- [ ] SHOW-011-T14 [US1] Wire it in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (`tempo` property, registration with `presentation`, follow in `resumeActiveVisual`, halt in `pauseActiveVisual`) and `Apps/projectM-iOS/Visuals/CircularSpectrumHost.swift` (tempo subscription hook); add the package to `project.yml`.
- [ ] SHOW-011-T15 [US1] [US2] Add `Apps/projectM-iOS/Views/TempoControls.swift` (readout, Tap, Reset tempo while manual; identifiers `tempoReadout`, `tapTempo`, `resetTempo`) and place it in both layouts of `Apps/projectM-iOS/Views/ControlsOverlay.swift`; every action restarts the auto-hide.
- [ ] SHOW-011-T16 [US1] [US2] Write `Apps/projectM-iOS/UITests/TapTempoUITests.swift`: launch with `-uitestTapInterval 500` and a started source, tap `tapTempo` four times, read "120 BPM, manual", tap `resetTempo`, read a value without "manual" and no `resetTempo`; uses `appears(within:)`/`disappears(within:)`/`poll` only.

## Phase 4: User Story 3 and 4 (P2)

- [ ] SHOW-011-T17 [US3] Covered by T03's rejection and pause cases; confirm feedback reaches the UI through T12's "Tap slower"/"Tap faster" announcements.
- [ ] SHOW-011-T18 [US4] Accessibility: labels, values, hint, Dynamic Type (readout uses text styles and `minimumScaleFactor`), announcements; covered by T12 and T16.

## Phase 5: User Story 5 (P3)

- [ ] SHOW-011-T19 [US5] Covered by T04's `nextBeat`/`beatPhase`/Codable cases; the spec's hand-off section names the consumers.

## Phase 6: Polish

- [ ] SHOW-011-T20 Add `PerformanceControl` to every package loop in `.github/workflows/ios-ci.yml` (Linux, macOS host, iOS compile, both simulator jobs).
- [ ] SHOW-011-T21 Build the app (`xcodegen generate`, simulator build) and run `TempoCoordinatorTests`, `TapTempoUITests` and `NativeVisualUITests` (the band feed was touched) on a simulator not in use by others; count new PosterBoard reports.
- [ ] SHOW-011-T22 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`, `swift test` for VisualGenerators (hook); record results.
- [ ] SHOW-011-T23 `{device}` On D1, tap along with music, reset with music playing; not required for this row and not run.

## Dependencies

T01 → T02 → T03-T05 (parallel) → T06 → T07 → T08 → T09 → T10 → T11-T16 → T20-T22. T23 is
`{device}` and not part of this run.

## Parallel examples

T03, T04 and T05 are separate files; T11 is independent of T12-T13.

## Implementation strategy

MVP: T02-T08 (the model) plus T13-T15 (the app control). Then the estimate (T09, T14), the UI test,
CI.
