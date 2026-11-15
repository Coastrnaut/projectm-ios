# Data Model: OSC-005 OSC Send

| Entity | Fields | Rules | Stored |
|---|---|---|---|
| `OSCSendDestination` | `host: OSCPeerAddress`, `port: UInt16` | R3: literal, local, not link-local IPv6/unspecified/multicast; port 1024-65535 | `settings.osc.send.host` (storage text), `settings.osc.send.port` (Int, absent → 9000); device only |
| `OSCSendKind` | `scene`, `beat`, `status` | R6 defaults: scene, status | `settings.osc.send.kinds` ([String], absent → scene+status) |
| Send OSC | Bool | R2: absent → off | `settings.osc.send.enabled` |
| Include scene names | Bool | R7: absent → off | `settings.osc.send.sceneNames` |
| `OSCSendEvent` | `.scene(name: String?)`, `.beat(Int32)`, `.status(OSCSendStatus)` (`started`, `stopped`) | memory only | no |
| `OSCSendRateCap` | last ≤ 60 send times | R9: ≤ 60 per 1 s | no |
| `OSCBeatGate` | last beat index, last beat time, beat counter | R8: once per beat, ≥ 250 ms apart | no |
| Sender counters | `sent`, `dropped` | R10 | memory only |

Activity state (R4): `active = sendEnabled ∧ oscSwitch ∧ appActive ∧ destination ≠ nil ∧ (¬allowlist ∨ approved(destination))`.
Transitions: active → inactive cancels the connection and drops queued sends (R5); inactive → active opens a new
connection; a destination change while active closes and reopens.

All five keys are excluded from the FILE-005 backup, removed by the FILE-011 Settings erase, and removed by
`-uitestResetNotice` (R12).
