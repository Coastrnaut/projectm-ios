# Tasks: AUD-003 Audio library queue

**Input**: Design documents in `specs/015-aud-003-audio-library-queue/` (spec.md, plan.md,
research.md, data-model.md, contracts/, quickstart.md)

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded in AUD-003-T06 before any production change.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator (udid `77E17861-E687-4274-8A84-14224F32BE3E`,
"iPhone Air").

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions "T07" is short for `AUD-003-T07`. The app builds in the feature
worktree with the 28 included presets; `PresetTests.testBundledIncludedScopeMatchesRelease1_0`
needs the full preset library and is known to fail there (not evidence for or against this feature).

## Phase 1: Setup

- [ ] AUD-003-T01 Confirm the baseline before any change: `swift test` for `Packages/CaptureKit`, `Packages/CaptureUI`, `Packages/Diagnostics`; `python3 scripts/test_scripts.py`, `scripts/check_compliance.py`, `scripts/validate_docs.py`. Record the counts. Evidence: command output.

## Phase 2: Foundational tests (blocking; written first, must fail)

- [ ] AUD-003-T02 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/PlayQueueStoreTests.swift` (no AVFAudio, runs on Linux): record round trip with sorted keys and `"schemaVersion": 1`; invalid UUIDs and repeated ids dropped; invalid `currentTrackID` dropped; missing file → `.missing`; garbage → `.damaged` and the file moved to `queue.damaged.json`; `schemaVersion` 2 → `.newerFormat(2)` with the file byte-for-byte unchanged; a file over 1 MB → `.damaged`; a failing writer leaves the previous file. Evidence: red, then green in T07.
- [ ] AUD-003-T03 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/PlayQueueTests.swift` (no AVFAudio): seeding from library order when there is no record; `didImport` inserts unknown ids at the top (last given first) and ignores known ones; `setLibrary` drops ids no longer in the library; `playNext` (after current; top when none; moves an already queued id), `addToEnd`, `remove`, `move(fromOffsets:toOffset:)` with SwiftUI semantics, `moveUp`/`moveDown` at both ends, `clear`; `item(after:)`/`item(before:)` wrap; the detached current track (removed while current) continues with the entry at its former index, wraps past the end, and with an empty queue yields nil; `startItem`; every edit stores the record and calls `onOrderChange`; a new `PlayQueue` over the same folder restores order and current id; newer-format load stores nothing. Evidence: red, then green in T08.
- [ ] AUD-003-T04 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/QueueTransportTests.swift` (transport with the existing fake backend, no AVFAudio): prepare reports the current item to the queue; Next and the end of a track follow a reorder made after prepare; a queue edit sends no transport command and does not set the interruption's user-change flag (`CaptureManager` stays resumable, AUD-003-R12); adding a second track to a lone queue sets the backend to non-looping through `updateLooping(false)`, removing it sets looping again; removing the playing track then Next plays the entry at its former place. Evidence: red, then green in T09-T10.
- [ ] AUD-003-T05 [P] Write `Packages/CaptureKit/Tests/CaptureKitTests/QueuePipelineTests.swift` (inside `#if canImport(AVFAudio) && canImport(CryptoKit) && canImport(UniformTypeIdentifiers)`), the roadmap acceptance (AUD-003-S1) through `PlaybackTransport` → `InAppPlaybackSource` → `AVInAppPlaybackBackend` → `InAppPlaybackGraph` in offline rendering with three counter tracks A, B, C (distinct offsets) in a `PlayQueue` over a temporary folder: (a) while A plays, move C above B: the counter stream of A stays consecutive across the edit, the position is unchanged by the edit, the state stays `.playing`, then A ends and C (not B) starts; Next from C goes to B; (b) a new `PlayQueue` over the same folder after `setLibrary` holds A, C, B and the current id of the last played track; (c) a lone looping track, then a second added while it plays: the stream stays consecutive, A plays to its last frame once and B follows; (d) the reverse (remove the other track) makes A wrap to frame 0 without a gap. Evidence: red, then green in T11.
- [ ] AUD-003-T06 Run the new tests and record the red run (compile failure: `PlayQueue`, `PlayQueueStore`, `MutablePlayOrder`, `updateLooping` do not exist). Evidence: log line in this task.

