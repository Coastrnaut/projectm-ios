# Implementation Plan: AUD-004 Loop track and queue

**Branch**: `feature/aud-004` (spec directory `017-aud-004-loop-track-and-queue`) | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-aud-004-loop-track-and-queue/spec.md`

## Summary

Imported audio plays in the user's queue (AUD-003), which always wraps: the behavior this feature
names "All Tracks". AUD-004 adds "Off" and "One Track", a control for them, and stores the choice,
by extending the existing seams instead of adding new ones:

1. `CaptureKit` (pure Foundation, builds on Linux):
   - `RepeatMode` (`off`, `one`, `all`; `next` cycles Off → All → One → Off).
   - `PlayOrder` gains one requirement with a default: `endOfTrack(after:) -> EndOfTrackStep`
     (`.play(item)` or `.stop(cue: item?)`). The default answers `item(after:)` (nil → stop with no
     cue), so `ListPlayOrder`, the reference track, the test signals and every test fake keep their
     behavior unchanged (AUD-004-R11).
   - `PlayQueue` gains `repeatMode` (stored, observable), `setRepeatMode(_:)`, `cycleRepeatMode()`,
     and implements `endOfTrack(after:)` by mode, including the detached-current-track rules
     (AUD-004-R3 to R5, R10). `item(after:)`/`item(before:)` are unchanged: Next and Previous wrap in
     every mode (AUD-004-R7).
   - `PlayQueueRecord` gains an optional `repeatMode` field in version 1 (written only when not All;
     missing or unknown reads All; research AUD-004-D2).
2. `CaptureKit` playback: `PlaybackTransport` asks `endOfTrack(after:)` for the end of a track and for
   whether the current track repeats (`.play` of the same id). On `.stop(cue:)` it stops as Stop
   playback does and, with a cue, selects the cued item at 0:00 while stopped (AUD-004-R5); Play at
   the very end with a cue starts the cued item (R6). A mode change is a queue change: the existing
   `onOrderChange` → `orderDidChange()` → `updateLooping` path applies it at once without a cut
   (AUD-003-R8, AUD-004-R9). No change to the backend, the graph or the tap.
3. `CaptureUI`: repeat strings in `UIStrings` (`repeatLabel`, `repeatValue`, `repeatAnnouncement`, `repeatIcon`, `repeatFooter`; contracts/ui-strings.md); an
   optional Repeat button in `TransportBar` (shown when a mode is given); a "Repeat" section with
   three selectable rows in `PlayQueueView`.
4. App (thin): `ControlsOverlay` passes the queue's mode and a cycle action to `TransportBar` when the
   transport shows the queue (imported audio). `PlayQueueView` reads the queue it already gets, so
   both sheets get the section without app changes. A UI test sets each mode and relaunches.

The acceptance (AUD-004-S1 to S3) is proved by package tests with three generated counter tracks
played through the production transport, source, AV backend and graph in offline manual rendering
with an injected manual clock (the AUD-006/AUD-003 pipeline rig): for each mode, the end of the
current track and the end of the queue, frame-exact; mode switches mid-track; and the same scenario
run twice compared sample sequence for sample sequence.

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: system frameworks already in use only: Foundation, Observation, AVFAudio
(through the unchanged graph), SwiftUI. No new dependency.

**Storage**: `queue.json` (AUD-003) keeps schema version 1 and gains an optional `"repeatMode"`
string (`"off"` or `"one"`; absent = All Tracks). Same atomic write, 1 MB read limit, damaged and
newer-version handling (AUD-003-R13, R14). No new file; AUD-001's `index.json` untouched.

**Testing**: XCTest.
- CaptureKit, pure (Linux too, `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`): `RepeatModeTests` (the queue's
  end-of-track answers per mode, removal rules, persistence, record golden files) and
  `RepeatTransportTests` (transport + scripted backend: stop and cue, Play after the end, live loop
  flag, no commands on a mode change, interruption resume unaffected).
- CaptureKit, AVFAudio-guarded: `RepeatPipelineTests` (offline rendering, three counter tracks,
  deterministic clock; the roadmap acceptance).
- CaptureUI: `RepeatStringsTests` (pure) and a `ViewRenderTests` addition (SwiftUI-guarded).
- App: `RepeatModeUITests` (iOS 27.2 simulator) plus the existing `PlayQueueUITests`,
  `TransportUITests`, `ImportedAudioUITests`, `InterruptionUITests` and all app unit tests.

**Target Platform**: iOS/iPadOS 26.0+ (app), macOS host for package tests, Linux CI for pure logic.

**Project Type**: mobile app with SwiftPM packages.

**Performance Goals**: a mode change stores a few-KB file on the main actor, well under a frame.

**Constraints**: no cut, position change, pause or transport command on a mode change (AUD-004-R9);
nothing added on the render thread (R15); no network; no new entitlement; no wall-clock assertions in
tests (waits use a ≥30 s ceiling and conditions, never iteration budgets).

**Scale/Scope**: one mode for the one queue.

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | Only public Foundation and SwiftUI APIs; SF Symbols `repeat`, `repeat.1`. `check_compliance.py` runs. PASS |
| IV Truthful labeling | Source stays "In-App Playback"; the stopped end of queue reports Stopped through the manager's user pause, never playing (AUD-004-R16). PASS |
| V No universal-capture claims | Not touched. PASS |
| VI Modular boundaries | Logic in CaptureKit, views and strings in CaptureUI, app glue a few lines. PASS |
| VII Real-time safety | No change to the tap, graph or backend; the end-of-track decision runs on the main actor in the existing callback hop. PASS |
| X Evidence-based quality | Acceptance by deterministic offline-rendering tests; device checks tagged `{device}`. PASS |
| Privacy | Adds one enum value to a file of track identifiers in app-private storage. No upload. PASS |
| Security | The stored value is untrusted input: decoded leniently, unknown values read as All Tracks. PASS |

Post-design re-check (after data-model and contracts): unchanged, PASS.

## Project Structure

### Documentation (this feature)

```text
specs/017-aud-004-loop-track-and-queue/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── repeat-mode.md
│   └── ui-strings.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/
├── InAppPlayback/RepeatMode.swift            # new: RepeatMode, EndOfTrackStep (Foundation only)
├── InAppPlayback/PlayOrder.swift             # + endOfTrack(after:) requirement with default
├── InAppPlayback/PlayQueue.swift             # + repeatMode, setRepeatMode, cycleRepeatMode, endOfTrack
├── InAppPlayback/PlaybackTransport.swift     # end of track and looping from endOfTrack; stop and cue
└── AudioLibrary/PlayQueueRecord.swift        # + optional repeatMode in version 1
Packages/CaptureKit/Tests/CaptureKitTests/
├── RepeatModeTests.swift                     # new (Linux)
├── RepeatTransportTests.swift                # new (Linux)
├── RepeatPipelineTests.swift                 # new (AVFAudio): roadmap acceptance
└── PlayQueueStoreTests.swift                 # + golden v1 files with and without the mode
Packages/CaptureUI/Sources/CaptureUI/
├── UIStrings.swift                           # + repeat strings
├── TransportBar.swift                        # + optional Repeat button
└── PlayQueueView.swift                       # + Repeat section
Packages/CaptureUI/Tests/CaptureUITests/
├── RepeatStringsTests.swift                  # new
└── ViewRenderTests.swift                     # + transport and queue with a mode
Apps/projectM-iOS/Views/ControlsOverlay.swift # passes mode and cycle action
Apps/projectM-iOS/UITests/RepeatModeUITests.swift   # new
```

**Structure Decision**: extend existing packages; no new package or target. `project.yml`,
`AppCoordinator.swift`, `.github/workflows/ios-ci.yml` and `scripts/test_scripts.py` need no change
(targets take their folders by path; new test files are picked up automatically).

## Analysis notes (speckit-analyze, 2026-11-13)

- Coverage: R1-R5, R7, R10 → T03-T05, T08-T09; R6 → T04, T05(c); R9 → T04, T05(d); R11 → T03, T10;
  R12-R13 → T11-T15; R14 → T02, T03, T07, T08, T15; R15 → T18; R16 → T04 (state Stopped); R17 →
  T19 `{device}`. S1-S3 → T05; S4 → T15; S5 → T12, T15; S6 → T09, T10, T16, T17.
- Licensing: no new dependency or asset (SF Symbols are system symbols). Privacy: one enum value
  added to an app-private file of identifiers; the App Store privacy answers do not change.
- Cross-feature: AUD-003's `queue.json` stays version 1 (AUD-003-D8); AUD-005 (shuffle) will add
  its own `endOfTrack`/`item(after:)` answers on top of the mode; QA-007's contract suite uses
  `ListPlayOrder`, whose behavior is unchanged by the protocol default.

## Rollback

- Code: every change is additive behind the default mode. Reverting the feature's commits restores
  AUD-003 exactly; `PlayOrder`'s new requirement has a default, so no other conformer changes.
- Data: `queue.json` stays version 1. An AUD-003-only app decodes it and ignores `repeatMode`
  (proved by the existing `testUnknownKeysAreIgnored` and a new golden test), so a rollback keeps
  the queue and the current track; if that app rewrites the file, the mode is dropped and the next
  AUD-004 launch reads All Tracks, today's behavior. Nothing to migrate back.

## Complexity Tracking

| Item | Why needed | Simpler alternative rejected because |
|---|---|---|
| `endOfTrack(after:)` beside `item(after:)` | In One Track the end of a track repeats it, while Next must still move on (AUD-004-R7); in Off the end of the queue stops while Next wraps | Answering the same item from `item(after:)` in One Track would make Next restart the track; answering nil in Off would make Next a dead button on the last track |
| Stop with a cue | Off must end at the first track at 0:00 so Play has something to play (AUD-004-R5, R6) | Staying at the end of the last track leaves Play doing nothing (today's nil answer in `play()`) |
