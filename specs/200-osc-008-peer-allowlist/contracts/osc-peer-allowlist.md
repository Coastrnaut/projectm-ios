# Contract: OSC peer allowlist (OSC-008)

## A1 Transport event
`OSCTransportEvent.datagram([UInt8], source: OSCSourceID = .unattributed, peer: OSCPeerAddress? = nil)`.
`NetworkDatagramTransport` passes the address it computed for the local check; it never stores it beyond the
connection's receive closure and opens no new connection (R13).

## A2 Receiver
On `.datagram`, for the current generation: if `allowlist.admits(peer)` is false, call
`dispatcher.noteDroppedUnapproved()` and return; the dispatcher's `handle` is not called (no `received`,
limiter, decode, store or live-value change). Otherwise unchanged.

## A3 Allowlist
- Off: `admits` is always true and records nothing.
- On: true iff `peer?.normalized` is in `approved`; otherwise false and, when `peer` is non-nil, the host moves
  to the front of `recentlyBlocked` (≤4, distinct).
- `approve` refuses non-local hosts and a full list (16); approving removes the host from `recentlyBlocked`.

## A4 App (`OSCPeersCoordinator`)
Loads both keys (dropping unreadable or non-local entries), writes them on every change, pushes state into the
receiver's allowlist, and reads `recentlyBlocked` and `droppedUnapproved` on OSC-009's gated refresh. Turning OSC
off clears `recentlyBlocked`.

## A5 Settings UI
Row `oscPeersLink` ("Approved Devices", value "Off" / "N approved") → screen with toggle `oscPeerAllowlistToggle`,
rows `oscApprovedPeer_<n>` with Remove `oscRemovePeer_<n>`, rows `oscBlockedPeer_<n>` with Allow
`oscAllowPeer_<n>`, `oscBlockedCount`, and `oscPeersEmptyNote` when on with no approved host.
