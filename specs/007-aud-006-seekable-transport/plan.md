# Implementation Plan: AUD-006 Seekable transport

**Branch**: `feature/aud-006` (spec directory `007-aud-006-seekable-transport`) | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-aud-006-seekable-transport/spec.md`

## Summary

In-App Playback plays one track per session in an endless loop and cannot be paused, moved or
changed. This feature turns the playback graph into a positioned player and adds a transport on
top of it:

1. `AudioCore`: a control-side "discard everything not yet delivered" operation on `PCMSink`,
   carried out by `AudioAnalyzer` on its own queue (sink ring, converter state, normalized ring,
   levels).
2. `CaptureKit`: `InAppPlaybackGraph` schedules file segments from a frame position, reports the
   position, seeks, pauses with a held position, changes track, and ends or loops a track. Every
   discontinuity (seek, track change, resume) is a hard cut: stop the player, close a lock-free
   tap gate, replace the mixer tap, discard downstream, schedule from the new frame.
   `InAppPlaybackBackend` and `InAppPlaybackSource` expose this; `CaptureManager` gains a user
   pause that lifecycle events never undo; `PlaybackTransport` (state, play, pause, stop, seek,
   next, previous, end-of-track) and `PlayOrder` (the seam for AUD-003) sit on top.
3. `CaptureUI`: `TransportBar` (buttons, scrubber, times) and its strings.
4. App: `AppCoordinator` owns a `PlaybackTransport`, builds the play order from the "Your Audio"
   list, and `ControlsOverlay` shows `TransportBar` for In-App Playback only.

The acceptance is proved by a generated track whose samples encode their own frame index, played
through the production graph, sink, analyzer and normalizer in AVAudioEngine's offline manual
rendering mode. Nothing is persisted; no new package, dependency, entitlement or background mode.

## Technical Context

**Language/Version**: Swift 6.4.2, strict concurrency complete (Xcode 27.2, ADR-0002).

**Primary Dependencies**: system frameworks only, all public and already in use: AVFAudio
(`AVAudioEngine`, `AVAudioPlayerNode.scheduleSegment`, `playerTime(forNodeTime:)`, `AVAudioFile`,
`AVAudioSession`), Synchronization (`Atomic`), Observation, SwiftUI. No third-party dependency.

**Storage**: none. The transport state, position and play order live in memory for the session
only (AUD-006-R30). The AUD-001 library and its `index.json` are read, never written, by this
feature.

**Testing**: XCTest in `AudioCore`, `CaptureKit` and `CaptureUI` on the macOS host and the iOS 27.2
simulator; app unit tests and XCUITests on the simulator; Python script test for the string
contract. Fixtures are generated at run time.

**Target Platform**: iOS/iPadOS 26.0+ (unchanged); packages build for macOS 15 (tests). The
transport model, play order, position math and tap gate build on Linux; the graph needs AVFAudio.

**Project Type**: Mobile app plus Swift packages.

**Performance Goals**: a seek is handled synchronously on the main actor in well under one frame
of UI time (research AUD-006-D3 measured 100 seeks in 33 ms offline on the build Mac); at most 10
seeks per second while scrubbing. The tap callback gains two atomic stores and one atomic load.

**Constraints**: no allocation, lock, I/O or logging added to any audio callback (Constitution
VII); public APIs only; offline; no networking; no persistence.

**Scale/Scope**: about 900 lines of production Swift and 1,400 lines of tests across three
packages and the app.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design: pass.*

| Principle | Status | How |
|---|---|---|
| I. Public Apple APIs only | Pass | AVFAudio scheduling and timing APIs, `Atomic`. No entitlement, permission or background mode. |
| II, III. Capture | N/A | In-App Playback of owned files only. System/App Capture and Microphone are untouched and have no transport (AUD-006-R1). |
| IV. Truthful source labeling | Pass | Every track stays "In-App Playback". A user pause or stop goes through the classifier's `suspended` event, so the state is "Paused" and "Active audio" returns only after new non-silent audio is verified (AUD-006-R20). The transport's own state is derived from the manager's state, not stored beside it. |
| V. No universal-capture claims | Pass | No claim added. Real-time and device behavior is tagged `{device}` and left open. |
| VI. Modular boundaries | Pass | `AudioSource` is unchanged. The discard operation is on `PCMSink`, which sources already hold. The transport talks to `InAppPlaybackSource` and `CaptureManager`; the renderer only sees the normalized reader. `PlayOrder` isolates the future queue. |
| VII. Real-time audio safety | Pass | The tap closure adds two atomic stores and one load (`PlaybackTapGate`), no allocation or lock. Discarding, tap replacement, file scheduling and position reads run on the main actor or the analysis queue. The wait for an in-flight tap write is bounded (1 s cap, normally microseconds). Stop stays idempotent; late completion callbacks are ignored by generation. |
| VIII. Upstream ProjectM fidelity | N/A | No engine or analysis change; projectM still receives normalized PCM through its documented API. |
| IX. Pinned dependencies and license review | Pass | No dependency. No media committed; fixtures are synthesized. |
| X. Evidence-based quality | Pass | Deterministic unit and offline-render tests on host and simulator; realtime UI tests on the simulator; device checks tagged `{device}`. |
| Security: untrusted imports | Pass | A track reached by Next or by the end of a track goes through the same `load` checks as a first start (AUD-002-R12, R16). |
| Privacy | Pass | Nothing persisted, nothing recorded, no network, no diagnostics field added. |

## Project Structure

### Documentation (this feature)

```text
specs/007-aud-006-seekable-transport/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/
│   ├── transport.md      # PlaybackTransport, PlayOrder, backend additions, discard contract
│   └── ui-strings.md     # transport strings
├── checklists/requirements.md
└── tasks.md              # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/
├── PCMSink.swift                 # + discardBufferedAudio(), setDiscardHandler(_:)
├── AudioAnalyzer.swift           # + discardBufferedAudio() on the analysis queue; registers the handler
├── Normalizer.swift              # + discardPending(): drop converter state, keep the format count
└── NormalizedPCMReader.swift     # + discardBuffered(): empty the ring, keep the counters
Packages/AudioCore/Tests/AudioCoreTests/DiscardTests.swift            # NEW

