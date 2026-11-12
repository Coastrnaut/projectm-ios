# Implementation Plan: AUD-014 Audio session interruption recovery

**Branch**: `feature/aud-014` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/009-aud-014-audio-session-interruption-recovery/spec.md`

## Summary

In-App Playback already reacts to interruptions, a lost output route and the app lifecycle
(feature 001; AUD-006 added the user pause). This feature adds the missing parts found by the
audit in the spec's Baseline and in [research.md](research.md):

1. A pure, typed `InterruptionPolicy` (CaptureKit) that decides resume / stay paused / stay stopped
   / fail for every combination of its inputs, and that `CaptureManager` and the playback backend
   both consult.
2. `CaptureManager` remembers an open interruption of In-App Playback (was playback eligible, what
   iOS indicated, did the user change the transport, was the output lost, is the app presentable)
   and resumes only when the policy says so; a refused Play during an open interruption keeps the
   session.
3. The playback backend holds the position itself when an interruption begins (no stale UI read),
   restarts the engine after `AVAudioEngineConfigurationChange`, rebuilds the graph after a
   media-services reset, and takes its notifications through an injectable seam so that all of it
   is tested with synthetic events on the offline engine.
4. Two explanation strings and a VoiceOver announcement for "interrupted" and "paused because the
   output was disconnected" (CaptureUI, app).

Microphone and System/App Capture code paths are not changed.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2, iOS SDK 27.2

**Primary Dependencies**: AVFAudio (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioSession`),
Foundation `NotificationCenter`, Swift `Synchronization` atomics; no new dependency

**Storage**: none (the open interruption and the held position live in memory only)

**Testing**: XCTest. `swift test` on the macOS host for AudioCore, CaptureKit, CaptureUI (and the
Linux-compatible subset by construction); the same suites with `xcodebuild test` on the iOS 27.2
simulator; app unit and UI tests on the simulator. Real audio only through AUD-006's offline
manual-rendering engine

**Target Platform**: iOS/iPadOS 26.0 and later (ADR-0002); macOS host for package tests

**Project Type**: mobile app with SwiftPM packages (`Packages/CaptureKit`, `Packages/CaptureUI`,
`Apps/projectM-iOS`)

**Performance Goals**: held position within 0.25 s of the audio last heard (AUD-014-R10); resume
within 2 s (FR-050, AUD-014-R5); restart after a hardware change within 1 s (AUD-014-R15)

**Constraints**: nothing blocking or allocating on the tap callback: one more atomic add
(AUD-014-R21); public APIs only; no entitlement, background mode, network or persistence
(AUD-014-R22); export vocabulary unchanged (AUD-014-R23)

**Scale/Scope**: about 350 lines of production Swift in 2 packages and the app, about 900 lines of
tests

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check |
|---|---|
| I. Public Apple APIs only | `AVAudioSession.interruptionNotification`, `routeChangeNotification`, `mediaServicesWereResetNotification`, `AVAudioEngineConfigurationChange`: all public. Pass |
| II, III. Capture feasibility, ScreenCaptureKit | Not touched; System/App Capture code unchanged. Pass |
| IV. Truthful source labeling | Status stays the classifier's output; "Active audio" only after new audio is verified following every restart (AUD-014-R13). The explanation lines never name a capture source. Pass |
| V. No universal-capture claims | None added. Pass |
| VI. Modular boundaries | Platform notifications stay inside CaptureKit's backend; the policy is pure; the UI reads `CaptureManager` only. Pass |
| VII. Real-time audio safety | The tap gains one atomic add (frames delivered). Engine restart and graph rebuild run on the main actor. Start/stop stay idempotent; observers are removed at stop; "format changes, route changes, interruptions, and stream restarts MUST be handled without crashing" is the purpose of User Story 4. Pass |
| VIII, IX. projectM, dependencies | Not touched; no new dependency. Pass |
| X. Evidence-based quality | Deterministic unit tests for the policy and the event orders; the real phone call is a `{device}` task, not claimed (AUD-014-S6). Pass |
| Privacy | Playback starts only after the user's action; a resume continues it under the policy; nothing recorded or stored. Pass |

