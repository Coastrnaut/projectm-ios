# Data Model: OSC-012 Peer Cue Sync

## OSCCueSyncRole (stored)

`off` | `lead` | `follow`. Key `settings.osc.cueSync.role` (String; absent or unknown → `off`). Device only:
FILE-005 excluded, FILE-011 erase, UI-test reset.

## OSCCueSyncMessage (wire, memory)

| Field | OSC type | Rule |
|---|---|---|
| cueID | `s` | 1…64 UTF-8 bytes (SHOW-001 UUID text, uppercase) |
| seq | `i` | ≥ 1, +1 per cue change |
| offsetMilliseconds | `i` | ≥ 0, clamped to Int32.max |
| session | `i` | random per leader launch, non-zero |

Address `/projectm/cue`. Anything else is malformed.

## OSCCueSyncLeader (memory)

session, seq, cue (ID, startedAt ns), burstStart, burstIndex (0…3), lastSend, sendsForCurrentCue, totalSends.
Transitions: `cueChanged(id, startedAt, now)` → seq+1, burst from now; `due(now)` → message or nil;
`stop()` → no cue, nothing due. `nextDue` = next burst slot, else lastSend + 2 s.

## OSCCueSyncFollower (memory)

lastAccepted (session, seq)?, leaderCueID?, alignedStart ns?, counters (applied, duplicates, unknown,
unapproved, malformed), lastUnknownCueID?. `receive(message, approved, now, hasCue)` →
`.apply(cueID, alignedStart)` | `.duplicate` | `.unknownCue(id)` | `.unapproved` | `.malformed`. `reset()` on
role change.

## OSCCueSyncInbox (memory, Sendable)

Up to 8 (message, receipt ns) pairs, oldest dropped; `offer` returns true when the caller must schedule the one
hop; `take` empties it and clears the pending flag.
