# Implementation Plan: AUD-003 Audio library queue

**Branch**: `feature/aud-003` (spec directory `015-aud-003-audio-library-queue`) | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/015-aud-003-audio-library-queue/spec.md`

## Summary

Imported audio plays in a fixed order (the "Your Audio" list at start time, AUD-006-R14) that the
user can neither change nor keep. This feature puts a stored, user-editable queue behind the
existing `PlayOrder` seam:

1. `CaptureKit` (pure Foundation, builds on Linux): `PlayQueueRecord` (the versioned `queue.json`
   format, decode with damage and newer-version handling), `PlayQueueStore` (atomic file I/O in the
   library folder, damaged file kept aside), and `PlayQueue`, an `@Observable` `PlayOrder` with the
   edit operations (play next, add to end, remove, move, move up/down, clear), the "detached current
   track" rule for removing the playing track, and the reconciliation with the library.
2. `CaptureKit` playback: a second protocol `MutablePlayOrder` (change notification and "playback
   moved to this item") that `PlaybackTransport` hooks in `prepare`, and a live loop update
   (`InAppPlaybackBackend.updateLooping(_:)`, `InAppPlaybackGraph.updateLooping(_:)`) that re-queues
   the playing track from the frame the player has reached, without a cut, when an edit changes
   whether it is alone in the order (AUD-003-R8).
3. `CaptureUI`: `PlayQueueView` (queue list with Edit-mode drag, Move Up/Down, remove, clear with
   confirmation, "Not in Queue" section with Add to Queue / Play Next, optional "Play Queue"),
   library-row swipe actions "Play Next" / "Add to Queue", a "Queue" button in `TransportBar`
   (optional, shown only when given), a "Queue" row in `ImportedAudioSection`, and strings.
4. App (thin): `AudioLibraryCoordinator` owns the `PlayQueue`, feeds it the library after every
   load, import and removal; `AppCoordinator` uses it as the play order for imported audio, starts
   "Play Queue", presents the sheet from the chooser and the visualizer.

The acceptance (AUD-003-S1) is proved by a package test with three generated counter tracks played
through the production transport, source, AV backend and graph in offline rendering (the AUD-006
pipeline rig): reorder while playing, assert the counter stream continues without a gap, the next
track follows the new order, and a new `PlayQueue` over the same folder restores order and current
track. A UI test imports three tracks, reorders, relaunches and reads the order (AUD-003-S2).

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: system frameworks only, already in use: Foundation (`JSONEncoder`,
`Data.write(options: .atomic)`), Observation, AVFAudio (`AVAudioPlayerNode` rescheduling), SwiftUI
(`List`, `onMove`, `EditButton`, `swipeActions`, `accessibilityAction(named:)`). No new dependency.

**Storage**: one new file, `AudioLibrary/queue.json` in Application Support (the AUD-001 library
folder), schema version 1, atomic replace; `queue.damaged.json` holds an unreadable record. The
AUD-001 `index.json` is not changed. `AudioLibrary`'s load sweep touches only `assets/` and
`incoming/`, so the queue file is safe beside it; `-uitestResetAudioLibrary` removes the whole folder
and with it the queue.

**Testing**: XCTest. CaptureKit host tests (macOS) plus the Linux approximation
(`-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`) for the pure queue, record and store; offline-rendering pipeline
tests (AVFAudio-guarded); CaptureUI string and view-render tests (SwiftUI-guarded); app unit tests
(`AudioLibraryCoordinatorTests`, `TransportCoordinatorTests`); UI tests on the iOS 27.2 simulator
(`PlayQueueUITests`, plus the existing `ImportedAudioUITests`, `TransportUITests`,
`InterruptionUITests`, `StatusUITests`).

**Target Platform**: iOS/iPadOS 26.0+ (app), macOS 15 host for package tests, Linux CI for pure logic.

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: a queue edit and its file write finish on the main actor in well under a
frame for queues of hundreds of tracks (JSON of UUIDs, a few KB).

**Constraints**: no cut, no position change, no state change on edits (AUD-003-R7); nothing on the
render thread allocates or locks (the re-queue runs on the main actor; the tap closure is unchanged);
no network; no new entitlement.

**Scale/Scope**: up to the library size (hundreds of tracks); one queue.

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | Only public Foundation, AVFAudio, SwiftUI APIs. `check_compliance.py` runs. PASS |
| IV Truthful labeling | The source stays "In-App Playback" for every queued track; the queue marks "Now Playing" only while the transport says playing. PASS |
| V No universal-capture claims | Not touched. PASS |
| VI Modular boundaries | Logic in CaptureKit, views and strings in CaptureUI, app glue thin. PASS |
| VII Real-time safety | The tap closure is unchanged; re-queueing happens on the main actor through `AVAudioPlayerNode` calls already used for seeks. PASS |
| X Evidence-based quality | Acceptance proved by deterministic offline-rendering and file tests; device checks tagged `{device}`. PASS |
| Privacy | Only track identifiers are stored, in app-private storage; no audio, titles or paths. No upload. PASS |
| Security | `queue.json` is untrusted input: bounded size (1 MB read limit), ids validated as UUIDs, duplicates dropped, unknown ids dropped. PASS |

Post-design re-check (after data-model and contracts): unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/015-aud-003-audio-library-queue/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── play-queue.md
│   └── ui-strings.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/
├── AudioLibrary/PlayQueueRecord.swift        # new: queue.json format (Foundation only)
├── AudioLibrary/PlayQueueStore.swift         # new: atomic load/save, damage handling
├── InAppPlayback/PlayQueue.swift             # new: the queue, a MutablePlayOrder
├── InAppPlayback/PlayOrder.swift             # + MutablePlayOrder protocol
├── InAppPlayback/PlaybackTransport.swift     # hooks MutablePlayOrder, live loop update
├── InAppPlayback/InAppPlaybackSource.swift   # + updateLooping, protocol default
├── InAppPlayback/AVInAppPlaybackBackend.swift# + updateLooping → graph
└── InAppPlayback/InAppPlaybackGraph.swift    # + updateLooping: re-queue without a cut
Packages/CaptureKit/Tests/CaptureKitTests/
├── PlayQueueTests.swift                      # pure queue rules (Linux)
├── PlayQueueStoreTests.swift                 # record, store, damage, newer version (Linux)
├── QueueTransportTests.swift                 # transport + fake backend (Linux)
└── QueuePipelineTests.swift                  # acceptance, offline rendering (AVFAudio)
Packages/CaptureUI/Sources/CaptureUI/
├── PlayQueueView.swift                       # new
├── ImportedAudioSection.swift                # + Queue row, Play Next / Add to Queue
├── TransportBar.swift                        # + optional Queue button
└── UIStrings.swift                           # + queue strings
Packages/CaptureUI/Tests/CaptureUITests/QueueStringsTests.swift
Apps/projectM-iOS/Coordinators/AudioLibraryCoordinator.swift   # owns PlayQueue
Apps/projectM-iOS/Coordinators/AppCoordinator.swift            # order, Play Queue, sheet flags
Apps/projectM-iOS/ProjectMApp.swift, Views/ControlsOverlay.swift, Views/VisualizerView.swift
Apps/projectM-iOS/Tests/PlayQueueCoordinatorTests.swift
Apps/projectM-iOS/UITests/PlayQueueUITests.swift
```

**Structure Decision**: extend existing packages; no new package or target. `project.yml` needs no
change (the app and test targets take their folders by path). `.github/workflows/ios-ci.yml` and
`scripts/test_scripts.py` need no change.

## Rollback

Every change is additive: removing the feature means using `ListPlayOrder` again in
`AppCoordinator.play(_:)` and ignoring `queue.json`. An older app ignores `queue.json`; a newer one
reads version 1. AUD-001's index is not touched, so a rollback never loses the library.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| Live loop update in the graph | AUD-003-R8: a lone looping track must stop looping (and the reverse) at once, keeping its position | Applying it at the next cut would make a lone track repeat forever after the user queued more tracks; waiting for the queued second pass would replay the whole track once more |
| `MutablePlayOrder` beside `PlayOrder` | The transport must hear queue edits and report track moves | Changing `PlayOrder` itself would touch `ListPlayOrder`, every test fake and AUD-016 |