Packages/CaptureKit/Sources/CaptureKit/
├── CaptureManager.swift          # + pause() (user), isPausedByUser; resume() clears it; lifecycle respects it
└── InAppPlayback/
    ├── PlaybackTapGate.swift     # NEW: lock-free generation gate for the tap
    ├── PlaybackPosition.swift    # NEW: PlaybackPosition value, frame math (loop wrap, clamping)
    ├── PlayOrder.swift           # NEW: PlaybackItem, PlayOrder protocol, ListPlayOrder
    ├── PlaybackTransport.swift   # NEW: the transport model
    ├── ScrubThrottle.swift       # NEW: at most 10 seeks per second while dragging
    ├── InAppPlaybackGraph.swift  # segments, position, seek, pause/resume with held frame, replace, end/loop
    ├── InAppPlaybackSource.swift # + transport passthrough, session counter, track-end callback
    └── AVInAppPlaybackBackend.swift   # + seek, replace, position; compiles on macOS for offline tests
Packages/CaptureKit/Tests/CaptureKitTests/
├── AudioFixtures.swift           # + writeCounter (frame-index fixture) and its decoder
├── PlaybackTapGateTests.swift, PlaybackPositionTests.swift, PlayOrderTests.swift, ScrubThrottleTests.swift   # NEW (pure)
├── SeekableGraphTests.swift      # NEW: the graph offline: seek, pause, replace, end, loop, stale frames
├── TransportPipelineTests.swift  # NEW: backend + source + manager + analyzer + normalizer offline (acceptance)
├── PlaybackTransportTests.swift  # NEW: state machine, order rules, lifecycle, failure (fake backend)
├── CaptureManagerTests.swift     # + user pause and lifecycle
├── SourceAdapterTests.swift      # FakePlaybackBackend gains the new requirements
└── InAppPlaybackGraphTests.swift # reference content is now streamed (one test renamed, same assertions)

Packages/CaptureUI/Sources/CaptureUI/
├── TransportBar.swift            # NEW
├── UIStrings.swift               # + transport strings
└── Previews.swift                # + a TransportBar preview
Packages/CaptureUI/Tests/CaptureUITests/TransportStringsTests.swift, ViewRenderTests.swift