## Phase 3: User Story 1 + 2 — reorder while playing, persist (P1) 🎯 MVP

**Goal**: the queue is the play order; edits follow at once without interrupting; order survives relaunch.
**Independent test**: T05 (package) and T17 (UI).

- [ ] AUD-003-T07 [US2] Implement `Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/PlayQueueRecord.swift` and `PlayQueueStore.swift` (Foundation only): `schemaVersion` 1, `trackIDs` UUID strings in order, `currentTrackID` optional; "invalid and repeated entries dropped on decode"; read limit 1 MB; atomic write; damaged file moved to `queue.damaged.json`; newer format never written. Evidence: T02 green on host and with `-DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-003-T08 [US1] Implement `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/PlayQueue.swift` (`@MainActor @Observable`, `MutablePlayOrder`) and add `MutablePlayOrder` to `PlayOrder.swift`, per data-model.md and contracts/play-queue.md. Evidence: T03 green on host and with `-DAUDIOCORE_NO_AVFAUDIO`.
- [ ] AUD-003-T09 [US1] `Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackSource.swift`: `InAppPlaybackBackend.updateLooping(_:)` with a protocol-extension default; `InAppPlaybackSource.updateLooping(_:)`. Evidence: T04 compiles; existing fakes unchanged.
- [ ] AUD-003-T10 [US1] `PlaybackTransport.swift`: hook `MutablePlayOrder` in `prepare` (unhook the previous order), report `playbackDidMove` after `prepare` and every successful track change, add `orderDidChange()` that recomputes looping and calls `source.updateLooping` when it differs; no `noteUserTransportChange` for edits. Evidence: T04 green.
- [ ] AUD-003-T11 [US1] `InAppPlaybackGraph.updateLooping(_:)` and `AVInAppPlaybackBackend.updateLooping(_:)`: re-queue at the reached frame without a cut when playing; flag only when held, at the end or silenced; the AUD-014 fallback position subtracts the frames rendered before the re-queue. Evidence: T05 green; `SeekableGraphTests`, `TransportPipelineTests`, `InterruptionPipelineTests`, `AudioSourceContractTests` still green.
- [ ] AUD-003-T12 [US1] [P] Write `Apps/projectM-iOS/Tests/PlayQueueCoordinatorTests.swift` first (red), then make `Apps/projectM-iOS/Coordinators/AudioLibraryCoordinator.swift` own a `PlayQueue` over the library folder (`PlayQueueStore(directory:)`), call `setLibrary` after every ready refresh, `didImport` with the ids of `.imported` outcomes, expose the queue edits; tests: import three fixtures → queue order equals the list; remove from library removes from queue; a second coordinator over the same folder restores a reordered queue. Evidence: `xcodebuild test` {sim}.
- [ ] AUD-003-T13 [US1] `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`: `play(_:)` uses the queue as the order (adding the track at the end first when not queued); `playQueue()` starts `startItem`; `showQueue` flag; `transportQueueAvailable` (current item is an imported track). Evidence: `TransportCoordinatorTests` and T12 green {sim}.

## Phase 4: User Story 3 + 4 — choose what is queued, accessibly (P2)

**Goal**: add/remove/clear from the chooser and the queue sheet; VoiceOver actions; Dynamic Type.
**Independent test**: T14 strings tests and T17 UI test.

- [ ] AUD-003-T14 [US4] [P] Write `Packages/CaptureUI/Tests/CaptureUITests/QueueStringsTests.swift` first (red): every string of contracts/ui-strings.md, `queueRowLabel(count:)` singular and plural, `queuePosition`, row accessibility labels with and without the marker. Then add the strings to `Packages/CaptureUI/Sources/CaptureUI/UIStrings.swift`. Evidence: `swift test --package-path Packages/CaptureUI`.
- [ ] AUD-003-T15 [US3] `Packages/CaptureUI/Sources/CaptureUI/PlayQueueView.swift` (new) per contracts/ui-strings.md: Up Next list with Edit-mode drag (`onMove` only in Edit mode), row menu and VoiceOver actions Move Up / Move Down / Remove from Queue, swipe to remove, current marker, Clear Queue with confirmation, Not in Queue section with Add to Queue / Play Next, optional Play Queue button, Done; titles up to two lines, Dynamic Type. Add a render test in `Packages/CaptureUI/Tests/CaptureUITests/ViewRenderTests.swift` inside the existing SwiftUI guard. Evidence: `swift test` CaptureUI host and {sim}.
- [ ] AUD-003-T16 [US3] `ImportedAudioSection.swift` (Queue row with count; leading swipe Play Next / Add to Queue on library rows, which VoiceOver lists as actions) and `TransportBar.swift` (optional Queue button, `transportQueue`); app wiring in `Apps/projectM-iOS/ProjectMApp.swift`, `Views/ControlsOverlay.swift`, `Views/VisualizerView.swift` (sheet over the visualizer; showing it keeps the controls visible). Evidence: app builds {sim}; T17.
- [ ] AUD-003-T17 [US2] Write `Apps/projectM-iOS/UITests/PlayQueueUITests.swift`: (a) import three generated tracks, open the queue from the chooser, reorder with Move Down / Move Up actions (and Edit-mode drag where the simulator allows), check the order, terminate and relaunch without resetting the library, open the queue, check the same order, and check nothing plays (the chooser is shown); (b) start the first track, open the queue from the transport, move the last track up while playing, check the transport title is unchanged and its elapsed time did not go back, tap Next track and check the moved track plays. Evidence: `xcodebuild test -only-testing:projectM-iOSUITests/PlayQueueUITests` {sim}.

## Phase 5: Polish & cross-cutting

- [ ] AUD-003-T18 Run every package suite twice on the host (CaptureKit, CaptureUI, Diagnostics) and CaptureKit with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`; CaptureKit and CaptureUI on the simulator {sim}. Evidence: counts.
- [ ] AUD-003-T19 App unit tests and UI tests `ImportedAudioUITests`, `TransportUITests`, `InterruptionUITests`, `StatusUITests`, `PlayQueueUITests` on the simulator {sim}. Evidence: counts; known environmental failure noted.
- [ ] AUD-003-T20 `python3 scripts/check_compliance.py`, `scripts/test_scripts.py`, `scripts/validate_docs.py`. Evidence: output.
- [ ] AUD-003-T21 Update the code comments that describe the play order (`PlayOrder.swift`, `PlaybackTransport.swift` header "Nothing is persisted", `AppCoordinator.swift` header) and record the delivery in `docs/test-reports/` only if the integration session asks for it (not in this branch). Evidence: diff.
- [ ] AUD-003-T22 {device} On D1 with headphones: reorder while listening (no gap), add a second track while a lone track loops (it ends once, the next follows; listen for a repeated fragment at the edit, research AUD-003-D4), remove the playing track, reorder during a call (resume behaves as without the edit), relaunch keeps the queue. Evidence: tester note.

## Dependencies

T01 → T02-T05 (parallel) → T06 → T07 → T08 → T09 → T10 → T11 → T12 → T13 → T14-T16 → T17 → T18-T21; T22 in the final device phase.

## Parallel examples

- T02, T03, T04, T05 are separate files: write together.
- T14 can be written while T11 is being debugged.

## Implementation strategy

MVP = Phase 3 (the queue as play order, persisted, edits live) proved by T05; then the UI (Phase 4)
and the UI acceptance T17.