No violation, so Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/009-aud-014-audio-session-interruption-recovery/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── interruption-policy.md
│   └── ui-strings.md
├── checklists/requirements.md
└── tasks.md                      (speckit-tasks)
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/
├── InterruptionPolicy.swift                 NEW  pure decision (contracts/interruption-policy.md)
├── CaptureManager.swift                     CHG  open-interruption record, policy at interruption
│                                                 end and on foreground/unlock, refused Play keeps
│                                                 the session, route loss while not running,
│                                                 pause(asStop:), noteUserTransportChange()
├── InAppPlayback/AudioSessionSignal.swift   NEW  platform-neutral signals + the iOS notification
│                                                 observer with an injectable NotificationCenter
├── InAppPlayback/AVInAppPlaybackBackend.swift CHG handle(_ signal:), hold at "began", engine
│                                                 restart, graph rebuild after a reset
├── InAppPlayback/InAppPlaybackGraph.swift   CHG  hold(), delivered-frame position fallback,
│                                                 start(atFrame:held:), restartAfterEngineStop()
├── InAppPlayback/PlaybackTapGate.swift      CHG  delivered-frame counter (atomic)
└── InAppPlayback/PlaybackTransport.swift    CHG  tells the manager about Stop playback and about
                                                  seek / next / previous
