# Contract: MIDI-008 Transport Mapping

## T1 Press normalisation (`MIDIPressFilter`)

- `rawEdge(event)`: note on (velocity > 0) → (note key, press); note off / velocity 0 → release; CC 0–119 → (CC key,
  press if value ≥ 64 else release); Start, Continue → (`.start` key, press, momentary); Stop → (`.stop` key, press,
  momentary); anything else → nil.
- `accept(key, edge, timestamp, momentary)`: press → `.press` unless the key is down, already pressed in this batch, or
  `timestamp ≠ 0` and within 30 ms of the key's last press (then nil and no state change); release → `.release` only
  if the key was down.
- `beginBatch()` before each batch.

## T2 Router (`MIDINoteRouter.route(_:bindings:)`)

Unbound keys are skipped before the filter (a CC not mapped as a button never reaches it). Trigger mode: `.press` →
`fire`. Hold mode: `.press` → `engage`, `.release` → `release`. CC 120/123 and Reset release held keys as in MIDI-006.

## T3 Lines

`ccbtn:<ch>:<cc>=<action>[;mode=hold]`, `rt:start=<action>`, `rt:stop=<action>` round-trip; MIDI-003/004 `cc:`,
MIDI-006 `note:` and MIDI-007 lines are written byte-identically; unreadable trigger lines are kept.

## T4 App

- Learn on a Transport row accepts the first note press, CC button press (0–119, ≥ 64) or real-time message (not on
  the hold row); the learned press fires nothing; announcements on `.midi`:
  "<title> mapped to CC button 20 on channel 1." / "<title> mapped to MIDI Start."
- Performer: toggle → `setPaused(!isPaused())`; play → `setPaused(false)` if paused; pause → `setPaused(true)` if
  playing. The app's pause path announces on `.playback` and never reveals the controls.
