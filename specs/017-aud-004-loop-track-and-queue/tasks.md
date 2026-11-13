# Tasks: AUD-004 Loop track and queue

**Input**: Design documents in `specs/017-aud-004-loop-track-and-queue/` (spec.md, plan.md,
research.md, data-model.md, contracts/, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded in AUD-004-T06 before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator (udid `77E17861-E687-4274-8A84-14224F32BE3E`,
"iPhone Air").

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions "T07" is short for `AUD-004-T07`. Stories: US1 = Off (stop after the
last track), US2 = One Track, US3 = All Tracks (default), US4 = choose, accessibly, and keep the mode.
`PresetTests.testBundledIncludedScopeMatchesRelease1_0` needs the full preset library and is known to
fail in the worktree (not evidence for or against this feature).

## Phase 1: Setup

- [ ] AUD-004-T01 Confirm the baseline before any change: `swift test` for `Packages/CaptureKit` and `Packages/CaptureUI` on the host, `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`. Record the counts. Evidence: command output.

## Phase 2: Foundational tests (blocking; written first, must fail)

- [ ] AUD-004-T02 [P] Extend `Packages/CaptureKit/Tests/CaptureKitTests/PlayQueueStoreTests.swift` (Foundation only, Linux): golden v1 file exactly as AUD-003 wrote it (`{"currentTrackID":"…","schemaVersion":1,"trackIDs":[…]}`) decodes with `repeatMode == .all` and re-encodes byte-identically; `.off` and `.one` encode as `"repeatMode":"off"`/`"one"` with sorted keys and round-trip; `"repeatMode"` "absent, not a string, or unknown ⇒ All Tracks"; the version stays 1, so the existing newer-version test (version 2) stays valid unchanged; the AUD-003 test `testUnknownKeysAreIgnored` (a v1 record with `"repeatMode":"all"`) still passes. Evidence: red, then green in T07.
- [ ] AUD-004-T03 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/RepeatModeTests.swift` (Foundation only, Linux): `RepeatMode.next` cycles off → all → one → off; default `.all`; `PlayQueue.endOfTrack(after:)` for every row of the data-model.md table in each mode (empty queue, middle, last, detached inside and past the end, unknown id); `item(after:)`/`item(before:)` wrap in every mode; `setRepeatMode` stores the record and calls `onOrderChange` (and setting the same mode does neither); `cycleRepeatMode`; a new `PlayQueue` over the same folder restores the mode; a newer-format record leaves the mode changeable but stores nothing; `ListPlayOrder`'s default `endOfTrack` (one item → `.play(self)`, several → next, empty → `.stop(cue: nil)`). `setUp`/`tearDown` must not touch main-actor state. Evidence: red, then green in T08.
- [ ] AUD-004-T04 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/RepeatTransportTests.swift` (transport + `FakePlaybackBackend`, Linux): loop flag per mode (One ⇒ looping with several tracks; All/Off ⇒ not; a lone track: All/One loop, Off does not); mode changes while playing set the flag through `updateLooping` with zero transport commands and the state `.playing`; Off at the last track's end ⇒ state `.stopped`, current = first queued, a seek to 0 or a replace of the first track while paused, session still available; Play then plays the first track; paused at the very end of the last track (a seek to the end) with Off, Play plays the first track from 0 (AUD-004-R6); Off with one track ⇒ stopped at the same track's 0; One at the end (fake end callback) ⇒ the same track, Next ⇒ the next track which loops; Off/One removal rules from data-model.md; a mode change during an interruption keeps the automatic resume (resumeCount 1). Waits poll a condition under a 30 s ceiling. Evidence: red, then green in T09.
- [ ] AUD-004-T05 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/RepeatPipelineTests.swift` (inside `#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)`), the roadmap acceptance (AUD-004-S1 to S3), production `PlayQueue` (temporary folder) → `PlaybackTransport` → `InAppPlaybackSource` → `AVInAppPlaybackBackend` → `InAppPlaybackGraph`, offline rendering at 44.1 kHz, `ManualClock`, three counter tracks A, B, C with distinct offsets: (a) All: A → B → C → A, each from its first frame, each played to its last frame, consecutive within each track; (b) One: A wraps from its last frame to frame 0 at least twice with no missing or repeated frame, B never plays; (c) Off: A → B → C, nothing after C's last frame, transport `.stopped`, current A at position 0, then Play delivers A from frame 0; (d) switches mid-track: All → One on A keeps the position within one sample and A repeats; One → All on A: A ends once and B follows; All → Off on C: C ends and playback stops; (e) scenario (c) run twice gives identical frame sequences. Evidence: red, then green in T09.
- [ ] AUD-004-T06 Run the new tests and record the red run (compile failure: `RepeatMode`, `EndOfTrackStep`, `endOfTrack`, `setRepeatMode`, `repeatMode` do not exist). Evidence: log line in this task.

## Phase 3: User Stories 1-3 — the three modes at the end of a track (P1) 🎯 MVP

**Goal**: Off, One Track and All Tracks behave as R3 to R7 and R10 say; the default is All Tracks.
**Independent test**: T03, T04, T05 green.

- [ ] AUD-004-T07 [US3] `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/PlayQueueRecord.swift`: `repeatMode: RepeatMode` (default `.all`), decoded leniently ("absent, not a string, or unknown ⇒ All Tracks"), encoded only when not `.all`; schema version stays 1. Evidence: T02 green on host and with `-DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-004-T08 [US1] [US2] New `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/RepeatMode.swift` (`RepeatMode`, `EndOfTrackStep`); `PlayOrder.swift`: `endOfTrack(after:)` requirement with the default; `PlayQueue.swift`: `repeatMode`, `setRepeatMode`, `cycleRepeatMode`, `endOfTrack(after:)` per data-model.md, the mode loaded from and saved to the record. Evidence: T03 green on host and with `-DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-004-T09 [US1] [US2] `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/PlaybackTransport.swift`: `loops` from `endOfTrack`; end of a track and Play at the end follow `EndOfTrackStep`; stop with a cue (pause as Stop playback, then select the cue while paused). Evidence: T04 and T05 green; `QueueTransportTests`, `QueuePipelineTests`, `TransportPipelineTests`, `PlaybackTransportTests`, `InterruptionPipelineTests`, `AudioSourceContractTests`, `ToneTrackTests` still green (full `swift test`).
- [ ] AUD-004-T10 [US3] Confirm All Tracks is today's behavior: every AUD-003 and AUD-006 test passes unchanged (no edits to their files). Evidence: full CaptureKit run and `git diff --stat` showing no change to those test files.

## Phase 4: User Story 4 — choose, accessibly, and keep the mode (P2)

**Goal**: a Repeat control in the transport and the queue screen; the mode survives relaunch.
**Independent test**: T11, T12 green; T15 on the simulator.

- [ ] AUD-004-T11 [P] [US4] Write `Packages/CaptureUI/Tests/CaptureUITests/RepeatStringsTests.swift` (pure, Linux): every string in contracts/ui-strings.md; announcement text; icons. Evidence: red, then green in T13.
- [ ] AUD-004-T12 [P] [US4] Extend `Packages/CaptureUI/Tests/CaptureUITests/ViewRenderTests.swift` (inside its SwiftUI guard): a `TransportBar` with each mode and a cycle action renders, at the default and the largest accessibility text size; `PlayQueueView` with a mode renders. Evidence: red, then green in T13-T14.
- [ ] AUD-004-T13 [US4] `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift` (repeat strings) and `TransportBar.swift` (optional Repeat button: identifier `transportRepeat`, label "Repeat", value the mode, icon per mode, announcement). Evidence: T11, T12 green on host.
- [ ] AUD-004-T14 [US4] `Packages/CaptureUI/Sources/CaptureUI/PlayQueueView.swift`: "Repeat" section with three rows (`repeatMode.off`, `repeatMode.one`, `repeatMode.all`), checkmark and `.isSelected` on the current one, footer. Evidence: T12 green.
- [ ] AUD-004-T15 [US4] {sim} Write `Apps/projectM-iOS/UITests/RepeatModeUITests.swift` and wire `Apps/projectM-iOS/Views/ControlsOverlay.swift` (mode and cycle action while the transport shows the queue): import three tones; in the chooser's queue the default is All Tracks; select Off, relaunch, Off is selected; play a track, the transport's Repeat reads "Off", tap → "All Tracks", tap → "One Track"; relaunch, the queue shows One Track; select All Tracks, relaunch, All Tracks. Reads from the auto-hiding controls use `showFreshControls`. Evidence: the test passes on the iOS 27.2 simulator (AUD-004-S4).

## Phase 5: Polish & cross-cutting

- [ ] AUD-004-T16 Run the full checks twice: `swift test` for CaptureKit and CaptureUI on the host (twice), CaptureKit with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`, CaptureKit and CaptureUI `xcodebuild test` on the iOS 27.2 simulator {sim}; `check_compliance.py`, `test_scripts.py`, `validate_docs.py`. Evidence: counts.
- [ ] AUD-004-T17 {sim} App: `xcodegen generate`; all app unit tests; `PlayQueueUITests`, `TransportUITests`, `ImportedAudioUITests`, `InterruptionUITests`, `RepeatModeUITests` on the iOS 27.2 simulator; count new `PosterBoard-*.ips` reports (owner rule 5). Evidence: counts.
- [ ] AUD-004-T18 Real-time and privacy review: `git diff` shows no change to `InAppPlaybackGraph.swift`, `AVInAppPlaybackBackend.swift`, `PlaybackTapGate.swift` or any tap/render callback (AUD-004-R15); no new dependency, entitlement, network API or stored data beyond the one `repeatMode` value (licensing and privacy unchanged). Evidence: diff stat and `check_compliance.py`.
- [ ] AUD-004-T19 {device} On D1 with three imported tracks: Off stops after the last track at the first track's 0:00 showing "Stopped"; One Track repeats without an audible gap on the speaker and a Bluetooth route; a phone-call interruption during One Track resumes per AUD-014; mode change during playback is inaudible. Evidence: device notes in `docs/test-reports/` (roadmap device phase only).

## Dependencies

- T01 → T02-T05 (parallel) → T06 → T07 → T08 → T09 → T10.
- T11, T12 (parallel) → T13 → T14 → T15 (needs T08 for the queue API).
- T16, T17, T18 after T15. T19 only in the device phase.

## Parallel examples

- T02, T03, T04, T05 are separate files: write together.
- T11 and T12 are separate files.

## Implementation strategy

MVP = Phase 3 (the modes in CaptureKit, proved by the offline pipeline tests); then the UI and
persistence through the UI (Phase 4); then the full regression and simulator runs.
