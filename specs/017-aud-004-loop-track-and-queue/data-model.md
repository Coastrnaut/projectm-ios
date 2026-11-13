# Data Model: AUD-004 Loop track and queue

## RepeatMode

| Case | Raw value (stored) | Shown as | Meaning |
|---|---|---|---|
| `off` | `"off"` | Off | Next queued track at a track's end; stop and cue the first after the last (AUD-004-R5) |
| `one` | `"one"` | One Track | The queued current track repeats without a gap (R4) |
| `all` | `"all"` (never written) | All Tracks | Next queued track, wrapping; default (R2, R3) |

`next`: off → all → one → off (R12).

## EndOfTrackStep

| Case | Transport does |
|---|---|
| `.play(item)` | `item.id == current.id`: the backend loops the track gaplessly (never reports an end). Otherwise the next track follows without a cut at the end. |
| `.stop(cue: item?)` | At the end: pause as Stop playback (state Stopped); with a cue, select it at 0:00 while stopped. Play at the very end with a cue: select it and play. |

## PlayQueue.endOfTrack(after: id) by mode

Let `Q` be the queued items (count `n`), `i` the index of `id` in `Q`, `d` the detached index (the
current track removed from the queue while current).

| Situation | All | One | Off |
|---|---|---|---|
| `n == 0` | stop(nil) | stop(nil) | stop(nil) |
| `id` queued, `i < n-1` | play(Q[i+1]) | play(Q[i]) | play(Q[i+1]) |
| `id` queued, `i == n-1` | play(Q[0]) | play(Q[i]) | stop(cue: Q[0]) |
| `id` detached, `d < n` | play(Q[d]) | play(Q[d]) | play(Q[d]) |
| `id` detached, `d >= n` | play(Q[d % n]) | play(Q[d % n]) | stop(cue: Q[0]) |
| `id` unknown | play(Q[0]) | play(Q[0]) | play(Q[0]) |

`item(after:)` and `item(before:)` are unchanged (wrap in every mode).

## PlayQueueRecord (`queue.json`, schema version 1, extended)

```json
{"currentTrackID": "UUID", "repeatMode": "one", "schemaVersion": 1, "trackIDs": ["UUID", "UUID"]}
```

| Field | Type | Rule |
|---|---|---|
| `repeatMode` | String, optional | `"off"` or `"one"`; omitted for All Tracks. On decode: absent, not a string, or unknown ⇒ All Tracks |

All other fields and load outcomes as AUD-003 (`specs/015-aud-003-audio-library-queue/data-model.md`).
Encoding: sorted keys; an All Tracks record is byte-identical to AUD-003's.

## State transitions at the end of the last track, Off

`playing(last, at end)` → `stopped(first, 0:00)` → Play → `playing(first, 0:00…)`.
With one queued track: `playing(A, end)` → `stopped(A, 0:00)`.