Packages/CaptureKit/Tests/CaptureKitTests/
├── InterruptionPolicyTests.swift            NEW  all 864 combinations
├── InterruptionRecoveryTests.swift          NEW  CaptureManager + transport on the scripted backend
├── InterruptionPipelineTests.swift          NEW  production backend on the offline engine
├── AudioSessionSignalTests.swift            NEW  notification parsing and observer lifetime
└── SourceAdapterTests.swift                 CHG  FakePlaybackBackend can refuse resume
Packages/CaptureUI/Sources/CaptureUI/
├── UIStrings.swift                          CHG  two explanation strings + lookup
└── StatusBanner.swift                       CHG  shows the explanation for In-App Playback
Packages/CaptureUI/Tests/CaptureUITests/InterruptionStringsTests.swift   NEW
Apps/projectM-iOS/
├── Automation/SyntheticSessionEvents.swift  NEW  the notifications iOS posts (shared by sc009
│                                                 and the UI-test panel; DEBUG || PROJECTM_AUTOMATION)
├── Automation/AutomationRunner.swift        CHG  uses SyntheticSessionEvents (same sequence)
├── Debug/UITestSessionEventPanel.swift      NEW  DEBUG, `-uitestSessionEvents`
├── Views/VisualizerView.swift               CHG  panel (DEBUG), announcement on reason change
├── Views/SourceStatusIndicator.swift        CHG  announcement text with the explanation
├── Tests/InterruptionAnnouncementTests.swift NEW
└── UITests/InterruptionUITests.swift        NEW  synthetic interruption while an imported track plays
scripts/test_scripts.py                      CHG  one class: the 009 string contract
```

**Structure Decision**: extend CaptureKit, CaptureUI and the app in place; no new package. Shared
files touched by other features (`project.yml`, CI workflow, `AppCoordinator.swift`,
`docs/privacy-policy.md`) are not edited: the app targets pick up new files by folder, and
`scripts/test_scripts.py` gets one appended class.

## Design

Details and alternatives are in [research.md](research.md) (decisions AUD-014-D1 to D10); types in
[data-model.md](data-model.md); the decision table in
[contracts/interruption-policy.md](contracts/interruption-policy.md).

### 1. InterruptionPolicy (pure)

`InterruptionPolicy.decide(_ input: Input) -> Decision`. No state, no Foundation. Inputs and
outcomes exactly as AUD-014-R1. Rules in order (first match wins) are the contract. The manager
uses it for In-App Playback at "interruption ended" and at "became presentable"; the backend uses
it after an engine restart or rebuild (`signal: .notInterrupted`). The Microphone and System/App
Capture rows state feature 001's behavior; their code paths in `CaptureManager` stay as they are
and existing tests pin them (AUD-014-R9, S5).

### 2. CaptureManager: the open interruption

New private state, In-App Playback only: `interruption: OpenInterruption?` (eligible, signal,
userChangedTransport, outputLost), `isPresentable` (false after background/lock, true after
foreground/unlock) and `userPauseIsStop`.

- `interruptionBegan`: no record → create it (eligible = running, or paused only by the
  lifecycle); a record whose signal is `.pending` → unchanged (duplicate); a record that already
  ended → signal back to `.pending`, eligibility kept only if a resume was indicated and deferred.
  Running → `apply(.interruptionBegan)` as today; paused by the lifecycle → reason `.interrupted`.
- `interruptionEnded(shouldResume)`: no record → ignored. Otherwise store the signal and decide.
  `.resume` → `resumeInner()`. Otherwise stay; if the output was lost the state becomes Paused
  with `audioRouteChanged`.
- `outputRouteLost`: as today while running; additionally recorded during an interruption and
  while paused by the lifecycle (reason `audioRouteChanged`, which also blocks FR-050's resume).
- background / lock: as today, but with a record the Paused state keeps the `.interrupted` reason.
- foreground / unlock: with a record → decide (resume only if a resume was indicated); without →
  today's FR-050 path.
- `pause()`: marks the record as changed by the user. `pause(asStop: true)` (Stop playback) also
  sets `userPauseIsStop`. `noteUserTransportChange()` (seek, next, previous) marks the record.
- `resume()` (the user's Play, or the banner's Resume): tries to resume; success clears the
  record. Failure while the record's signal is `.pending` leaves everything as it was
  (AUD-014-R8); any other failure ends the session as today.
- `stopCurrent()` and `beginAttempt()` clear the record.

### 3. Backend and graph

- `AudioSessionSignal` (`interruptionBegan(outputDisconnected:)`, `interruptionEnded(shouldResume:)`,
  `outputRouteLost`, `engineConfigurationChanged`, `mediaServicesReset`) is what the backend
  handles; `AudioSessionObserver` (iOS) turns notifications from an injected `NotificationCenter`
  into signals. The engine notification is observed on every platform with AVFAudio.
- began → `graph.hold()`, then the source event. `hold()` is `pause()` that also works when iOS
  already stopped the engine: the position is the player's own time when readable, otherwise the
  start frame plus the larger of the last read and the frames the tap delivered since the last cut
  (a new atomic counter in `PlaybackTapGate`, converted to the track's rate).
- configuration change → policy with `before: held ? .paused : .playing`; `.resume` →
  `graph.restartAfterEngineStop()` (hold, start the engine, cut, schedule from the held frame).
  Failure → `.failed(.inAppPlaybackFailed)`.
- reset → load the current track again, build a new graph at the old graph's position and held
  state (`start(atFrame:held:)`), activate the session again; failure → `.failed(...)`.
- `replaceTrack` remembers the current track for the rebuild.

### 4. UI

`UIStrings.playbackHoldDetail(mode:reason:)` returns the explanation for In-App Playback with
reason `.interrupted` or `.audioRouteChanged`, nil otherwise. `StatusBanner` shows it under the
feature 001 message. `VisualizerView` announces it when the reason changes
(`SourceStatusIndicator.holdAnnouncement`).

## Testing strategy (deterministic)

| Layer | Suite | What it proves |
|---|---|---|
| Policy | `InterruptionPolicyTests` | all 864 combinations against the contract's rules; the six conditions of AUD-014-R2; Microphone and System/App Capture rows (S1) |
| Manager + transport, scripted backend | `InterruptionRecoveryTests` | every scenario of User Stories 1 to 3 and every order in AUD-014-S4, with resume/pause counts (no double start) |
| Production backend, offline engine | `InterruptionPipelineTests` | held position after the engine was stopped behind the app's back; frame-exact resume without stale frames; configuration change; reset; observers idempotent across stop/start (S2, S3) |
| Notifications | `AudioSessionSignalTests` | parsing of type/option/reason; observer registered once and removed (iOS simulator; the engine notification also on the host) |
| Strings | `InterruptionStringsTests`, `scripts/test_scripts.py` | contract ↔ `UIStrings.swift` |
| App | `InterruptionAnnouncementTests`, `InterruptionUITests`, existing `TransportUITests`, `ImportedAudioUITests`, `StatusUITests` | status line and transport before, during and after a synthetic interruption of an imported track |
| Device | `{device}` tasks | real phone call, headphones, iOS 27 delivery of the older notice (S6) |

Red first: the new suites are written and run before the production change, and the failing run
is recorded in tasks.md.

## Cross-feature notes, licensing, privacy (speckit-analyze 2026-11-12)

- **AUD-006**: `PlaybackTransport`'s public API is unchanged; `CaptureManager.pause()` gains a
  defaulted parameter. The AUD-006 report's stale position is fixed in the graph (design 3).
- **AUD-007** (route indicator), **AUD-012** (source crossfade): not started here. The lost-route
  handling keeps feature 001's reason and event.
- **AUD-015** (background playback policy): `isPresentable` is the policy input a background
  audio mode would relax; this feature adds no background mode.
- **QA-007** (source contract suite, depends on this feature): `InterruptionPolicy` and its types
  are public so the suite can state the same invariants for fakes.
- **PRE import validation** (in progress in another worktree): no shared file is edited except one
  appended class in `scripts/test_scripts.py`.
- **CaptureLab** uses `CaptureManager` and `StatusBanner`; it is built in AUD-014-T23.
- **Licensing**: no new dependency, asset or font. Test audio is generated by the tests.
- **Privacy**: no new data, permission or network use; `docs/privacy-policy.md` is unchanged
  (AUD-014-T28).

## Local persistence and rollback

Nothing is persisted and no stored format changes, so there is no migration. Rollback is reverting
this feature's commits (or the merge commit): `SourceEvent`, `StopReason`, `AudioState` and the
export schema are unchanged, so no other feature or stored data depends on the new code.

## Complexity Tracking

No constitution violation to justify.
