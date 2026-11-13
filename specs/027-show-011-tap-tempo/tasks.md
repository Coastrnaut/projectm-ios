# Tasks: SHOW-011 Tap Tempo

**Input**: `specs/027-show-011-tap-tempo/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: test-first. Every test injects times (no wall clock, no sleeps); each runs in about a
second or less on the host, the package suite in under a minute, the UI test in under 30 s
(owner rule 7). Logs go to `.build/scratch/`. Device-only checks are tagged `{device}` and are not
run by this row.

Format: `- [ ] SHOW-011-Tnn [P?] [Story?] description`. A task is ticked only when verified, with
" — Verified 2026-11-13: <how>".

## Phase 1: Setup

- [X] SHOW-011-T01 Record the baseline before any change: `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`; note results here. — Verified 2026-11-13: before any change: check_compliance OK, validate_docs OK (266 files), test_scripts 99 tests OK (1 skipped) in 8.0 s; log .build/scratch/show011-scripts-baseline.log.
- [X] SHOW-011-T02 Create `Packages/PerformanceControl/Package.swift`: tools 6.0, platforms iOS 26 / macOS 15, one library product `PerformanceControl` with targets `PerformanceControl` (no dependencies) and `PerformanceControlAnalysis` (depends on `PerformanceControl`, `AnalysisFeatures`, `AudioCore`), test target `PerformanceControlTests`; empty source stubs so the package resolves. — Verified 2026-11-13: `swift build` resolves the package with both targets and the test target (commit a5ab4d7).

## Phase 2: Foundational (tests first)

- [X] SHOW-011-T03 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TapTempoTests.swift` (US1, US3): four taps 500 ms apart → `.established(bpm: 120)`, origin manual, confidence 1, anchor = last tap; taps 1-3 → `.counting(taps: n, of: 4)` and origin unchanged; alternating ±20 ms errors → within ±4 BPM at tap 4 and ±1 BPM at tap 8; further taps → `.refined`; an interval "shorter than 300 ms" (including a second tap at the same instant) → `.tooFast`, tap ignored, count unchanged; an interval "longer than 1 s and at most 2 s" → `.tooSlow`, count 1; an interval "longer than 2 s" → `.counting(taps: 1, of: 4)`; a manual tempo survives a restart until the new sequence's fourth tap replaces it; never a manual BPM outside 60-200. — Verified 2026-11-13: 8 tests in TapTempoTests pass on the host, the -DANALYSIS_NO_ACCELERATE build and the iOS 27.2 simulator, 0.000 s each; red first (T06). The alternating ±20 ms case gives 121.95 BPM at tap 4 and 120.46 BPM at tap 8.
- [X] SHOW-011-T04 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoSourceTests.swift` (US2, US5): no input → `TempoSnapshot.none`; a confident estimate (≥ 0.5) → estimated with its BPM, confidence, period and anchor; confidence below 0.5 → none; reset with a confident estimate → estimated; reset without → none; reset clears the sequence (next tap counts 1); an estimate never overrides manual; `nextBeat(atOrAfter:)` of a manual 120 BPM tempo is last tap + k·500 ms (before, at and after the anchor); `beatPhase(at:)` 0.5 halfway; snapshot JSON round trip unchanged. — Verified 2026-11-13: 9 tests in TempoSourceTests pass (host, portable, simulator), 0.000 s each; red first (T06).
- [X] SHOW-011-T05 [P] Write `Packages/PerformanceControl/Tests/PerformanceControlTests/TempoEstimateTrackerTests.swift` (US2, US5): frames with `bpm` and confidence give an estimate without a beat time; a beat event sets the beat host time to event host time − (session sample − beat sample)/rate; a frame with `bpm == nil` clears the estimate; `sessionStarted`/`sessionEnded` clear it; `clear()` clears it. Events and frames are built by hand (no pipeline audio). — Verified 2026-11-13: 6 tests in TempoEstimateTrackerTests (0.000-0.020 s) plus 2 end-to-end tests in TempoBusEndToEndTests (a real ANL-016 pipeline fed AUD-016 pulse-120, stepped synchronously: 0.31-0.86 s each) pass. The ID-order case was shown red by disabling the fix (log .build/scratch/show011-order-red.log: the stale frame brought back 120.19 BPM).
- [X] SHOW-011-T06 Record the red run (T03-T05 fail to compile against the missing symbols) in `.build/scratch/show011-red.log`. — Verified 2026-11-13: `swift build --build-tests` failed with `cannot find type 'TempoSource' in scope` before any production code; .build/scratch/show011-red.log.
- [X] SHOW-011-T07 Implement `Packages/PerformanceControl/Sources/PerformanceControl/TapTempoRules.swift` and `TempoSnapshot.swift` (contracts/tempo-source.md; rules "4 taps, 60-200 BPM, 2 s pause, 8 taps, 0.5"). — Verified 2026-11-13: TapTempoRules.swift and TempoSnapshot.swift; T03/T04 pass.
- [X] SHOW-011-T08 Implement `Packages/PerformanceControl/Sources/PerformanceControl/TempoSource.swift`: least-squares period over the last "at most 8" taps (research SHOW-011-D1), limits and sequences (D2), reset, estimate (confidence floor 0.5); T03 and T04 pass. — Verified 2026-11-13: TempoSource.swift; T03/T04 pass.
- [X] SHOW-011-T09 Implement `Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoEstimateTracker.swift` and `TempoAnalyzer.swift` (`TempoSubscriptionReader`, `TempoAnalyzer` with its own ANL-016 pipeline; D3, D4); T05 passes. — Verified 2026-11-13: TempoEstimateTracker.swift, TempoAnalyzer.swift; T05 passes.
- [X] SHOW-011-T10 Run the package on the host, with `-Xswiftc -DANALYSIS_NO_ACCELERATE`, and on the iOS 27.2 simulator; record counts and per-test durations. — Verified 2026-11-13: host `swift test`: 25 tests, 0 failures, 0.61 s; `-Xswiftc -DANALYSIS_NO_ACCELERATE`: 25 tests, 0 failures, 1.67 s; `xcodebuild test -scheme PerformanceControl` on the private iOS 27.2 simulator `SHOW iPhone 17` (8B094D93): 25 tests, TEST SUCCEEDED, 1.6 s (21 s wall). No warnings.

## Phase 3: User Story 1 + 2 in the app (P1)

- [X] SHOW-011-T11 [P] [US1] Add the hook to `Packages/VisualGenerators/Sources/VisualBandFeed/LiveBandAnalyzer.swift`: `subscribe(eventCapacity:)`, `unsubscribe(_:)`, `sampleRate` (additive; existing tests unchanged). — Verified 2026-11-13: LiveBandAnalyzerSubscriptionTests (1 test, 0.021 s) plus BandFeedTests (3 tests) pass on the host.
- [X] SHOW-011-T12 [US1] Write `Apps/projectM-iOS/Tests/TempoCoordinatorTests.swift`: with an injected clock and announcer, four taps → snapshot manual 120, announcement "Tempo set to 120 BPM"; tap value "Tap 2 of 4"; reset → "Manual tempo cleared. No tempo" and origin none; reset with an injected estimate → "Manual tempo cleared. Detected tempo 126 BPM"; too fast → "Tap slower"… (texts per contracts/tempo-source.md); readout texts; `-uitestTapInterval` synthetic clock steps. — Verified 2026-11-13: 6 tests in TempoCoordinatorTests pass on the private iOS 27.2 simulator (0.000-0.020 s each). Written after TempoCoordinator.swift, so no separate red run was recorded for the app layer.
- [X] SHOW-011-T13 [US1] Implement `Apps/projectM-iOS/Coordinators/TempoCoordinator.swift`: `TempoSource` owner, announcements, readout texts, estimate polling at 250 ms while a feed runs (D5), `PresentationBoundResource`, own `TempoAnalyzer` for projectM, external subscription for the circular spectrum. — Verified 2026-11-13: TempoCoordinator.swift; T12 passes.
- [X] SHOW-011-T14 [US1] Wire it in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (`tempo` property, registration with `presentation`, follow in `resumeActiveVisual`, halt in `pauseActiveVisual`) and `Apps/projectM-iOS/Visuals/CircularSpectrumHost.swift` (tempo subscription hook); add the package to `project.yml`. — Verified 2026-11-13: `xcodegen generate` and `build-for-testing` succeed with no warnings in the changed files; TapTempoUITests and NativeVisualUITests run the wiring.
- [X] SHOW-011-T15 [US1] [US2] Add `Apps/projectM-iOS/Views/TempoControls.swift` (readout, Tap, Reset tempo while manual; identifiers `tempoReadout`, `tapTempo`, `resetTempo`) and place it in both layouts of `Apps/projectM-iOS/Views/ControlsOverlay.swift`; every action restarts the auto-hide. — Verified 2026-11-13: TapTempoUITests reads the identifiers, labels and values in the compact layout (iPhone 17 portrait); the regular layout compiles but no UI test exercises it.
- [X] SHOW-011-T16 [US1] [US2] Write `Apps/projectM-iOS/UITests/TapTempoUITests.swift`: launch with `-uitestTapInterval 500` and a started source, tap `tapTempo` four times, read "120 BPM, manual", tap `resetTempo`, read a value without "manual" and no `resetTempo`; uses `appears(within:)`/`disappears(within:)`/`poll` only. — Verified 2026-11-13: TapTempoUITests.testFourTapsSetTheTempoAndResetClearsIt passed in 9.7 s on the private iOS 27.2 simulator.

## Phase 4: User Story 3 and 4 (P2)

- [X] SHOW-011-T17 [US3] Covered by T03's rejection and pause cases; confirm feedback reaches the UI through T12's "Tap slower"/"Tap faster" announcements. — Verified 2026-11-13: T03's tooFast/tooSlow/pause cases and T12's "Tap slower"/"Tap faster" announcements pass.
- [X] SHOW-011-T18 [US4] Accessibility: labels, values, hint, Dynamic Type (readout uses text styles and `minimumScaleFactor`), announcements; covered by T12 and T16. — Verified 2026-11-13: labels, values, hint and announcements checked by T12 and T16; the readout uses text styles with minimumScaleFactor 0.7. Not checked with VoiceOver or accessibility text sizes on a device.

## Phase 5: User Story 5 (P3)

- [X] SHOW-011-T19 [US5] Covered by T04's `nextBeat`/`beatPhase`/Codable cases; the spec's hand-off section names the consumers. — Verified 2026-11-13: T04's nextBeat/beatPhase/JSON cases pass; the spec's hand-off section names the consumers.

## Phase 6: Polish

- [X] SHOW-011-T20 Add `PerformanceControl` to every package loop in `.github/workflows/ios-ci.yml` (Linux, macOS host, iOS compile, both simulator jobs). — Verified 2026-11-13: PerformanceControl is in all 5 package loops of ios-ci.yml (Linux, macOS host, iOS compile, both simulator jobs); not yet run in CI (no push from this worktree).
- [X] SHOW-011-T21 Build the app (`xcodegen generate`, simulator build) and run `TempoCoordinatorTests`, `TapTempoUITests` and `NativeVisualUITests` (the band feed was touched) on a simulator not in use by others; count new PosterBoard reports. — Verified 2026-11-13: on the private simulator `SHOW iPhone 17` (iOS 27.2, 8B094D93; the shared 4E32B01D was in use by the integration run): `xcodegen generate`, `build-for-testing` (TEST BUILD SUCCEEDED); all app unit tests: 119 executed, 1 failure, the known environmental `PresetTests.testBundledIncludedScopeMatchesRelease1_0` (the worktree has no preset submodules: 28 presets indexed); TempoCoordinatorTests 6/6; TapTempoUITests 1/1 (9.7 s); NativeVisualUITests 4/4 (9.2-18.2 s). Zero new PosterBoard reports; the simulator was shut down afterwards. Logs .build/scratch/show011-app-*.log.
- [X] SHOW-011-T22 Run `python3 scripts/check_compliance.py`, `python3 scripts/validate_docs.py`, `python3 scripts/test_scripts.py`, `swift test` for VisualGenerators (hook); confirm with `grep` that no tempo type is referenced from `Packages/ProjectMBridge`, `Packages/Rendering` or `Packages/ANGLERendering` (SHOW-011-R15); record results. — Verified 2026-11-13: check_compliance OK; validate_docs OK (266 files); test_scripts 99 tests OK (1 skipped) in 6.8 s; VisualGenerators `swift test` 82 tests, 0 failures, 13.9 s; grep finds no PerformanceControl/Tempo reference in Packages/ProjectMBridge, Rendering or ANGLERendering.
- [ ] SHOW-011-T23 `{device}` On D1, tap along with music, reset with music playing; not required for this row and not run (open, `{device}`).

## Dependencies

T01 → T02 → T03-T05 (parallel) → T06 → T07 → T08 → T09 → T10 → T11-T16 → T20-T22. T23 is
`{device}` and not part of this run.

## Parallel examples

T03, T04 and T05 are separate files; T11 is independent of T12-T13.

## Implementation strategy

MVP: T02-T08 (the model) plus T13-T15 (the app control). Then the estimate (T09, T14), the UI test,
CI.
