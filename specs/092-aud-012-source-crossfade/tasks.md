# Tasks: AUD-012 Source Crossfade

**Input**: Design documents from `specs/092-aud-012-source-crossfade/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/source-handoff.md, quickstart.md

Tests are requested by the roadmap row (unit tests plus the simulator). Budgets (owner rule 7): a
unit test about 1-2 s and at most 10 s, a package suite under 1 minute, a UI test under 30 s.

## Phase 1: Setup

- [X] AUD-012-T01 Record the baseline switch measurement (gap, ring cleared, label before audio, step 1.0, NaN pass-through) in spec.md "Baseline" and remove the temporary harness `Packages/CaptureKit/Tests/CaptureKitTests/SwitchBaselineMeasurement.swift` — Verified 2026-11-13: baseline measured with the temporary CaptureKit harness (swift test --filter SwitchBaselineMeasurement), results in spec.md Baseline; harness removed from the tree

## Phase 2: Foundational (renderer boundary, blocks every story)

- [X] AUD-012-T02 [P] Write `Packages/AudioCore/Tests/AudioCoreTests/SourceHandoffTests.swift`: sanitizer replaces NaN/±Inf with 0 and clamps beyond ±2 with an exact count; clean writes are bit-identical; the envelope's fade-out, silence and fade-in ("position 0…4,410", gain = position / 4,410) with the step bound a / 4,410; forced completion "over min(remaining, 1,024) frames" from the last frame, step ≤ |a| / 1,024; `resetForHandoff` keeps projectM's ring, empties the tap, advances the generation, writes 1,024 zero frames; a second fade-out during a fade-in continues from the current position; `reset()` returns to unity — Verified 2026-11-13: SourceHandoffTests, 14 tests pass on the host
- [X] AUD-012-T03 Implement `PCMSanitizer` and `HandoffEnvelope` in `Packages/AudioCore/Sources/AudioCore/SourceHandoff.swift` (index `while` loops, no allocation; contract C1) — Verified 2026-11-13: SourceHandoffTests (sanitizer, envelope, forced ramp)
- [X] AUD-012-T04 Route `NormalizedPCMRing.write` through the boundary (fast path for clean unity writes, 1,024-frame preallocated scratch otherwise), add `sanitizedSampleCount`, `resetForHandoff(silenceFrames:)`, `beginFadeOut()`, `completeFadeOut()`, `beginFadeIn()`, `handoffPhase`, make `reset()` restore unity, and document the handoff silence as the one exception to R-06's underrun policy in the header of `Packages/AudioCore/Sources/AudioCore/NormalizedPCMReader.swift` — Verified 2026-11-13: SourceHandoffTests plus the existing AnalysisTapTests/NormalizedReaderTests (unbounded default ring keeps their index patterns)
- [X] AUD-012-T05 In `Packages/AudioCore/Sources/AudioCore/AudioAnalyzer.swift`: replace non-finite samples in the drain scratch before `LevelMeter` and the Normalizer (counted); add `beginHandoffFadeOut()`, `handoffFadeOutDone`, `completeHandoffFadeOut()`, `beginAttempt(handoff:)` (C1.6) and the immediate publish of the first drain pass with audio in a handoff attempt — Verified 2026-11-13: SourceHandoffTests testTheAnalyzerSanitizesInputBeforeLevelsAndConversion, testAHandoffAttemptFadesTheNewSourceInAfterTheSilence
- [X] AUD-012-T06 Run AudioCore on the host and with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO` (Linux shape); all pass, suite under 1 minute — Verified 2026-11-13: swift test (AudioCore) 182 tests, 0 failures, 25.0 s; -Xswiftc -DAUDIOCORE_NO_AVFAUDIO 177 tests, 0 failures, 21.6 s

## Phase 3: User Story 1 - Switch source without leaving the visualizer (P1)

**Goal**: a mid-session switch with the label rule. **Independent test**: CaptureKit unit tests and one UI test.

