# ADR-0102: Peer Cue Sync Adds One Bounded OSC Message to the Reviewed Sender

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: OSC-012 (`specs/291-osc-012-peer-cue-sync`)
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
- **Amends**: ADR-0088 decision 4 (until now only `/projectm/scene`, `/projectm/beat` and `/projectm/status` left
  the device)

## Context

The roadmap row OSC-012 asks to "synchronize cue ID and monotonic offset between user-approved local peers", with
the acceptance "Packet loss fixture recovers next cue without infinite retransmission". ADR-0088 allows one
opt-in UDP flow to one literal local address with three message kinds. OSC-008's allow list is the app's only
notion of an approved peer; OSC-011 helps the user find and approve one.

## Decision

1. **One new message, same flow.** A device whose Cue sync role is Lead sends
   `/projectm/cue ,siii <cue ID> <seq> <offset ms> <session>` through `OSCSender.postCue` over the existing
   `NetworkOSCSender` to OSC-005's one destination. No new network code, destination type or symbol; every OSC-005
   gate (Send OSC, the receiver switch, the foreground) and the 60/s cap apply.
2. **Approved peers only.** Both roles need OSC-008's "Only approved devices" on: the leader sends only to an
   approved destination, and a follower acts only on messages that passed the allow list.
3. **Bounded sends.** Per cue change at most 3 sends (0, 100, 300 ms), then one heartbeat per 2 s while leading.
   No acknowledgements, no per-message retries, no replies from the follower: traffic does not grow with loss.
4. **Content.** The cue's UUID text, two counters and a random per-launch session number. No scene name, label,
   note, device name or setting.
5. **Off by default.** One device-only key `settings.osc.cueSync.role` (Off, Lead, Follow), excluded from the
   FILE-005 backup and removed by the FILE-011 Settings erase.
6. **Receive side.** `OSCDispatcher` hands `/projectm/cue` to one message tap (after the allow list and the
   datagram rate limits), never to the parameter store; a follower only moves its show position.

## Consequences

- Two devices with the same show can run one cue list; the end-to-end LAN check is OSC-012-T22 `{device}`.
- One follower per leader (OSC-005 has one destination); several followers would need a new ADR.
- Alignment precision is the one-way network delay; no frame-accurate claim.

## Alternatives rejected

- OSC-006 time tags: need agreeing wall clocks.
- Acknowledged delivery with retransmission: unbounded under total loss and needs a second outbound class.
- Multicast or broadcast: refused by OSC-005's destination rule and reaches unapproved hosts.
