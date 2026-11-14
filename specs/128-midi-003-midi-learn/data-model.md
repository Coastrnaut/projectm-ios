# Data Model: MIDI-003 MIDI Learn

## Control key (MIDI-002 `MIDIControlKey`)

| Field | Type | Rule |
|---|---|---|
| kind | `MIDIEventKind` | `.controlChange` for every binding in this row |
| channel | UInt8 | 0–15 (shown 1–16) |
| number | UInt8 | 0–119 learnable; 120–127 never bound |

## Binding (`MIDIControlBinding`)

| Field | Type | Rule |
|---|---|---|
| key | `MIDIControlKey` | see above |
| target | `ParameterID` | a learnable parameter (MIDI-003-R1) |

Stored form: `cc:<channel 0-15>:<number 0-119>=<parameter ID>`, e.g. `cc:0:7=effect.bloom.intensity`.
No other field exists, so nothing about a device can be stored (MIDI-003-R4). MIDI-004 onward add
optional suffixes (range, curve, inversion) after the parameter ID, separated by `;`; this row
writes none and ignores unknown suffixes on read (MIDI-003-R16).

## Binding list (`MIDIBindingList`)

- Ordered bindings, at most 64 (`MIDIBindingList.capacity`).
- Invariants: no two bindings share a key; no two share a target.
- `bind(key, to:) -> MIDIBindOutcome`: `.added`, `.replaced(previous: MIDIControlKey)`,
  `.moved(from: ParameterID)`, `.movedAndReplaced(from:previous:)`, `.full`.
- `remove(target:) -> MIDIControlBinding?`, `binding(for target:)`, `target(for key:)`.
- `storageLines: [String]`; `init(storageLines:allowedTargets:)` skips unreadable, duplicate,
  disallowed and excess lines.

## Learn session (`MIDILearnSession`)

States: `idle` → `learning(target, deadline)` → `idle`.

| Transition | Trigger | Result |
|---|---|---|
| idle → learning | `start(target, now)` | deadline = now + 30 s |
| learning → learning | `start(other, now)` | target replaced, deadline restarted |
| learning → idle | first eligible event in `handle(batch, now)` | `.bound(key, target, eventIndex)` |
| learning → idle | `handle` or `expire` with now ≥ deadline | `.timedOut(target)` |
| learning → idle | `cancel()` | `.cancelled(target)` |

## Live values

`[ParameterID: Double]` in parameter units, memory only, empty at launch; the newest value per
target per batch; removed when the target's binding is removed or moved away.

## Status (coordinator)

| State | Text |
|---|---|
| listening off | "Turn on Listen for MIDI devices to learn a control." |
| idle, no change yet | "Tap Learn, then move a control on your MIDI device." |
| learning | "Move a control on your MIDI device to map <parameter>…" |
| bound | "<Parameter> mapped to CC <n> on channel <c>." |
| moved | "<Parameter> mapped to CC <n> on channel <c> (moved from <old parameter>)." |
| timed out | "MIDI learn timed out. Nothing was mapped." |
| cancelled | "MIDI learn cancelled." |
| stopped by listening | "Learning stopped: Listen for MIDI devices is off." |
| full | "No more mappings fit (64). Delete one first." |
