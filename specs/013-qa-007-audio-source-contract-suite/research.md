# Research: QA-007 Audio source contract suite

## Audit of the existing source tests (2026-11-12, commit `d4d2a5f`)

Files are in `Packages/CaptureKit/Tests/CaptureKitTests/`. "Fake source" means the generic
`FakeAudioSource` (`FakeAudioSource.swift`), which stands in for a whole source and bypasses every
real adapter. "Adapter" means the real `ScreenCaptureSource`, `MicrophoneSource` or
`InAppPlaybackSource` over a fake platform seam (`FakeStreamDriver`, `FakeMicrophoneBackend`,
`FakePlaybackBackend` in `SourceAdapterTests.swift`). "AV" means the real `AVInAppPlaybackBackend`
in offline rendering.

| Invariant | System/App Capture | Microphone | In-App: reference | In-App: file | In-App: test signal | New in QA-007 |
|---|---|---|---|---|---|---|
| R1 start → Waiting, one session, own label | adapter+manager: `testSystemStopBecomesEndedBySystemInManager` (Waiting only); fake: `testSelectStartsAndShowsWaiting` | adapter: `testExplainerRequiredBeforePermissionPrompt`; adapter+manager: `testBackgroundForegroundViaManagerResumesWithinTwoSeconds` | adapter: `testTrackDefaultsToReference` | adapter: `testSelectedFileTrackReachesBackendAndKeepsTheMode`, `testManagerLabelsImportedTrackAsInAppPlaybackAndRestartsIt` | AV: `ToneTrackTests` (no manager, no adapter) | all 5 through adapter+manager |
| R2 start on a started source | none | none | none | none | none | all 5 |
| R3 stop idempotent, Stopped, backend stopped | adapter: `testStopIsIdempotent`; fake: `testStopIsIdempotentAndFast` | none | adapter: `testStopWithinOneSecondAndIdempotent` | none | none | all 5, adapter and manager |
| R3 stop during a pending start | adapter: `testStopEndsAStartWaitingOnThePicker`, `testManagerStopCancelsAStartWaitingOnThePicker`; fake: `testStopCancelsAStartThatNeverAnswers` and 5 more | none (permission prompt) | n/a (start does not wait) | n/a | n/a | Microphone permission prompt |
| R4 no event after stop | none | none | AV: `testAStoppedBackendReactsToNothingAndANewSessionReactsOnce` | none | none | all 5 at adapter and manager |
| R5 denied/blocked start | adapter+manager: `testDeclinedRecordingShowsNotAllowed`, `testNotAllowedIsUnavailableWithItsOwnReason`, `testPickerCancelIsCancelled` | adapter: `testDeniedPermission`, `testDeniedAtPrompt`, `testNoInputIsMicrophoneUnavailable`; fake: `testStartFailureShowsReason` | adapter: `testMissingTrackFails` | adapter: `testUnplayableFileTrackFailsWithoutFallback` | none | all 5 through the manager, plus recovery |
| R5 recovery after denial | none | none | none | none | none | all 5 |
| R6 no samples / silent / active | fake: `testActiveOnlyAfterVerifiedAudio`, `testContentIdentityOnlyAfterVerifiedActiveAudio` | none | AV: `TransportPipelineTests.testPlayedAudioReachesTheRendererInOrderAndBecomesActive` | AV (same suite) | AV: `ToneTrackTests` | all 5 through adapter+manager |
| R7 clean slate | fake: `testDeniedStartAfterVerifiedSessionClearsPreviousSession` and 2 more | fake | fake | none | none | all 5 |
| R8 transition graph | none at source level (AudioCore: `AudioStateClassifierTests`, 20 tests, classifier alone) | none | none | none | none | all 5 |
| R9 interruption | fake: `testInterruptionIgnoredForSystemCaptureButNotForMicrophone` | fake: same, `testInterruptionWithoutResumeNeedsOneTapRestart`, `InterruptionRecoveryTests.testMicrophoneKeepsItsFeature001Behavior` | adapter+manager: `InterruptionRecoveryTests` (26 tests); AV: `InterruptionPipelineTests` | adapter (same; uses file tracks) | AV: `testInterruptionResumesAtTheHeldFrameWithTheFixturesContent` | all 5 through adapter+manager, checked against `InterruptionPolicy.decide` |
| R10 lifecycle | fake: `testBackgroundDoesNotTouchSystemCapture` | adapter+manager: `testBackgroundForegroundViaManagerResumesWithinTwoSeconds`; fake: `testPermissionRevokedWhileBackgrounded` | fake: `testLockIsHandledLikeBackground`; adapter: AUD-014 suite | adapter (AUD-014) | none | all 5 (background, lock, foreground, unlock; and with no session) |
| R11 OS end / failure | adapter+manager: `testSystemStopBecomesEndedBySystemInManager` | fake: `testMicrophoneLostStopsWithReason` | AV: `testAResetThatCannotRebuildEndsAsFailedAndPlaysNothingElse` | none | none | all 5 through adapter+manager |
| R12 restart after terminal | fake: `testRestartAfterEndedBySystem` | none | adapter: restart of a running session only | adapter (same) | none | all 5 after every terminal outcome |
| R13 switch | fake: `testOnlyOneActiveSourceAndSwitchStopsOldFirst` (Microphone → In-App only), `testFiftyRapidCyclesEndInLastActionWithoutDuplicates` | fake | fake | none | none | 6 ordered pairs of real adapters + 3 self-restarts |
| R14 release / no callback after deallocation | none | none | none | none | none | all 5 adapters and the manager |

