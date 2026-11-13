# Data Model: OSC-007 OSC Network Access Switch

## OSC listener badge (derived, not stored)

| Field | Source | Rule |
|---|---|---|
| port | `OSCReceiverCoordinator.state` | `listening(port)` → port; every other state → no badge |

State → badge (OSC-007-R2, R3):

| Receiver state | Badge |
|---|---|
| `off` | none |
| `starting(port)` | none |
| `listening(port)` | "OSC listening on port N" with Stop |
| `stopping` | none |
| `failed(port, _)` | none (Settings explains) |

Transitions caused by Stop: `listening(p)` → `stopping` (badge gone at once) → `off` after the
transport's `.cancelled`; `settings.osc.enabled` becomes false.

## Stored keys

None added. `settings.osc.enabled` (OSC-001-R15) is the only key Stop writes.
