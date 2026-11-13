# Implementation Plan: AUD-005 Shuffle with history

**Branch**: `feature/aud-005` (spec directory `023-aud-005-shuffle-with-history`) | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/023-aud-005-shuffle-with-history/spec.md`

## Summary

The queue of imported audio (AUD-003) is already the transport's `MutablePlayOrder`, and AUD-004 lets
it answer the end of a track by repeat mode. AUD-005 adds a shuffled order with a play history on top
of the queue's `ids`, as AUD-003-R19 planned, extending the same seams:

1. `CaptureKit`, pure Foundation (Linux too):
   - `ShuffleGenerator` (new, `InAppPlayback/ShuffleGenerator.swift`): SplitMix64 with a documented
     bounded-index rule, Fisher-Yates shuffle, `cycleSeed(seed, cycle)` and an FNV-1a hash for import
     positions. No standard-library random algorithms (research AUD-005-D1).
   - `ShuffleState` (new, `InAppPlayback/ShuffleState.swift`): a value type with the seed, cycle,
     shuffled `order`, `played` count and the bounded `history` with its cursor. Pure functions:
     `next`, `previous`, `endOfTrack`, `didMove`, and the edit hooks (insert next, append, import,
     remove, clear, repair). It holds identifiers only; `PlayQueue` maps them to items.
   - `PlayOrder.swift`: `PlaybackMove` (`.start`, `.next`, `.previous`, `.endOfTrack`) and
     `MutablePlayOrder.playbackDidMove(to:by:)` with a default that calls `playbackDidMove(to:)`, so
     existing conformers and fakes are unchanged (research AUD-005-D3).
   - `PlayQueue`: `isShuffled`, `setShuffle(_:)`, `toggleShuffle()`, an injected `seedSource`, and
     `item(after:)`, `item(before:)`, `endOfTrack(after:)`, `startItem` answered from `ShuffleState`
     while shuffled; every edit also updates the shuffle state; stored like every edit.
   - `PlayQueueRecord`: optional `shuffle`, `shuffleSeed` (hex string), `shuffleCycle`,
     `shuffleOrder`, `shufflePlayed` in version 1, written only while shuffled (research AUD-005-D2).
2. `PlaybackTransport` reports how it moved (`playbackDidMove(to:by:)`): prepare = `.start`, Next =
   `.next`, Previous = `.previous`, the end of a track and a cue = `.endOfTrack`. Nothing else changes:
   the 3-second rule stays in the transport; toggling Shuffle is a queue change that only re-evaluates
   looping (AUD-003-R8), never a command.
3. `CaptureUI`: shuffle strings in `UIStrings`; an optional Shuffle button in `TransportBar` (shown when
   a value and a toggle action are given); a "Shuffle" toggle row in `PlayQueueView`.
4. App (thin): `ControlsOverlay` passes `queue.isShuffled` and `toggleShuffle` to `TransportBar` for
   imported audio. One UI test turns Shuffle on and off from both places and relaunches.

The acceptance (AUD-005-S1 to S4) is proved by short pure tests: scripted Next/Previous sequences for
a fixed seed against literal expected sequences, 20-cycle no-repeat checks for three seeds, each repeat
mode at the end of a cycle, each edit kind; plus scripted-backend transport tests (toggle keeps the
position, the move reasons reach the queue) and record golden bytes.

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: Foundation, Observation, SwiftUI (UI only). No new dependency.

**Storage**: `queue.json` stays version 1; optional shuffle fields (data-model.md). Same atomic write,
1 MB limit, damaged and newer-version handling (AUD-003-R13, R14).

**Testing**: XCTest. CaptureKit pure tests (`ShuffleGeneratorTests`, `ShuffleQueueTests`,
`ShuffleTransportTests`, record tests in `PlayQueueStoreTests`) run on the host, Linux
(`-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`) and the iOS 27.2 simulator; CaptureUI `ShuffleStringsTests`; app
`ShuffleUITests` on the simulator. No wall-clock assertions; seeds injected.

**Target Platform**: iOS/iPadOS 26.5+ (unchanged).

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: every new unit test ≤ about 1-2 s (owner rule 7); a shuffle step is O(n) in the
queue length on the main actor (n ≤ a few thousand), off the audio path.

**Constraints**: nothing on the real-time audio thread (Constitution VII); no networking; public APIs.

**Scale/Scope**: queues up to the library size; history 100 entries.

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | Foundation and SwiftUI only. PASS |
| IV. Truthful source labeling | The source stays "In-App Playback"; Shuffle changes no label. PASS |
| VI. Modular boundaries | Logic in CaptureKit, strings and views in CaptureUI, app wiring only. PASS |
| VII. Real-time audio safety | Main-actor decisions only; the audio callbacks are untouched. PASS |
| IX. Pinned dependencies and license review | No new dependency; SplitMix64 and FNV-1a are public-domain algorithms written here. PASS |
| X. Evidence-based quality | Tests first with a recorded red run; device check tagged `{device}`. PASS |
| Privacy | The record gains identifiers of tracks already stored; no titles, no times, no network. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/023-aud-005-shuffle-with-history/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/shuffle.md
├── contracts/ui-strings.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/
├── ShuffleGenerator.swift        (new)
├── ShuffleState.swift            (new)
├── PlayOrder.swift               (PlaybackMove, playbackDidMove(to:by:))
├── PlayQueue.swift               (shuffle)
└── PlaybackTransport.swift       (move reasons)
Packages/CaptureKit/Sources/CaptureKit/AudioLibrary/PlayQueueRecord.swift   (optional fields)
Packages/CaptureKit/Tests/CaptureKitTests/
├── ShuffleGeneratorTests.swift, ShuffleQueueTests.swift, ShuffleTransportTests.swift (new)
└── PlayQueueStoreTests.swift     (shuffle record cases)
Packages/CaptureUI/Sources/CaptureUI/{UIStrings,TransportBar,PlayQueueView}.swift
Packages/CaptureUI/Tests/CaptureUITests/ShuffleStringsTests.swift (new)
Apps/projectM-iOS/Views/ControlsOverlay.swift
Apps/projectM-iOS/UITests/ShuffleUITests.swift (new)
```

**Structure Decision**: extend the existing packages; no new package, no `project.yml` change (the UI
test target takes every file under `Apps/projectM-iOS/UITests`, project.yml `projectM-iOSUITests`).

## Rollback

- Code: revert the feature's commits; nothing else depends on them.
- Data: an AUD-004 app reads a shuffled `queue.json` (it ignores the extra keys) and keeps the queue
  and the repeat mode; when it rewrites the file the shuffle keys disappear and Shuffle reads Off.

## Complexity Tracking

None.

## Analysis (speckit-analyze, 2026-11-13)

- Coverage: AUD-005-R1 to R14 each map to at least one task (R13 added to AUD-005-T04 (l)); R15 is AUD-005-T17 `{device}`.
- Licensing: SplitMix64 and FNV-1a are public-domain algorithms implemented here; no code copied, no dependency (Constitution IX).
- Privacy: the record gains only identifiers already stored, a seed and counters; no titles, times or listening log beyond the current cycle; nothing leaves the device.
- Cross-feature: amendments to AUD-006-R15/R16, AUD-004-R5 and AUD-003-R13 apply only while Shuffle is on; AUD-003-R19 (room for shuffle) is fulfilled. No constitution conflict.
