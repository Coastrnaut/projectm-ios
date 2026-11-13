# Data model: AUD-003 Audio library queue

## PlayQueueRecord (`queue.json`, schema version 1)

```json
{"currentTrackID": "8F0B…-UUID", "schemaVersion": 1, "trackIDs": ["UUID", "UUID"]}
```

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | Int | 1. `< 1` or missing: damaged. `> 1`: newer format, nothing else read |
| `trackIDs` | [String] | queue order; each a UUID string; invalid and repeated entries dropped on decode |
| `currentTrackID` | String? | a UUID string or absent; an invalid value is dropped |

- Encoding: sorted keys, current version. Read limit 1 MB (larger: damaged).
- Only identifiers of AUD-001 `ImportedTrack.id`; no titles, paths, positions, audio.

## Load outcomes (`PlayQueueStore.load()`)

| File | Outcome | Effect |
|---|---|---|
| absent | `.missing` | queue = library order; stored at the first edit or move |
| valid v1 | `.record(r)` | queue = r, filtered to library tracks |
| unreadable | `.damaged` | file moved to `queue.damaged.json`; as `.missing` |
| version > 1 | `.newerFormat(v)` | file untouched; queue = library order; `isPersistent` false |

## PlayQueue (in memory, `@MainActor @Observable`)

| Member | Meaning |
|---|---|
| `ids: [String]` | the order (track UUID strings), each once |
| `items: [PlaybackItem]` | `ids` resolved against the library catalog (missing ones skipped) |
| `notQueued: [PlaybackItem]` | library tracks not in the queue, in library order |
| `currentID: String?` | last item playback moved to (stored) |
| `detachedIndex: Int?` | set when the current track was removed from the queue: its former index |
| `isPersistent: Bool` | false after a newer-format load |
| `onOrderChange` | set by the transport |

State rules:

- `setLibrary(items)` (library ready): catalog replaced; ids not in the library removed (the
  current one detaches); first call with no record seeds `ids` from the library order.
- `didImport(ids)`: unknown ids inserted at the top, last given first.
- `item(after: id)`: id queued → next, wrapping; id detached (= current, not queued) → entry at
  `detachedIndex % count`; other id → first; empty → nil. `item(before:)` symmetric with
  `detachedIndex − 1`.
- `playbackDidMove(to: id)`: `currentID = id`; clears `detachedIndex` when the id differs from the
  detached one or is queued again; stores.
- Every edit stores the record (when persistent) and calls `onOrderChange`.

## Transport additions

- `PlaybackTransport.orderDidChange()`: `loops = order.item(after: current) == current`; if it
  differs from the source's, `source.updateLooping(loops)`.
- `InAppPlaybackBackend.updateLooping(_:)`: default sets `loopsCurrentTrack`; AV backend forwards to
  `InAppPlaybackGraph.updateLooping(_:)` (re-queue at the reached frame, research AUD-003-D4).
