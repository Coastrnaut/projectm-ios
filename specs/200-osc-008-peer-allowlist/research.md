# Research: OSC-008 OSC Peer Allowlist

- **OSC-008-D1 Where to filter.** Decision: in `OSCReceiver.handle`, before `OSCDispatcher.handle`, using the
  host carried on the datagram event. Rationale: pure and Linux-testable with the fake transport; the check
  runs per datagram so list changes apply at once (R8) and before the limiter (R6). Alternatives: filter in
  `NetworkDatagramTransport.accept` (per connection; untestable on Linux and stale after list changes);
  filter in the dispatcher (after the source bucket would let blocked hosts drain the global budget).
- **OSC-008-D2 Peer identity.** Decision: host bytes only, IPv4-mapped IPv6 folded to IPv4, zone ignored.
  Rationale: controllers send from ephemeral ports; `NWEndpoint.Host.ipv6` exposes 16 bytes (zone separate).
- **OSC-008-D3 Unknown host.** Decision: unapproved (fail closed) while on. `.datagram` without `peer` keeps
  its old meaning while off, so existing fakes and tests are unchanged.
- **OSC-008-D4 Text form.** Decision: IPv4 dotted decimal; IPv6 as 8 lowercase hex groups without
  compression for storage, RFC 5952 compressed for display. A small pure parser reads only the stored forms
  (and compressed `::` for robustness). Rationale: no `inet_pton` (Linux and Network-free target).
- **OSC-008-D5 Approval UX.** Decision: approve from "Recently blocked" (≤4, memory), no typed entry.
  Rationale: no typos, only hosts that really sent; conservative. Alternative typed entry rejected (validation
  UI, risk of approving non-existent or public hosts).
- **OSC-008-D6 Bounds.** Decision: 16 approved; refusing when full rather than evicting.
- **OSC-008-D7 Backup.** Decision: exclude both keys from FILE-005 (network-specific like `settings.osc.enabled`).
- **OSC-008-D8 Privacy.** Decision: ADR-0058 narrows OSC-001-R13/R15 for user-approved hosts only.
