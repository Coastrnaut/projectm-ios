# Tasks: AUD-015 Background Playback Policy

**Input**: `specs/097-aud-015-background-playback-policy/` (spec, plan, research, data-model,
contracts/background-policy.md, quickstart)

**Tests**: requested by the roadmap acceptance ("Tests show playback stops or continues only when
entitled and intended; no covert capture"). Budgets (owner rule 7): unit test about 1-2 s, at most
10 s; UI test under 30 s.

Format: `- [ ] AUD-015-Tnn [P?] [Story?] Description`. `{device}` = needs a physical device and a
person.

## Phase 1: Setup

- [X] AUD-015-T01 Record the baseline: `swift test --package-path Packages/CaptureKit` on the host;
  `python3 scripts/check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `test_scripts.py`; PosterBoard report count. Evidence: counts
  recorded here. — Verified 2026-11-14: at c791527f, CaptureKit 454 tests on the host, 0 failures
  (39.8 s); the four checks OK; `test_scripts.py` 147 tests OK (1 skipped, 16.6 s); PosterBoard
  reports 25.

## Phase 2: Foundational (the policy)

- [X] AUD-015-T02 Write `Packages/CaptureKit/Tests/CaptureKitTests/BackgroundPolicyTests.swift`
  table test: all 48 cases of source (3) × presence (foreground, background, locked, background and
  locked) × keepPlayingInBackground (2) × declaresAudioBackgroundMode (2) against the contract's
  policy table (action, reason, notice text); `mayResumeAutomatically` true only in the foreground
  and unlocked for Microphone and In-App Playback; `declaresAudioMode(in:)` for `[]`,
  `["screen-capture"]`, `["screen-capture","audio"]` (S1). Record the red run. — Verified 2026-11-14: red run
  `cannot find type 'BackgroundPolicy' in scope` (.build/scratch/aud015-red-T02.log); 5 tests in
  `BackgroundPolicyTableTests`, the table test counts 48 cases.
- [X] AUD-015-T03 Implement `Packages/CaptureKit/Sources/CaptureKit/BackgroundPolicy.swift`
  (Context, Action, Reason with `notice`, Decision, Configuration, `decide`,
  `mayResumeAutomatically`, `declaresAudioMode(in:)`), pure Swift, no platform imports (R1, R2,
  R4, R5). Evidence: T02 passes. — Verified 2026-11-14: `swift test --filter
  BackgroundPolicyTableTests` 5 tests, 0 failures (0.001 s).

## Phase 3: User Story 1 - The microphone never listens in the background (P1)

**Independent test**: a fake microphone backend that delivers frames only while its engine runs.

- [ ] AUD-015-T04 [US1] Add manager tests to `BackgroundPolicyTests.swift` using a
  `FrameCountingMicrophoneBackend` (`deliver(frames:)` writes into the sink only while its engine
  runs) behind the real `MicrophoneSource`: (a) background → zero frames reach the sink and the
  engine is off; lock; unlock while backgrounded → still zero, engine off, no resume; foreground →
  engine on, frames flow (S2); (b) a start that completes while away is held Paused with the
  engine off (R6); (c) `resume()` while away does not start the engine; (d) the notice is
  `microphoneStoppedInBackground` after background and cleared by Stop and a new start. Record the
  red run.
- [ ] AUD-015-T05 [US1] In `Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift`: replace
  `isPresentable` with `isBackgrounded` and `isLocked` (foreground clears both), use the policy in
  `handle(_:)`, hold a start that completes while away, refuse a Microphone/In-App resume while
  away, publish `backgroundNotice` and `dismissBackgroundNotice()`, add `backgroundConfiguration`
  (R5, R6, R7, R10). Evidence: T04 and the full CaptureKit suite pass.
- [ ] AUD-015-T06 [US1] Update `Apps/projectM-iOS/Tests/LifecycleCoordinatorTests.swift`
  `testUnlockWhileStillInTheBackgroundResumesNothing`: the microphone is no longer resumed by an
  unlock in the background (0 resumes), and is resumed once on foreground. Evidence: app unit test
  passes.

## Phase 4: User Story 2 - In-App Playback pauses and comes back (P1)

- [ ] AUD-015-T07 [P] [US2] Add tests to `BackgroundPolicyTests.swift` with `FakePlaybackBackend`
  behind the real `InAppPlaybackSource`: shipped configuration pauses on background and resumes on
  foreground with notice `playbackPausedInBackground`; configuration (audio mode, keep) continues,
  no pause, no notice; a user pause stays paused on return and sets no notice; an open
  interruption stays on hold on return; the notice is cleared by a user pause and by `resume()`
  (S3, R7, R10).
- [ ] AUD-015-T08 [US2] Wire the app: `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` sets
  `manager.backgroundConfiguration` from `Bundle.main` `UIBackgroundModes` and keep = false
  (R3); exposes `visibleBackgroundNotice` (nil while away or while a stop/pause reason shows).
  `Apps/projectM-iOS/Views/VisualizerView.swift` shows the notice (identifiers `backgroundNotice`,
  `backgroundNoticeText`, `backgroundNoticeDismiss`), clears it after 8 s, announces it once
  (R7). Unit tests in `Apps/projectM-iOS/Tests/BackgroundPolicyAppTests.swift`: the shipped
  Info.plist declares no `audio` mode and the configuration is (false, false); the notice is
  hidden while away and while a reason shows.

## Phase 5: User Story 3 - System/App Capture follows the system (P2)

- [ ] AUD-015-T09 [P] [US3] Tests in `BackgroundPolicyTests.swift`: with a fake System/App
  Capture source, background, lock, unlock and foreground never suspend, resume or restart it and
  set no notice; an end by the system while away shows "Ended by system" (`endedBySystem`) on
  return and nothing restarts (R4).

## Phase 6: User Story 4 - Rendering stops while away (P2)

- [ ] AUD-015-T10 [P] [US4] Test in `Apps/projectM-iOS/Tests/BackgroundPolicyAppTests.swift`
  through `LifecycleCoordinator`: in every mode, background and lock suspend the visualization and
  every registered presentation resource; an unlock in the background resumes neither the
  resources nor the microphone (R8).

## Phase 7: UI test and polish

- [ ] AUD-015-T11 Write `Apps/projectM-iOS/UITests/BackgroundPolicyUITests.swift`: import a tone,
  play it as In-App Playback, `XCUIDevice.shared.press(.home)`, `app.activate()`; the indicator
  returns to "In-App Playback · Active audio" and `backgroundNoticeText` reads "Playback paused
  while projectM-iOS was in the background." (S4). Under 30 s.
- [ ] AUD-015-T12 Documentation: `docs/privacy-policy.md` section "When the app is in the
  background"; `docs/adr/<next free number>-background-playback-policy.md` (0036 if still free at
  commit time; never 0015, 0016, 0025, 0026, 0031); data-model lifecycle matrix note in
  `specs/001-ios-projectm-visualizer/data-model.md`; keep `check_permission_catalog.py` passing
  (R9).
- [ ] AUD-015-T13 {device} On D1, per source (Microphone, In-App Playback, System/App Capture): Home
  and return, lock and unlock into the app, lock then unlock onto the Home Screen then open the
  app; record the export; check against the contract (S6).
- [ ] AUD-015-T14 Final checks: CaptureKit suite, the app unit tests and the UI tests named in the
  brief (`projectM-iOSTests`, StatusUITests, InterruptionUITests, SessionRecoveryUITests,
  SourceSwitchUITests, BackgroundPolicyUITests), the five scripts, `check_privacy_manifest.py` on
  the Debug app; PosterBoard count after.

## Dependencies

T01 → T02 → T03 → T04 → T05 → (T06, T07, T09) → T08 → (T10, T11) → T12 → T14. T13 last, on a device.

## Parallel examples

T07, T09 and T10 touch different test cases and can be written together after T05.

## Implementation strategy

MVP = Phases 2-3 (the policy and the microphone guarantee: "no covert capture"). Then In-App
Playback's notice, System/App Capture tests, rendering tests, the UI test and docs.