Summary: before QA-007, 3 of the 14 invariants (R2, R8, R14) had no test for any source, and none
was checked for all three sources through real adapters.

## Decisions

### D1 — Fakes at the lowest seam, not `FakeAudioSource`

- **Decision**: The suite drives the real adapters over new conformance fakes of the three platform
  seams, and the real `CaptureManager` over the adapters.
- **Rationale**: `FakeAudioSource` replaces the adapter itself, so it cannot find adapter defects
  (it already implements the contract by construction).
- **Alternatives**: Reusing `FakeStreamDriver`, `FakeMicrophoneBackend`, `FakePlaybackBackend`. They
  lack a common interface, the microphone fake keeps no sink or event callback, and other suites
  depend on their exact counters; changing them would risk those suites.

### D2 — XCTest with loops over configurations

- **Decision**: One `XCTestCase`; each test iterates the configurations and prefixes failure
  messages with the configuration name; a fresh rig per configuration.
- **Rationale**: Same framework as all CaptureKit tests, runs under `swift test` on macOS and Linux
  and under `xcodebuild` without any setup. Swift Testing's parameterized tests would give one
  result per argument, but the package has no Swift Testing tests yet and Linux CI's toolchain
  behavior with mixed frameworks is unverified here.
- **Alternatives**: An abstract `XCTestCase` subclass per configuration (one subclass per
  configuration and a base class whose own tests must not run; more boilerplate for the same
  coverage).

### D3 — Determinism

- **Decision**: Everything on the main actor; `ManualClock` and `stepAnalysisForTesting()` drive the
  classifier; a wait helper polls a condition with `Task.yield()` and a 5 s ceiling; "nothing
  changed" is proven by a marker event (`formatChanged`, which only appends `formatChange` to the
  lifecycle log) sent after the event under test.
- **Rationale**: The manager handles a source's events strictly in order (one `for await` loop that
  awaits each event's serialized operation), so the marker's log entry means the earlier event was
  fully handled. No fixed sleeps, no assumptions about other threads.

### D4 — Start on a started source

- **Decision**: The adapter ends its current session first (stop, then start). See spec
  Clarifications.
- **Rationale**: Constitution VII ("Start/stop MUST be idempotent"). Reading the platform backends
  shows why it matters: `AVMicrophoneBackend.start` on a running backend builds a second
  `AVAudioEngine` with a second tap into the same sink and adds a second set of notification
  observers without stopping the first; `SCKStreamDriver.start` would present the picker and create
  a second `SCStream`. Only `AVInAppPlaybackBackend` protects itself ("A start while started … must
  not leave a second graph playing"). The adapters are where the guard belongs, since every backend
  sits behind one.

### D5 — Microphone and the AUD-014 policy table

- **Decision**: The contract follows FR-050 and AUD-014-R9 for Microphone's return to the
  foreground during an open interruption (it resumes, and the resume re-checks the session), and
  records the mismatch with policy rows 5-7's claim as a finding (spec Clarifications).
- **Rationale**: R9 is a MUST; changing feature 001 behavior needs device evidence this feature
  cannot produce.

### D6 — Platforms

- **Decision**: All five configurations run everywhere the package tests run (macOS host, Linux,
  iOS simulator), because `ScreenCaptureSource` and `StreamDriver` compile without ScreenCaptureKit
  (only `SCKStreamDriver` is compiled out).