- [ ] AUD-012-T07 [P] [US1] Write `Packages/CaptureKit/Tests/CaptureKitTests/SourceSwitchTests.swift`: A → B and B → A with fake sources: the old source stops before the new starts, exactly one runs, label sequence (`switchingTo` nil → B → nil with `activeMode` B) exactly A, switching, B; the label clears on first audio, on a decided state, on a failed start; same mode is a no-op; `select`/`stop`/`restart` unchanged (no `switchingTo`)
- [ ] AUD-012-T08 [US1] Implement `switchSource(to:)`, `switchingTo`, `HandoffTiming` (150 ms / 5 ms, `.immediate`), `sanitizedSampleCount`, `onSessionMode` in `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift` (contract C2, C3)
- [ ] AUD-012-T09 [P] [US1] Add `UIStrings.switchingSource` ("Switching source…") and `UIStrings.switchSource` ("Switch Source") in `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`
- [ ] AUD-012-T10 [US1] App: `AppCoordinator.switchSource(to:)`, `switchTargets`, `showSourceSwitcher`, label routing (`sourceStatusText`), route indicator hidden while switching, AUD-011 flag via `onSessionMode` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; "Switch Source" button and dialog in `Apps/projectM-iOS/Views/ControlsOverlay.swift` and `Apps/projectM-iOS/Views/VisualizerView.swift`; indicator and announcements in `Apps/projectM-iOS/Views/SourceStatusIndicator.swift`; identifiers `switchSource` and `switchSource:<mode raw value>`, label "Switch Source" (AUD-012-R14; contract C5)
- [ ] AUD-012-T11 [US1] Debug fakes: `-uitestFake a,b` and `-uitestFakeLevel loud` in `Apps/projectM-iOS/Debug/UITestFakeSource.swift` (single-mode usage unchanged)
- [ ] AUD-012-T12 [P] [US1] App unit tests `Apps/projectM-iOS/Tests/SourceSwitchAppTests.swift`: switch targets exclude the current and unavailable modes; the indicator text while switching; the route context is nil while switching; Microphone with a pending explainer goes to the chooser
- [ ] AUD-012-T13 [US1] UI test `Apps/projectM-iOS/UITests/SourceSwitchUITests.swift`: two fakes, switch mid-session, the indicator goes to "System/App Capture · Active audio", the visualizer stays and frames keep rendering; under 30 s

## Phase 4: User Story 2 - Clean audio at the renderer boundary (P1)

**Goal**: no non-finite or out-of-bound sample, bounded ramp, generation rule. **Independent test**: CaptureKit harness.

- [ ] AUD-012-T14 [US2] Extend `SourceSwitchTests.swift`: fakes inject NaN/±Inf at 44.1 and 48 kHz across A → B, B → A, A → B → A: 0 non-finite and 0 |x| > 2 in projectM's ring (read in order) and the tap, every injected sample counted, levels true; DC ±0.5 switch: max step ≤ 0.5 / 1,024 + 1e-6 and an exact-zero run of ≥ 1,024 frames between the sources; handoff written frames (fade + silence + fade-in) ≤ 300 ms of sample clock; no positive (A) sample read from the tap after the generation advanced
- [ ] AUD-012-T15 [US2] Show the sanitized count in `Apps/projectM-iOS/Views/PerformanceOverlay.swift` when it is non-zero (a number only)

## Phase 5: User Story 3 - Stop, rapid switching and failures stay truthful (P2)

- [ ] AUD-012-T16 [US3] Extend `SourceSwitchTests.swift`: Stop during the fade-out wait (non-immediate timing, a source that keeps writing) stops the old source, starts nothing, clears `switchingTo`; A → B → C before B finished: B never runs or is stopped, C runs, the gain sequence has no jump; a failed start of B shows B with the failure; the noise gate flag follows `onSessionMode`

## Phase 6: Polish & Cross-Cutting

- [ ] AUD-012-T17 ADR for the switch/handoff architecture in `docs/adr/` (next free number above the highest; never 0015, 0016, 0025, 0026, 0031) and the ADR index `docs/adr/README.md`
- [ ] AUD-012-T18 Run the checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`, `check_permission_catalog.py`, `test_scripts.py`, `check_privacy_manifest.py <Debug .app>`; CaptureKit host suite; app unit tests and StatusUITests, TransportUITests, InterruptionUITests, SourceSwitchUITests on "AUD12 iPhone 17"; PosterBoard reports counted before and after; simulator deleted
- [ ] AUD-012-T19 Spec status, tasks ticked with evidence
- [ ] AUD-012-T20 {device} On D1/D2: switch between Microphone, In-App Playback and System/App Capture (D3: Microphone and In-App Playback) including a route change, an interruption and a trip to the background during a switch; record the indicator sequence and that projectM never freezes on old audio

## Dependencies

T01 → T02-T05 → T06 → US1 (T07-T13) → US2 (T14-T15) → US3 (T16) → T17-T19; T20 last.
US2 and US3 extend the same test file as US1, so they run after it.

## Parallel examples

- T02 (tests) with T09 (strings); T07 with T09; T12 with T11.

## Implementation strategy

MVP = Phase 2 + US1 (the boundary and the switch). US2 adds the evidence harness for the
acceptance; US3 hardens the edge cases. Device work (T20) is last and stays open.

## Analysis (speckit-analyze, 2026-11-13)

Coverage 15/15 requirements and 8/8 success criteria; 0 critical, 0 high. Applied: C1 R14's
identifiers named in T10; C2 the R-06 underrun exception documented by T04; U1 background during a
switch added to the device task T20 (on the host, lifecycle events are serialized behind the switch
like every other command; no new code path).
