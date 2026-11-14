# Data Model: OSC-008 OSC Peer Allowlist

## OSCPeerAddress (existing, OSC-001)
`ipv4(a,b,c,d)` or `ipv6([16 bytes])`. New: `normalized` (IPv4-mapped IPv6 → IPv4), `text` (display),
`storageText`, `init?(text:)`.

## OSCPeerAllowlist (new, PerformanceControl; Sendable, lock-protected)
| Field | Type | Rule |
|---|---|---|
| isEnabled | Bool | default false (R1) |
| approved | ordered set of normalized local hosts | ≤ 16 (R5); non-local refused (R3) |
| recentlyBlocked | [OSCPeerAddress] | ≤ 4, distinct, most recent first, memory (R4, R11); unknown hosts not listed |
| droppedUnapproved | lives in `OSCReceiverCounters` | memory (R7) |

Operations: `admits(_ peer: OSCPeerAddress?) -> Bool` (records a block), `approve(_:) -> ApproveResult`
(`.approved`, `.alreadyApproved`, `.full`, `.notLocal`), `remove(_:)`, `setEnabled(_:)`, `setApproved(_:)`
(load), `clearRecentlyBlocked()`.

## Stored settings (app)
| Key | Type | Absent | Backup |
|---|---|---|---|
| `settings.osc.peerAllowlist.enabled` | Bool | off | excluded |
| `settings.osc.approvedPeers` | [String] storage text | empty | excluded |
