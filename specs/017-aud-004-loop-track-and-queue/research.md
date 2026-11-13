# Research: AUD-004 Loop track and queue

Audit of the code on `feature/aud-004` (base `1911b6d`, 2026-11-13). No external research was needed:
every decision uses APIs and seams already in the repository.

## AUD-004-D1 Where the mode lives and how the transport asks

- **Decision**: The mode is a property of `PlayQueue`. `PlayOrder` gets one more requirement,
  `endOfTrack(after:) -> EndOfTrackStep`, with a protocol-extension default built from
  `item(after:)`. The transport uses it for (a) the end of a track, (b) whether the current track
  repeats (`.play` of the same id ⇒ the backend loops gaplessly), and (c) Play at the end of a track.
  Next and Previous keep calling `item(after:)`/`item(before:)`.
- **Rationale**: AUD-003-D8 planned "a property consulted by `PlayQueue`". Splitting "what follows at
  the end" from "what Next selects" is what One Track needs (repeat at the end, move on Next) and
  what Off needs (stop at the end, Next still wraps). The default keeps every other order unchanged.
- **Alternatives**: answering nil from `item(after:)` for Off at the end (AUD-003-D8's sketch): Next
  on the last track would do nothing, and `play()` at the end would do nothing. A mode on the
  transport: the reference track and test signals would need exceptions, and the mode would not be
  stored with the queue.

## AUD-004-D2 Storage

- **Decision**: optional `"repeatMode"` in `queue.json` version 1, written only for `off` and `one`.
  Decoding is lenient (`Lossy<String>`): absent, wrong type or unknown value ⇒ All Tracks.
- **Rationale**: AUD-003-D8 ("a later version may add fields; decoding ignores unknown keys") and
  AUD-003's own test `testUnknownKeysAreIgnored`, which already decodes a v1 record with
  `"repeatMode":"all"`. A record in the default mode is byte-identical to AUD-003's, so the AUD-003
  golden encoding test still holds. Rollback keeps the queue (plan, Rollback).
- **"Migration"**: the v1-without-mode record is the old format; reading it as All Tracks is the
  migration, a pure function tested with AUD-003's exact bytes as the golden input.
- **Alternatives**: version 2 (an AUD-003 app reads it as "newer format", stops storing edits for that
  launch, and the queue falls back to the library order); a separate `repeat.json` (two files that
  can disagree, two atomic writes per change).

## AUD-004-D3 Off at the end of the queue

- **Decision**: `.stop(cue: first queued item)`. The transport pauses as Stop playback
  (`manager.pause(asStop: true)`, state Stopped), then selects the cue: `replaceTrack` on a paused
  source holds it at frame 0 (AUD-006-R18; the graph's `replace` keeps a held position and cuts) or,
  for the same track, a seek to 0 while held. The stopped session is recorded so `state` is Stopped.
  An empty queue answers `.stop(cue: nil)`: stop at the end of the track, as today.
- **Ordering**: the pause comes first, so no audio of the cued track is rendered between the end and
  the stop. Between the end of the last track and the pause the player has nothing scheduled
  (silence), which is what the offline test asserts as "nothing after the last frame".
- **The tail (found by AUD-004-T05's first green attempt, 2026-11-13)**: stopping at once lost the
  last 2,200-2,700 frames of C: the tap hands audio over in ~100 ms blocks, so when the transport
  paused right after the player's end callback, the last partial block never reached the sink, and
  the cue's cut then discarded what had. Fix, kept off the real-time path: the graph records the tap's
  delivered-frame counter when the track is rendered to its end and reports `hasDeliveredTrackEnd`
  once one more tap block (100 ms, silence) has been delivered; the transport waits for it (main
  actor, 5 ms polls, at most 2 s, abandoned when the user acts meanwhile) before pausing. While held
  after a track played to its end, a cue (`replace` or a seek) needs no cut: only that track's tail
  can still arrive; the resume cuts as before. Mutation check: with `hasDeliveredTrackEnd` forced to
  true, the three Off pipeline tests fail again.
- **Play at the very end** (paused at the end of the last track by a seek, Off): `play()` already
  detects "at the end of a non-looping track"; with `.stop(cue: item)` it now changes to the cue and
  resumes, so the queue starts again (AUD-004-R6). With `.stop(cue: nil)` it stays as today.

## AUD-004-D4 One Track and the detached current track

- **Decision**: in One Track, `endOfTrack(after: id)` is `.play(self)` when `id` is queued. A
  detached current track (removed while playing) is not repeated: its step is the entry at its
  former index, wrapping, as AUD-003-R9; that entry then repeats because it is queued. In Off, a
  detached track's former index at or past the end is the end of the queue.

## AUD-004-D5 Applying a mode change while playing

- **Decision**: `setRepeatMode` stores the record and calls `onOrderChange`, like any queue edit. The
  transport's `orderDidChange()` recomputes "loops" from `endOfTrack(after: current)` and calls
  `source.updateLooping`, which re-queues the playing segment from the reached frame without a cut
  (AUD-003-R8; `InAppPlaybackGraph.updateLooping`). It is not a transport command and does not call
  `noteUserTransportChange` (AUD-004-R9). While paused or interrupted only the flag changes.
- **Evidence it is frame-exact offline**: AUD-003's `QueuePipelineTests` already prove a loop ↔
  no-loop switch delivers consecutive frames; AUD-004 adds the One ↔ All and All → Off cases.

## AUD-004-D6 Deterministic tests

- Offline manual rendering (`AVInAppPlaybackBackend(offlineSampleRate: 44_100)`), `ManualClock` for
  the manager, `stepAnalysisForTesting()`; counter tracks whose samples encode `offset + frame`, so
  the stream reaching the renderer's reader shows which track and frame played. The graph's end
  callback hops to the main actor; the pump yields between renders. Assertions are on frame
  sequences and transport state, never on elapsed wall time; any wait for a state is a condition
  polled under a 30 s ceiling.
- Repeatability: one scenario is run twice in the same test and the two frame sequences compared.
