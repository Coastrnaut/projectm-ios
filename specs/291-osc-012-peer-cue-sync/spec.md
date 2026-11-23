# Feature Specification: OSC-012 Peer Cue Sync

**Feature Branch**: `feature/osc-012` (spec directory `291-osc-012-peer-cue-sync`)

**Created**: 2026-11-15

**Status**: Implemented (OSC-012-T22 {device} open)

**Input**: User description: "Implement roadmap row OSC-012 (Peer cue sync) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Synchronize cue ID and monotonic offset between user-approved local peers."
Acceptance, verbatim: "Packet loss fixture recovers next cue without infinite retransmission."
P3, effort XL, depends on OSC-011 and SHOW-001 (both integrated)."

Identifiers carry the roadmap ID: requirements `OSC-012-R1…`, success criteria `OSC-012-S1…`, research
decisions `OSC-012-D1…`, tasks `OSC-012-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008), ADR-0088 (the
reviewed OSC-005 sender, one literal local destination), ADR-0100 (OSC-011 discovery) and every OSC-001,
OSC-005, OSC-007, OSC-008, OSC-009 and SHOW-001 requirement stay in force. This row adds one outbound message
class, `/projectm/cue`; ADR-0102 records it.

## Baseline: what exists today (audit of 2026-11-15, commit `761e85e7`)

| Area | Today | Gap |
|---|---|---|
| Sender (OSC-005) | `OSCSender` over `NetworkOSCSender`: one UDP flow to one literal local destination, 60 messages/s cap (`OSCSendRateCap`), gated by Send OSC, the OSC receiver switch, the foreground and the allow list (`OSCSendCoordinator.activeDestination`) | **gap**: only `/projectm/scene`, `/projectm/beat`, `/projectm/status` may be sent |
| Receiver (OSC-001, OSC-009) | `OSCReceiver` → `OSCDispatcher`: allow list per datagram, datagram rate limits, bundles, then routes to parameters; any other address is ignored (`unknownAddress`) | **gap**: no way to hand a non-parameter message to a consumer |
| Allow list (OSC-008) | `OSCPeerAllowlist`, off by default, drops unapproved hosts before the dispatcher | none: reused for "approved peers" |
| Discovery (OSC-011) | Nearby Devices: Allow and Use as send destination | none: how users pick the peer |
| Bundles and time tags (OSC-006) | wall-clock NTP tags mapped to the receiver's monotonic clock | not used: needs agreeing wall clocks (research OSC-012-D2) |
| Cues (SHOW-001) | `ShowCue.id` (UUID, stable over moves and renames); `ShowCoordinator.go(to:)`, `stepNow(_:)`, `cueStarted` | none: cue IDs are the sync key |
| Timed advance (SHOW-002/007) | `ShowAutoAdvanceCoordinator.isHeld` | used to hold a follower's own timed advance |
| Performance lock (SHOW-015) | the scene lock; cue steps stay allowed while locked | none: following is a cue step |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How are the roles chosen? → A: One "Cue sync" choice in Settings › OSC › Cue Sync with three values: Off, Lead, Follow. Off by default and on a fresh install. One choice (not two switches) so a device can never lead and follow at once, which would let two devices echo cues at each other (OSC-012-R1).
- Q: Who does a leader send to? → A: OSC-005's one send destination, through the same reviewed sender (`OSCSender` over `NetworkOSCSender`), so the literal local destination, the 60/s cap and every OSC-005 gate apply unchanged. One follower per leader in this row; several followers would need a multi-destination sender and a new ADR (out of scope) (OSC-012-R3).
- Q: What does "user-approved" mean? → A: OSC-008's allow list. Both roles need "Only approved devices" on: a leader sends only to a destination on the approved list, and a follower applies messages only while the allow list is on, so only approved hosts can reach it (the receiver drops everyone else before the dispatcher). With the allow list off, both roles show "Turn on Only approved devices" and do nothing (OSC-012-R4, R6).
- Q: What is sent? → A: `/projectm/cue ,siii <cue ID> <seq> <offset ms> <session>`: the cue's ID (SHOW-001 UUID text), a sequence number that grows by one per cue change, the leader's monotonic milliseconds since the cue started, and a random per-launch session number so a restarted leader (seq back at 1) is not taken for an old one. Nothing else: no scene name, label, note, setting or device name (OSC-012-R2).
- Q: Offset or OSC-006 time tags? → A: Offset. Time tags need both devices' wall clocks to agree, which nothing guarantees on a local network without a time server; a monotonic offset needs no shared clock. The follower computes the cue's start on its own monotonic clock as "receipt time − offset". Precision is the one-way network delay plus the follower's hop to the main thread (typically under 50 ms on a quiet Wi-Fi); this is not a frame-accurate sync claim (OSC-012-R8; research OSC-012-D2).
- Q: How is packet loss handled without unbounded retransmission? → A: Per cue change the leader sends the message 3 times (at 0, 100 and 300 ms) and then a heartbeat with the current cue every 2 s while it leads and has an active cue. There is no acknowledgement and no per-message retry. A newer cue change cancels the rest of an older burst. Total sends per cue change are at most 3 plus one heartbeat per 2 s, and the OSC-005 60/s cap applies on top (OSC-012-R5).
- Q: What does a follower do with duplicates and reordering? → A: It keeps the newest (session, seq) it accepted. A message with the same session and a seq not greater than that is ignored; a different session starts over. Only the newest message is applied (OSC-012-R7).
- Q: A cue ID the follower's show does not have? → A: Reported in the Cue Sync status ("The leader's cue isn't in this show") and counted, never applied; the follower stays where it is. The (session, seq) is still recorded so the same unknown cue is not reported again on every heartbeat (OSC-012-R9).
- Q: How is a cue applied on the follower? → A: Through SHOW-001's step path (Go to cue) at once, with the cue's own transition, never through the beat quantizer (the leader already quantized). If the follower is already on that cue nothing is applied again (OSC-012-R8).
- Q: What about the follower's own timed advances? → A: While following is active, the follower's SHOW-002 timed advance is held, so its show does not run away from the leader. Manual steps on the follower stay possible (the operator's hands win) until the leader's next cue change (OSC-012-R10).
- Q: Safety and the performance lock? → A: Cue sync only moves the show position. It never changes a setting, edits or deletes a cue, scene or file, and never turns another switch on. Following is a cue step, which the scene/performance lock (SHOW-015) allows; blackout, the repair report and Reduce flashing apply exactly as for a manual step (OSC-012-R11).
- Q: What is stored? → A: One key, `settings.osc.cueSync.role` (absent → Off), this device's network setup: excluded from the FILE-005 backup, removed by the FILE-011 Settings erase and by the UI-test reset. Sequence, session and follower state are memory only (OSC-012-R12).

### Session 2026-11-15 (speckit-clarify)

- Q: When does a leader start a new burst besides a cue change? → A: Whenever leading becomes active with an active cue: choosing Lead, Send OSC becoming active (switch, receiver, foreground, approval), or returning to the foreground. Each start counts as a cue change (new seq, 3 sends), so a follower that missed everything while the leader was paused recovers at once (OSC-012-R5).
- Q: Does cue sync need one of Send OSC's message kinds (scene, beat, status)? → A: No. Cue messages are their own class, controlled by the role alone; Send OSC's switch and destination are still needed. The kind choices and Include scene names do not affect them (OSC-012-R3).
- Q: Which `/projectm/cue` messages are malformed? → A: Anything but exactly the types `s i i i`; a cue ID that is empty or over 64 UTF-8 bytes; a negative seq or offset. Malformed messages are ignored and counted, and never change the last accepted seq (OSC-012-R7).
- Q: Is anything spoken to VoiceOver for sync? → A: No new announcements. A follower's step announces through SHOW-001's cue lane exactly like a manual step; the Cue Sync status line ("Following cue 3", "Waiting for the leader", "The leader's cue isn't in this show") is an ordinary label (OSC-012-R14).
- Q: How does a follower show the synchronized offset? → A: The status line shows the cue and how long ago it started on the leader, rounded to the second ("Following cue 3 · started 12 s ago"), computed from the aligned start on the follower's own clock (OSC-012-R8, R14).

### Session 2026-11-23 (QA-011 device run)

- Q: What latency bound does the two-device check (OSC-012-T22) apply to "B steps to cue 3 within a fraction of a second"? → A: At most 1 s from the leader's step to the follower's change, measured as an upper bound: the leader stamps its step before XCUITest's tap, so each reading includes the tap's own time (about 0.35-0.45 s), and the two device clocks are not corrected (±0.25 s window). Every step but one must be matched. Evidence: D2 (follow) and D3 (lead), 2026-11-23, 26 of 26 steps matched, median 0.449 s, max 0.532 s; the earlier 0.5 s bound failed only on that tap time. The 10 s Wi-Fi outage part stays not required (owner ruling 2026-11-18).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A follower iPad stays on the leader's cue (Priority: P3)

Two iPads run the same show (copied as a scene pack or backup, so the cue IDs match). Each has the OSC receiver
and "Only approved devices" on, with the other approved. On iPad A the performer sets Send OSC's destination to
iPad B and chooses Cue sync "Lead"; on iPad B they choose "Follow". When the performer steps A to cue 3, B
steps to cue 3 within a fraction of a second.

**Why this priority**: it is the roadmap row (P3).

**Independent Test**: a leader model and a follower model connected through a fake network: a cue change on the
leader is applied on the follower; with real UDP on 127.0.0.1 the same holds through two coordinators.

**Acceptance Scenarios**:

1. **Given** a leader and an approved follower with the same show, **When** the leader goes to a cue, **Then** the follower's show goes to that cue.
2. **Given** a follower that joins late (turns Follow on after the cue started), **When** the next heartbeat arrives, **Then** it goes to the leader's cue and its start time is the leader's elapsed time back from now.

### User Story 2 - Packet loss recovers without infinite retransmission (Priority: P3)

**Acceptance Scenarios**:

1. **Given** 50% random loss, a burst loss of the first 3 packets, or total loss for 5 s, **When** the leader changes cue, **Then** the follower reaches the leader's latest cue within the burst or by the next heartbeat after the loss ends.
2. **Given** any cue change, **Then** the leader sends at most 3 messages for it plus one heartbeat per 2 s; over 60 s without cue changes it sends at most 31 heartbeats.

### User Story 3 - Only approved, newest, known cues are applied (Priority: P3)

**Acceptance Scenarios**:

1. **Given** duplicates or out-of-order messages, **Then** only the newest seq is applied, once.
2. **Given** a cue ID the follower's show does not have, **Then** it is reported and nothing moves.
3. **Given** a message from a host that is not approved, or the allow list off, **Then** it is ignored.

### User Story 4 - Off by default (Priority: P3)

**Acceptance Scenarios**:

1. **Given** a fresh install, **Then** Cue sync is Off, nothing is sent for cues and `/projectm/cue` messages are ignored as unknown addresses.

### Edge Cases

- The leader is at Standby (no active cue): nothing is sent until a cue is active.
- The leader's Send OSC is off, the destination is not approved, or the app is in the background: the role stays chosen, nothing is sent (OSC-005 gates), and the status says why.
- The follower's OSC receiver is off or in the background: nothing arrives; following resumes with the next heartbeat.
- A restarted leader (new session, seq 1): accepted as a new session.
- A malformed `/projectm/cue` (wrong types, empty or over-long cue ID, negative offset): ignored and counted.
- The follower's cue's scene is missing or needs repair: SHOW-001/SCN-012 behaviour (notice or repair report), as for a manual step.
- Rapid cue changes on the leader: each change gets its own burst; older bursts are cancelled; the 60/s cap bounds the total.

## Requirements *(mandatory)*

- **OSC-012-R1**: Settings › OSC MUST offer Cue Sync with one role choice: Off, Lead, Follow; Off by default and on a fresh install.
- **OSC-012-R2**: A leader MUST send only `/projectm/cue` with exactly the cue ID string (≤ 64 bytes), seq (int32), offset in milliseconds (int32, ≥ 0) and session (int32).
- **OSC-012-R3**: A leader MUST send through OSC-005's sender to its one destination, under every OSC-005 gate and its 60/s cap; it MUST NOT open any other flow.
- **OSC-012-R4**: A leader MUST send only while the allow list is on and the destination is approved.
- **OSC-012-R5**: Per cue change a leader MUST send at most 3 messages (0, 100, 300 ms), then at most one heartbeat per 2 s while leading with an active cue; no acknowledgements or other retries. Leading becoming active with an active cue counts as a cue change.
- **OSC-012-R6**: A follower MUST act on `/projectm/cue` only while Follow is chosen and the allow list is on (so only approved hosts reach it); otherwise the message is ignored.
- **OSC-012-R7**: A follower MUST apply only a message newer than the last accepted (same session and greater seq, or a different session); older and duplicate messages are ignored. Malformed messages (types other than `s i i i`, a cue ID empty or over 64 bytes, a negative seq or offset) are ignored and counted.
- **OSC-012-R8**: A follower MUST go to the received cue at once through SHOW-001's step path (not quantized), unless already on it, and MUST record the cue's start as its own monotonic receipt time minus the offset.
- **OSC-012-R9**: A cue ID that the follower's show does not have MUST be reported and counted, never applied.
- **OSC-012-R10**: While following is active (Follow chosen, the OSC receiver switch on and the allow list on) the follower's timed advance MUST be held.
- **OSC-012-R11**: Cue sync MUST NOT change settings, edit or delete show material or files, or turn any switch on; the scene/performance lock MUST NOT block following.
- **OSC-012-R12**: The role MUST be stored on this device only (excluded from backup, removed by the Settings erase and the UI-test reset); all other sync state MUST stay in memory.
- **OSC-012-R13**: Traffic MUST NOT schedule main-thread work per message (OSC-009-R11): received cue messages are coalesced into a bounded inbox with at most one pending hop.
- **OSC-012-R14**: Cue Sync MUST show a status line for the role (why it is not active, "Sending cue 3", "Following cue 3 · started 12 s ago", "Waiting for the leader", "The leader's cue isn't in this show") and add no VoiceOver announcements of its own.

### Key Entities

- **Cue sync role**: Off, Lead, Follow (device only).
- **Cue sync message**: cue ID, seq, offset ms, session.
- **Leader state**: session, seq, current cue and its start time, the burst schedule, the next heartbeat (memory).
- **Follower state**: last accepted (session, seq), the leader's cue, its aligned start, counts of applied, ignored and unknown messages (memory).

## Success Criteria *(mandatory)*

- **OSC-012-S1**: Under 50% random loss, a 3-packet burst loss, and a 5 s outage, the follower reaches the leader's latest cue in 100% of fixture runs, at the latest by the first heartbeat after the loss ends.
- **OSC-012-S2**: The leader never sends more than 3 messages per cue change plus one heartbeat per 2 s (≤ 31 over a 60 s run with no change).
- **OSC-012-S3**: 0 duplicate, stale, unknown-cue or unapproved messages move the follower's show.
- **OSC-012-S4**: On a fresh install 0 cue messages are sent or applied.
- **OSC-012-S5**: Over real UDP on 127.0.0.1, a leader's cue change reaches a follower coordinator within 5 s (a generous ceiling).

## Assumptions

- Both devices hold the same show (same cue IDs), copied by scene pack, backup or folder backup. Matching shows by content is out of scope.
- One follower per leader (OSC-005 has one destination).
- Local Wi-Fi delay is small next to a cue; no clock offset estimation is attempted.
- The end-to-end check on two physical devices (OSC-012-T22) is `{device}`.
