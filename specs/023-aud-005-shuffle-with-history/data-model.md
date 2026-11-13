# Data Model: AUD-005 Shuffle with history

## ShuffleState (CaptureKit, value type, identifiers only)

| Field | Type | Rule |
|---|---|---|
| `seed` | UInt64 | Drawn when Shuffle is turned on; stored |
| `cycle` | Int ≥ 0 | 0 for the first cycle; +1 at every new cycle; stored |
| `order` | [ID] | A permutation of the queue's ids; stored |
| `played` | Int, 0...order.count | `order[0..<played]` played this cycle, in play order; stored |
| `history` | [ID], ≤ 100 | Tracks played while shuffled; not stored (rebuilt as `order[0..<played]`) |
| `cursor` | Int | Index of the current track in `history` (−1 when empty) |

Invariants: `Set(order) == Set(queue.ids)`; no duplicates; `played ≤ order.count`; history entries are
queued tracks, except the current one while detached.

### Operations

| Operation | Effect |
|---|---|
| enable(seed, ids, current) | `order = shuffle(ids, cycleSeed(seed, 0))`; if current is queued: move it to 0, `played = 1`, `history = [current]` |
| upcoming (Next target) | `history[cursor+1]` if any; else `order[played]` if `played < count`; else the first of the next cycle |
| previous target | `history[cursor-1]` if `cursor > 0`; else the current track (restart) |
| endOfTrack | One Track (current queued): play current. Forward history: play it. `played < count`: play `order[played]`. Cycle complete: All → play first of next cycle; Off → stop, cue it |
| didMove(id, .previous) | `cursor -= 1` when `history[cursor-1] == id` |
| didMove(id, .next/.endOfTrack) | `cursor += 1` when `history[cursor+1] == id`; else mark played and append |
| didMove(id, .start) | mark played and append (truncating forward entries) |
| mark played(id) | if the cycle is complete, begin the next cycle first; move `id` to index `played`; `played += 1` |
| next cycle | `order = shuffle(queue ids, cycleSeed(seed, cycle+1))`, swap first/last if first == last played; `cycle += 1; played = 0` |
| insertNext(id) | move/insert `id` at `played`; drop forward history |
| append(id) (new to the queue) | insert at the end |
| imported(id) | insert at `played + h % (count - played + 1)` |
| remove(id) | remove from `order` (`played -= 1` when its index < `played`); remove from history except the current entry |
| clear | `order = []`, `played = 0`, history keeps only the current entry |
| repair(ids) | drop unknown, append missing in queue order, clamp `played` |

## Queue record (`queue.json`, version 1) — additive keys

| Key | JSON | Written when |
|---|---|---|
| `shuffle` | `true` | Shuffle on |
| `shuffleSeed` | string, 16 lowercase hex digits | Shuffle on |
| `shuffleCycle` | integer ≥ 0 | Shuffle on |
| `shuffleOrder` | [string] canonical UUIDs | Shuffle on |
| `shufflePlayed` | integer ≥ 0 | Shuffle on |

Decoding: any key missing or the wrong type, or a seed that is not 1-16 hex digits, reads as Shuffle
Off when `shuffle` or the seed is unusable; a bad cycle reads 0, a bad played count 0, bad order
entries are dropped; `PlayQueue` then repairs the order against the queue.

Golden (Shuffle on, sorted keys):

```json
{"currentTrackID":"00000000-0000-0000-0000-000000000002","schemaVersion":1,"shuffle":true,"shuffleCycle":0,"shuffleOrder":["00000000-0000-0000-0000-000000000002","00000000-0000-0000-0000-000000000001"],"shufflePlayed":1,"shuffleSeed":"000000000000002a","trackIDs":["00000000-0000-0000-0000-000000000001","00000000-0000-0000-0000-000000000002"]}
```
