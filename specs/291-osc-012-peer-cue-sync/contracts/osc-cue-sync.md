# Contract: OSC-012 Peer Cue Sync

## C1 Wire message

`/projectm/cue ,siii <cueID> <seq> <offsetMs> <session>` as one plain OSC message (no bundle) per UDP datagram,
sent only by a leader through OSC-005's sender to its one destination. Example: cue `0C1D…`, seq 4, 12 340 ms,
session 917.

## C2 Leader schedule (`OSCCueSyncLeader`)

- `cueChanged(_ cueID: String?, startedAt: UInt64, now: UInt64)`: nil stops. Otherwise seq += 1, burst slots at
  now + 0, 100, 300 ms.
- `due(now:) -> OSCCueSyncMessage?`: at most one message per call; overdue slots collapse into that one.
- `nextDue: UInt64?`: earliest time a message is due.
- Bound: per cue change ≤ 3 burst sends; heartbeats ≥ 2 s apart. Leading becoming active = `cueChanged`.

## C3 Follower rule (`OSCCueSyncFollower.receive`)

1. Not approved (allow list off) → `.unapproved`.
2. Malformed → `.malformed` (state unchanged).
3. Same session and seq ≤ last → `.duplicate`.
4. Record (session, seq). Unknown cue → `.unknownCue` (reported once per (session, seq)).
5. Otherwise `.apply(cueID, alignedStart: max(now − offset, 0))`.

## C4 Receive path

`OSCDispatcher.setMessageTap(address:handler:)` (nil removes): messages with that address skip routes and go to
the handler under the dispatcher lock (outcome `.tapped`, counter `tapped`); called only after the allow list and
datagram limits. The handler must not call into the dispatcher.

## C5 Send path

`OSCSender.postCue(_:) -> OSCSendOutcome`: `.inactive` without destination, `.rateLimited` over the 60/s cap,
else `.sent`. Kind choices do not apply.

## C6 App (`OSCCueSyncCoordinator`, Settings › OSC › Cue Sync)

Picker "Cue sync" (`oscCueSyncRole`: Off/Lead/Follow), status line (`oscCueSyncStatus`), counts
(`oscCueSyncCounts`). Lead: active iff Lead, allow list on, Send OSC active (`activeDestination` non-nil) and the
show has an active cue. Follow: tap installed iff Follow; applies iff allow list on. Timed advance held while
following is active (Follow, receiver switch on, allow list on).
