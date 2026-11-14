# Data Model: MIDI-006 MIDI Note Triggers

| Entity | Fields | Rules |
|---|---|---|
| `MIDINoteEdge` | `.on`, `.off` | From `MIDIEvent.noteEdge` only (D1). |
| `MIDINoteAction` | `cueNext` (`cue.next`), `cuePrevious` (`cue.previous`), `blackout` (`blackout`) | `allowsHold` only for `blackout`. |
| `MIDINoteMode` | `trigger`, `hold` | Stored only as `;mode=hold`. |
| `MIDINoteTarget` | action, mode | Learnable targets: Next cue, Previous cue, Black out, Black out while held. `id`: `cue.next`, `cue.previous`, `blackout`, `blackout.hold`. |
| `MIDINoteBinding` | key (`.noteOn`, channel 0–15, note 0–127), target, extra segments | Line `note:<ch>:<note>=<action>[;mode=hold][;extra…]`. |
| `MIDINoteBindingList` | bindings (≤ 64), kept unreadable lines | No two bindings share a key or a target; binding replaces (moved / replaced outcome). |
| `MIDINoteCommand` | target, phase (`fire`, `engage`, `release`), key | Output of the router. |
| `MIDINoteRouter` | keys down | Down: edge-only; at most one fire per binding per batch. |

State of one mapped key: up →(on)→ down →(off / panic / release-all / binding removed)→ up. A hold binding emits
`engage` on up→down and `release` on down→up; a trigger binding emits `fire` on up→down only.
