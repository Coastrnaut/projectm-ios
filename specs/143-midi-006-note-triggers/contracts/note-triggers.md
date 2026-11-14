# Contract: MIDI-006 MIDI Note Triggers

## N1 Normalisation

`MIDIEvent.noteEdge`: `.on` iff kind `.noteOn` and value > 0; `.off` iff kind `.noteOff`, or `.noteOn` with value
0; nil for every other kind. The byte parser and the UMP decoder produce `.noteOff` (value 0) for note on with
velocity 0, running status included.

## N2 Stored form

- `note:<channel 0-15>:<note 0-127>=<action>` then `;mode=hold` when held, then unknown segments verbatim.
- Read: `mode=trigger` or no mode → trigger; `mode=hold` only for `blackout`; anything else makes the line
  unreadable. Unreadable `note:` lines are kept verbatim after the bindings; lines repeating a key or target
  already read are dropped; at most 64 bindings.
- The app writes `cc:` lines (MIDI-003/004, unchanged) then `note:` lines; the key is removed when both are empty.

## N3 Router

`route(_ batch, bindings) -> [MIDINoteCommand]`, in event order:
- CC 120 or 123 on channel c → `release` for every held hold binding on c; those keys are up.
- System Reset → as `releaseAll`.
- `.on` for a bound key that is up → key down; trigger → `fire` (unless this binding already fired in this
  batch); hold → `engage`. `.on` for a key down → nothing.
- `.off` for a bound key that is down → key up; hold → `release`. Otherwise nothing.
- `releaseAll(bindings)` → `release` for each down key bound to a hold target (sorted by channel, note); all keys up.
- `release(keys:bindings)` → the same for the given keys.

## N4 App

- `MIDIMappingCoordinator.startLearningNote(_:)`, `deleteNoteMapping(_:)`, `noteRows`; learning accepts the first
  `.on` in a batch (the learning press fires nothing; its later note off is ignored).
- Held notes are released when the input stops receiving or the listed sources shrink.
- `MIDINoteActionPerformer.perform(_:)`: fire `cue.next` → show next; fire `cue.previous` → show previous; fire
  `blackout` → toggle; engage → black out if not already, remembering it; release → restore only if remembered
  and still blacked out.
- Announcements on `.midi`: "Press a key or pad on your MIDI device to map Next cue." (status line ends with "…"),
  "Next cue mapped to note C4 on channel 1." (with " (moved from Previous cue)" when the note moved), and MIDI-003's
  timeout text. The status line while learning a note: "Press a key or pad on your MIDI device to map Next cue…".
- Identifiers: `midiNote.<id>` (label "Next cue, note C4, channel 1" / "Next cue, not mapped"),
  `midiNoteLearn.<id>`, `midiNoteDelete.<id>`.
