# Research: AUD-003 Audio library queue

All decisions 2026-11-12, by Claude under the owner's standing approval (CLAUDE.md owner rule 4).

## AUD-003-D1 Queue versus library

- **Decision**: a separate queue that starts as the library list order and diverges once edited
  (spec Clarifications).
- **Rationale**: keeps AUD-006 behavior for users who never edit; removing from the queue never
  deletes a file.
- **Alternatives**: reorderable library list (conflates order and ownership); empty default queue
  (silently changes current behavior).

## AUD-003-D2 Storage: separate `queue.json`, not an index v2

- **Decision**: `queue.json` beside `index.json`, version 1, `Data.write(options: .atomic)`.
- **Rationale**: additive; the library index (AUD-001-R12 to R15) keeps its format, its recovery
  and its newer-version guard; a damaged queue never triggers library recovery. The roadmap's
  migration policy ("pure, versioned, tested migrations; keep a backup until successful atomic
  replacement") is met without any migration: version 1 is new, the damaged file is kept aside.
- **Alternatives**: extend `index.json` to v2 (forces a migration and makes an older app treat the
  library as "newer format" and unusable: a rollback would hide the whole library).

## AUD-003-D3 Removing the playing track

- **Decision**: it plays to its end; the queue remembers its former index ("detached" current
  track); after it comes the entry now at that index (wrapping), before it the entry at index − 1.
  Empty queue: nothing follows; the transport's existing rule stops at the end (AUD-006-R17).
- **Alternatives**: skip at once (interrupts), stop at once (interrupts).

## AUD-003-D4 Loop changes while playing

- **Problem**: `InAppPlaybackGraph` decides looping when it schedules (`loops` takes effect at the
  next cut). A lone track keeps two passes queued; adding a second track would otherwise leave it
  looping until a cut, and a non-looping track left alone would end and restart with a cut.
- **Decision**: `updateLooping(_:)` on the graph: when the schedule's looping differs and the graph
  is playing, read the position, bump the schedule generation (old completions ignored), stop the
  player and schedule from that frame with the new mode, then play. This is not a cut: the tap and
  the tap gate stay, nothing downstream is discarded, the counter stream stays consecutive (tested
  in offline rendering). While held (paused, interrupted) only the flag changes; the next resume
  cuts in with it. The fallback position (frames delivered by the tap since the last cut, AUD-014-R10)
  subtracts the frames rendered before the re-queue, so it stays at most one tap block behind.
- **Real time**: the re-queue runs on the main actor with the same player calls as a seek; the tap
  closure is unchanged.
- **Residual**: with a live engine the render thread can render one more quantum between the
  position read and `stop()`; at most one render quantum (about 10 ms) may repeat. Not observable in
  offline tests; device listening check is `{device}` (AUD-003-T22).
- **Alternatives**: wait for the queued pass to end (the track plays one full extra time);
  schedule-time-only (track loops forever).

## AUD-003-D5 Observing queue edits

- **Decision**: `MutablePlayOrder: PlayOrder` with `onOrderChange` and `playbackDidMove(to:)`.
  `PlaybackTransport.prepare` hooks the closure (and unhooks the previous order's);
  `change(to:)` and `prepare` report the current item. The transport's `orderDidChange()`
  recomputes looping and applies it live.
- **Alternatives**: app-layer calls after each edit (forgettable, untestable in the package).

## AUD-003-D6 Interruption interplay

- **Decision**: queue edits do not call `CaptureManager.noteUserTransportChange()` (AUD-003-R12).
  During an interruption the graph is held, so `updateLooping` only stores the flag.

## AUD-003-D7 New imports and "Play Queue"

- **Decision**: imported tracks are inserted at the top of the queue in the order the list shows
  them (last imported first). "Play Queue" starts the stored current track at 0:00, or the first.
- Tapping a library row plays that track; when it is not queued it is appended first.

## AUD-003-D8 Design room for AUD-004 and AUD-005

- Repeat modes become a property consulted by `PlayQueue.item(after:)` (nil for "off" at the end);
  shuffle becomes a derived permutation plus a history stack over the same stored order. Neither
  changes `queue.json` version 1 (a later version may add fields; decoding ignores unknown keys).