Apps/projectM-iOS/
├── Coordinators/AppCoordinator.swift          # owns the transport; play order; transport actions
├── Coordinators/AudioLibraryCoordinator.swift # playbackItems(): the list as PlaybackItems
├── Views/ControlsOverlay.swift                # shows TransportBar for In-App Playback
├── Tests/TransportCoordinatorTests.swift      # NEW
└── UITests/TransportUITests.swift             # NEW (simulator)
scripts/test_scripts.py                        # + contract check for this feature's strings
```

**Structure Decision**: extend `AudioCore`, `CaptureKit` and `CaptureUI`; no new package.
`project.yml` and the CI workflow are not touched (the app's sources are globbed by folder; the
packages' test lists are unchanged). `AppCoordinator.swift` gets one property and one small
section.

## Design

Details: [research.md](research.md), [data-model.md](data-model.md),
[contracts/transport.md](contracts/transport.md).

### 1. Discarding undelivered audio (AudioCore)

`PCMSink.discardBufferedAudio()` is a control-side call for the source that owns the producer. Its
contract: the caller guarantees no producer write is in flight or will start until the call
returns; when it returns, nothing written before the call can still reach a consumer. The sink
forwards to a handler that `AudioAnalyzer` registers at init; the analyzer runs it synchronously on
its queue: drain the sink ring, drop the Normalizer's converter state (its resampler holds a tail
of old audio), empty the normalized ring, and set the levels to silent. Because it runs on the
queue, a drain pass that had already read old samples has finished writing them to the normalized
ring before the ring is emptied. Without a handler (a sink used alone) the sink drains its ring.
Session statistics and the classifier are not touched: a seek is not a new session.

### 2. The tap gate and the hard cut (CaptureKit)

Audio is in transit in five places at a seek: (a) segments queued in the player, (b) rendered
audio accumulated inside the engine's tap (delivered in 100 ms blocks on a tap thread), (c) the
sink ring, (d) the converter, (e) the normalized ring. `InAppPlaybackGraph.restart(from:play:)`
cuts all five, in this order, on the main actor:

1. bump the schedule generation (late completion callbacks of old segments are ignored);
2. `player.stop()` (clears queued segments; the player's timeline restarts at the next `play`);
3. `gate.close()`: advance the gate generation, then wait until no tap write is in flight;
4. remove the mixer tap (drops the engine's partial block) and `sink.discardBufferedAudio()`;
5. install a new tap whose closure carries the new gate generation;
6. schedule the track from the new frame and, when playing, `player.play()`.

The tap closure is `gate.enter(token)` → write to the sink → `gate.leave()`. `enter` stores the
"writing" flag and then loads the generation; `close` stores the generation and then loads the
flag (both sequentially consistent), so either the closure sees the new generation and drops its
buffer, or `close` sees the flag and waits for the write to finish before the discard. A buffer
from a removed tap that arrives late is dropped by its stale token.

### 3. Position (CaptureKit)

While playing, position = `startFrame + player.playerTime(forNodeTime: player.lastRenderTime)`,
in the track's own sample rate, mapped by `PlaybackPositionMath` (clamped to the length, or
wrapped when the track loops). While paused the position is the held frame: pause reads the
position, stops the player and pauses the engine; resume starts the engine and performs the hard
cut from the held frame. Nothing depends on how the player's timeline behaves across an engine
pause. Reported tolerance: one render cycle (AUD-006-R9's 50 ms is the requirement; offline tests
assert exact frames).

### 4. End of track, loop and track change

- Order of one item: the graph loops as today (two passes queued ahead, `.dataConsumed` reschedules
  on the main actor), now starting from any frame; the position wraps.
- Otherwise: one segment to the end with a `.dataRendered` completion (the type that also fires in
  offline rendering; research AUD-006-D5) → main actor → `onTrackEnded` → the transport selects
  the next item and calls `replaceTrack`.
- `replace(content:)`: hard cut, except after a track that played to its end (its tail, up to
  one 100 ms tap block, is still on its way and belongs before the new track); if the format differs, reconnect player → mixer in the new
  format (the mixer's tap format does not change); then schedule from frame 0, or hold frame 0
  when paused. A track that fails `load` makes the transport report `.failed(.inAppPlaybackFailed)`
  through the source's event stream; the manager stops the session (AUD-006-R19).
- The reference track is opened as a streamed file like library tracks (one content kind; seek
  needs segments). Its endless gapless loop is unchanged.

### 5. User pause in CaptureManager

`pause()` (In-App Playback only): `source.suspend()`, classifier event `suspended`, and
`isPausedByUser = true`. `handle(.foreground/.unlock)` resumes only when `!isPausedByUser`.
`resume()` clears the flag. A stop, a failure and a new attempt clear it. Interruption and
route-loss handling are unchanged; their guards already ignore a paused session.

### 6. PlaybackTransport and PlayOrder

`PlaybackTransport(manager:source:)` is `@MainActor @Observable`. Its `state` is derived:
unavailable → stopped; user-stopped in this session → stopped; `manager.state.isRunning` →
playing; else paused. Commands: `play`, `pause`, `stop`, `togglePlayPause`, `seek(to:)`, `next`,
`previous`, plus `prepare(order:current:)` before a session starts. `PlayOrder` answers
`item(after:)` and `item(before:)`; `ListPlayOrder` wraps around. The source loops the current
track exactly when the order's next item is the current item.

### 7. UI

`TransportBar` (CaptureUI) takes values and closures: title, state, a position provider polled by
a `TimelineView` every 0.25 s while visible, and actions. The scrubber is a `Slider` over
0…duration with an explicit adjustable action (±10 s) and a spoken value. `ControlsOverlay` shows
it above the existing rows when `transport.isAvailable`. Coordinator actions call `showControls()`
so the hide delay restarts. Dragging uses `ScrubThrottle` (100 ms) and a final exact seek.

## Testing strategy (deterministic)

- **Fixture**: `AudioFixtures.writeCounter` writes a Float32 CAF in which frame `n` holds
  `(n+1) / 4096` split across the two channels as exact binary fractions, so every delivered frame
  decodes to its frame index and silence decodes to 0. Unity-gain mixing at the file's rate
  preserves the values bit for bit (research AUD-006-D2).
- **Graph, offline** (`SeekableGraphTests`): seek while playing, paused and stopped; to 0, middle,
  end, beyond; 100 rapid seeks; seek right after a track change; pause/resume stability; loop wrap;
  end of track callback; replace with another rate and channel count; stop during all of these.
  Assertions: first non-silent frame after the cut equals the target frame; every later frame is
  its predecessor + 1 (or wraps at the loop point); position equals target + frames rendered.
  A control test without the cut (old tap kept) is not shipped; the red run before the
  implementation is the evidence that the test detects stale frames.
- **Pipeline, offline** (`TransportPipelineTests`): `AVInAppPlaybackBackend` in offline mode →
  `InAppPlaybackSource` → `CaptureManager` (analysis stepped by the test) → `normalizedOutput`.
  The frames read from the normalized reader after `transport.seek` decode to the new position
  onward only; levels are silent right after the discard; the state stays truthful through
  pause/play/stop.
- **Transport** (`PlaybackTransportTests`, fake backend, runs on Linux): state derivation, the
  order rules at both ends, the 3-second rule, end-of-track advance, single-item loop flag,
  no-op commands, failure on a missing next track, user pause across lifecycle events and
  interruptions, transport ignored for other sources.
- **Pure units**: gate (including a concurrent stress test), position math, play order, throttle.
- **UI**: `TransportStringsTests`, `ViewRenderTests` (renders at accessibility sizes); app
  `TransportCoordinatorTests`; `TransportUITests` on the simulator in real time: transport shown
  for a library track and the reference track, hidden for Microphone; pause shows "Paused" and
  holds the time; scrubber adjust changes the time; next/previous change the title; stop returns
  to 0:00.
- **Regression**: all existing suites of `AudioCore`, `CaptureKit`, `CaptureUI`, `Diagnostics`,
  `Rendering`, `ANGLERendering` (dependents of `AudioCore`) and the app.
- **Red run recorded** before the production change (tasks.md).
- **Not covered before the device phase**: the audio session, routes, interruptions, and
  real-time timing of the cut on hardware (`{device}` tasks).

## Local persistence and rollback

- Nothing is written: no defaults key, no file, no schema. A relaunch starts with no transport
  state; `index.json` is untouched.
- Rollback is a code revert with no data step. Within a session, a failed track change ends the
  session through the existing failure path; the library is not modified.

## Complexity Tracking

No constitution violation. Two recorded changes to earlier behavior:

| Change | Why | Simpler alternative rejected because |
|---|---|---|
| The reference track is streamed from its file instead of being read into memory (AUD-001-D7) | Seeking needs file segments; one content kind keeps one code path | Slicing an in-memory buffer per seek needs a copy or a second scheduling path |
| With more than one library track, the end of a track now advances to the next instead of repeating (AUD-006-R17) | Roadmap row: next/previous and a transport; AUD-004 will add the choice | Keeping "repeat one" as the only behavior would make Next the only way to hear another track |
