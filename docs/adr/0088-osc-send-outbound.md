# ADR-0088: OSC Send Is an Opt-In UDP Flow to One Literal Local Address

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: OSC-005 (`specs/277-osc-005-osc-send`)
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
- **Amends**: OSC-001-R19 and the FILE-012 network symbol scan (until now the shipping app contained no sending
  code; outbound `NWConnection` APIs were allowed only beside the DEBUG loopback sender)

## Context

ADR-0008's owner ruling (2026-11-12) unblocked OSC-005 under FR-068's one-folder exception: off until the user
enables it, local network only. OSC-001 had kept every sending API out of Release builds, and
`scripts/check_network_symbols.py` enforced that by allowing `NWConnection(host:port:using:)` and `send` only in an
image that defines the DEBUG-only `OSCLoopbackSender`.

## Decision

1. **One reviewed sender.** `NetworkOSCSender` in `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/`
   (the only folder `check_compliance.py` allows the Network framework) is the app's only outbound flow: one UDP
   `NWConnection`, cellular prohibited.
2. **Literal local addresses only.** The destination is a typed IPv4/IPv6 literal that passes OSC-001's local rule,
   minus IPv6 link-local, unspecified, multicast and limited broadcast. Host names are refused, so no DNS lookup or
   Bonjour resolution ever happens; the transport re-checks the address before opening.
3. **Opt-in and gated.** Nothing is sent unless "Send OSC" (off by default), the OSC receiver switch (OSC-007), the
   foreground and, when on, OSC-008's approved-device list all agree. Turning any of them off cancels the flow and
   drops sends not yet handed to the system.
4. **Minimal content, bounded rate.** Only `/projectm/scene` (the name only on the user's choice), `/projectm/beat`
   and `/projectm/status started|stopped`, at most 60 messages per second; nothing is stored but the five settings,
   which never leave the device (not backed up).
5. **Scan rule.** `check_network_symbols.py` allows the outbound pair in an image that defines both the OSC transport
   and `NetworkOSCSender`, also with `--release`; every other Network API stays on the listener-side allowlist, and
   `--release` still rejects the DEBUG loopback sender. The existing Local Network permission covers the flow; its
   usage string now mentions sending.

## Consequences

- Release builds contain outbound UDP code, reachable only through the Send OSC screen.
- The privacy policy's OSC section describes sending; the App Store privacy answers do not change (no data is
  collected: messages go to the user's own device on their network).
- A device check with a LAN receiver (OSC-005-T16) remains `{device}`.
