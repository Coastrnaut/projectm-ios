# Data Model: MIDI-002 MIDI Input Monitor

## MIDIEvent (PerformanceControl, value type, 16 bytes)

| Field | Type | Meaning |
|---|---|---|
| `kind` | `MIDIEventKind` (`UInt8` raw) | noteOn, noteOff, polyPressure, controlChange, programChange, channelPressure, pitchBend, systemExclusive, timeCode, songPosition, songSelect, tuneRequest, clock, start, continue, stop, activeSensing, reset |
| `channel` | `UInt8` | 0–15 for channel messages; 0 for system messages |
| `number` | `UInt8` | note, controller or program; 0 when none |
| `value` | `UInt32` | velocity, controller value, pressure (0–127); pitch bend and song position 0–16383; SysEx byte count; time code data byte |
| `timestamp` | `UInt64` | monotonic nanoseconds (the system's uptime clock) |

Rules: note on with velocity 0 is stored as `noteOff` with value 0. Program change and channel
pressure: `number` is the program (program change) or 0 (pressure; the pressure is `value`).
No field names a source. `controlKey` = (kind, channel, number); `normalizedValue` = value / 127
for 7-bit kinds, value / 16383 for pitch bend, nil otherwise; `isChannelMessage`.

## MIDIEventRing

Capacity 512 (power of two not required). Counters: `dropped` (events not stored because full),
`clockCount`, `activeSensingCount`. Producer: `push(_:)`. Consumer: `drain(into:maxCount:)`,
`discardAll()`.

## MIDIInputState

`off` → `receiving` (start with the provider open) → `off` (stop); `unavailable(code)` when the
provider cannot open; a later start retries.

## Monitor entry (app)

| Field | Meaning |
|---|---|
| `id` | sequence number since the monitor opened |
| `event` | the `MIDIEvent` |
| `typeText`, `channelText`, `numberText`, `valueText` | "Control change", "Ch 1", "CC 7", "100" |
| `timeText` | seconds since opened or cleared, "12.40 s" |
| `accessibilityLabel` | "Control change, channel 1, controller 7, value 100" |

Monitor state: `entries` (≤ 64, newest first), `isPaused`, counters `clock`, `activeSensing`,
`whilePaused`, `dropped` (each relative to the last open or clear), `statusText`.
