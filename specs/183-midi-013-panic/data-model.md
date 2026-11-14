# Data Model: MIDI-013 MIDI Panic

No stored entity is added.

- **Panic command**: one-shot; inputs are the router state, the note bindings, the learn sessions and the input queue.
  Output: release commands for held hold bindings, an announcement ("MIDI reset", `.midi` lane) and a status text.
- **Press rule state after panic**: down set empty, last-press times empty, same-batch set empty (`isEmpty`).
- **Panic trigger binding**: an existing MIDI-006 trigger line with action `midi.panic`, trigger mode only, for example
  `note:0:61=midi.panic`, `ccbtn:0:21=midi.panic`, `rt:stop=midi.panic`. A `;mode=hold` variant is unreadable and kept
  verbatim.
