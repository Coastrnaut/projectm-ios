# Data Model: OSC-011 Local Peer Discovery

| Entity | Fields | Rules | Storage |
|---|---|---|---|
| Discovery switches | `browse: Bool`, `advertise: Bool` | R4: absent → off | `settings.osc.discovery.browse`, `settings.osc.discovery.advertise`; device only (excluded from backup, erased with Settings, UI-test reset) |
| `OSCDiscovery.Activity` | `browse: Bool`, `advertise: Bool` | R5: each = its switch ∧ OSC switch ∧ foreground | derived |
| Announced name | `String` "projectM XXXX" | R7: 4 uppercase hex digits, per launch | memory |
| `OSCDiscoveredPeer` | `name: String` (id), `address: OSCPeerAddress?`, `port: UInt16?` | R8: cleaned name ≤ 63 characters, no control characters; non-local address → dropped; `destination` only when `OSCSendDestination` accepts it | memory |
| Found list | `[OSCDiscoveredPeer]` | sorted by name, at most 16, own name left out, cleared on stop | memory |
| `OSCBrowserEvent` | `.browsing`, `.peers([OSCDiscoveredPeer])`, `.failed(OSCListenerFailure)` | reported on the browser's queue | — |

State: Off → (conditions hold) Browsing → (any condition fails) Off; a failure shows a status until the next start (no retry, as OSC-001-R3).
