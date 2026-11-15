# Research: OSC-012 Peer Cue Sync

## OSC-012-D1: Transport for the leader

- **Decision**: Reuse OSC-005's `OSCSender` and its one destination (`postCue`, outside the kind filter, inside the 60/s cap).
- **Rationale**: ADR-0088's reviewed flow already enforces the literal local address, cellular off, every gate and the cap; adding a second flow would need new scan rules and review.
- **Alternatives**: a second sender per follower (multi-destination, amends ADR-0088 decision 1; rejected for this row); broadcast or multicast (refused by `OSCSendDestination.isSendable`, and would reach unapproved hosts).

## OSC-012-D2: Offset versus OSC-006 time tags

- **Decision**: A monotonic offset in milliseconds since the cue started on the leader; the follower aligns with "receipt time − offset" on its own monotonic clock.
- **Rationale**: Time tags are NTP wall-clock times; two iPads' wall clocks may differ by hundreds of ms and nothing in the app synchronizes them. An offset needs no shared clock. Error = one-way delay (unmeasured; LAN Wi-Fi typically a few ms, worse under load) plus the inbox hop (receipt time is taken on the transport queue, so the hop does not add). Not frame-accurate.
- **Alternatives**: NTP-style round-trip estimation (needs replies, i.e. a second outbound class from the follower; rejected as more traffic and more surface).

## OSC-012-D3: Bounded reliability

- **Decision**: 3 sends per cue change at 0, 100, 300 ms; then a heartbeat every 2 s while leading with an active cue. Late ticks collapse overdue burst slots into one send. A newer change cancels the older burst. No ACK.
- **Rationale**: Recovers from short bursts of loss within 300 ms and from any outage within 2 s after it ends; total traffic is a constant bound (≤ 31 heartbeats per minute) independent of loss, so loss can never cause more sends ("without infinite retransmission").
- **Alternatives**: ACK + retransmit until acknowledged (unbounded under total loss; needs follower sends); heartbeat only (2 s worst-case latency on every cue).

## OSC-012-D4: Ordering and restarts

- **Decision**: (session, seq): session is a random non-zero Int32 per launch of the leader coordinator; seq starts at 1 and grows per cue change. A follower accepts a different session as new, otherwise only a greater seq.
- **Rationale**: Without a session, a restarted leader (seq 1) would be ignored forever. The follower keeps only the last session it saw; an old-session packet arriving after a new one (practically impossible on a LAN across an app restart) would switch it back once, and the new session's next heartbeat (≤ 2 s) restores it. Accepted.

## OSC-012-D5: Receiving path

- **Decision**: A single message tap in `OSCDispatcher.apply(message)`, before route lookup, for `/projectm/cue`; the tap pushes into `OSCCueSyncInbox` (8 entries, newest kept) under the dispatcher lock and requests one main-actor hop only when none is pending.
- **Rationale**: The tap runs after OSC-008's allow-list check and OSC-009's datagram limits, also for messages inside bundles; it never touches the store. Holding the lock is like store observers (documented; the tap must not call back into the dispatcher).
- **Alternatives**: decoding in `OSCReceiver` before the dispatcher (double decode, bypasses rate limits).

## OSC-012-D6: Approval

- **Decision**: Both roles need the allow list on. Leader: `OSCSendCoordinator.activeDestination` already requires approval when the list is on; cue sync adds "list must be on". Follower: messages are acted on only while the list is on, so every message that reaches the tap came from an approved host.
- **Rationale**: The row says "user-approved local peers"; OSC-008 is the app's only approval.

## OSC-012-D7: Applying on the follower

- **Decision**: `ShowCoordinator.stepNow(.go(id))` (the one step path, not the quantizer), skipped when already on the cue; SHOW-002's timed advance held while following is active (`ShowAutoAdvanceCoordinator.isHeld`).
- **Rationale**: Leader quantized already; a second quantize would delay by up to a bar. Holding prevents the follower's own dwell from running away.
