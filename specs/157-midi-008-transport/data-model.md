# Data Model: MIDI-008 MIDI Transport Mapping

## Trigger action (`MIDINoteAction`, extended)

`cue.next`, `cue.previous`, `blackout` (MIDI-006) and `transport.toggle` (Play/Pause), `transport.play` (Play),
`transport.pause` (Pause). Only `blackout` allows hold.

## Trigger source (`MIDIControlKey`)

| Kind | Key | Line prefix | Shown | Spoken |
|---|---|---|---|---|
| Note | `.noteOn`, channel 0–15, note 0–127 | `note:<ch>:<note>` | Note C4 · Ch 1 | note C4 on channel 1 |
| CC button | `.controlChange`, channel 0–15, controller 0–119 | `ccbtn:<ch>:<cc>` | CC 20 · Ch 1 | CC button 20 on channel 1 |
| Real-time Start (and Continue) | `.start`, 0, 0 | `rt:start` | MIDI Start | MIDI Start |
| Real-time Stop | `.stop`, 0, 0 | `rt:stop` | MIDI Stop | MIDI Stop |

## Trigger binding (`MIDINoteBinding`)

key, target (action and mode), extra segments. Line: `<prefix>=<action>[;mode=hold][;<extra>…]`. A real-time key with
`mode=hold` is unreadable (kept verbatim). List: at most 64, no two share a key, no two share a target.

## Press filter (`MIDIPressFilter`)

| Field | Meaning |
|---|---|
| down | keys whose press was accepted and not yet released (never real-time) |
| lastPress | key → timestamp (ns) of its last accepted press |
| pressedInBatch | keys accepted since `beginBatch()` |

Constant: repeat window 30 ms.
