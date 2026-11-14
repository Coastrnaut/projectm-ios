# ADR-0058: Store User-Approved OSC Peer Hosts; Show Recently Blocked Local Hosts in Memory

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: OSC-008 (`specs/200-osc-008-peer-allowlist`; contract `contracts/osc-peer-allowlist.md`)
- **Constitution**: I (public APIs only), VI (modular boundaries), Privacy constraints; FR-068 as amended
  by ADR-0008 (networking for OSC only)
- **Amends**: OSC-001-R13 and R15 ("counters MUST NOT record peer addresses"; "nothing received MUST be
  stored") and the `OSCPeerAddress` note that addresses are never stored or shown; OSC-009-R3 is unchanged
  (the rate limiter still never sees an address)

## Context

OSC-008 asks to "optionally restrict packets to user-approved local peers", accepted when an unapproved
source address cannot change a scene. An allowlist cannot exist unless the app keeps the hosts the user
approves, and the user cannot approve a controller they cannot see. OSC-001 deliberately kept no address.

## Decision

1. **Off by default.** `settings.osc.peerAllowlist.enabled` absent → off; OSC is then unchanged.
2. **What is stored.** Only hosts the user approves (`settings.osc.approvedPeers`): local addresses
   (OSC-001's rule), at most 16, host only (no port), on this device only. Both keys are excluded from the
   FILE-005 backup and erased with Settings (FILE-011).
3. **What is shown.** While the allowlist is on, the last 4 distinct blocked hosts are kept in memory and
   shown with Allow; they are cleared when OSC is turned off. Counters still hold no address or payload.
4. **Where it is enforced.** The transport hands the address it already reads for the local check to the
   receiver with each datagram (memory only); the receiver drops unapproved datagrams before the rate
   limiter and the decoder. No new network capability: nothing is opened, resolved or sent.
5. **No typed entry.** Hosts are approved only from "Recently blocked", so every entry is a local host that
   really sent to this device.

## Consequences

- The privacy policy describes the option and the stored addresses.
- `ALLOWED_KEYS` in `scripts/run_device_tests.py` lists both keys for the device privacy review.
- A user who never opens Approved Devices stores nothing new.
