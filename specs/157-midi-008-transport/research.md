# Research: MIDI-008 MIDI Transport Mapping

## MIDI-008-D1 Extend MIDI-006's trigger list instead of a new list

- **Decision**: Transport actions join `MIDINoteAction`; a trigger binding's key may be a note, a CC button or a
  real-time source. One list, one router, one learn session, one row set ("Transport").
- **Rationale**: Next cue and blackout already exist as MIDI-006 rows; a second list would allow two rows for the same
  action and two copies of the press logic. One action per source and one source per action stay enforced by one list.
- **Alternatives**: a separate `MIDITransportBindingList` (duplicate rows and rules); a `;mode=button` segment on
  `cc:` lines (MIDI-003's list would have to skip them, and `cc:` lines must stay byte-identical).

## MIDI-008-D2 One press filter for all sources

- **Decision**: `MIDIPressFilter` per router: per key a down flag and the last press timestamp, plus the keys pressed
  in the current batch. A press is dropped when the key is down, already pressed in this batch, or within 30 ms of its
  previous press (message timestamps; 0 = unknown, no window). A dropped press changes no state, so its matching
  release is ignored too. Real-time presses are momentary (never left down).
- **Rationale**: the three repeat patterns in the acceptance (same message twice without a release, CC 127 twice,
  duplicated press-and-release across batches) need state, batch scope and a short time window respectively; one
  place keeps MIDI-006's edge rules and MIDI-008's additions consistent.
- **Alternatives**: a debounce on the action (would also swallow a fast deliberate second press of another control);
  delivery-time windows (depend on the 30 Hz drain, not on the controller).

## MIDI-008-D3 CC button threshold

- **Decision**: value ≥ 64 presses (when up), value < 64 releases. The press filter's down state is the hysteresis:
  repeated high values never re-press.
- **Rationale**: the brief and the MIDI convention for switch controllers (CC 64–69: ≤ 63 off, ≥ 64 on).

## MIDI-008-D4 Real-time sources

- **Decision**: Start and Continue are one source (`rt:start`), Stop another (`rt:stop`); learnable on any trigger
  row except the hold row; nothing is mapped by default. MMC SysEx is out of scope (MIDI-002 keeps no SysEx bytes).
- **Rationale**: a DAW sends Continue when resuming; both mean "play". Off by default so a clock source never pauses
  the show unasked.

## MIDI-008-D5 Play and pause target

- **Decision**: the visualizer's existing Pause (FR-046). The performer reads and sets it through injected closures;
  the app's `setPausedQuietly(_:)` reuses the controls' path (pause/resume the active visual, idle timer, `.playback`
  announcement) without revealing the controls, and does nothing outside the visualizer.
- **Rationale**: SHOW-001 has no auto-advance or timeline; FR-046 is the only play/pause the app has.

## MIDI-008-D6 One action per control across lists

- **Decision**: a CC learned as a button is removed from the MIDI-003 list and a CC learned for a parameter loses its
  button binding, both reported as "moved from" and both in the shared Undo; notes already follow MIDI-007-R8.
- **Rationale**: a fader that both moves the glow and steps cues would surprise the performer.

## MIDI-008-D7 Learned press and its copies

- **Decision**: the learning press is registered in the filter (down for notes and CC buttons, the timestamp for all),
  so a duplicate copy of the learning message fires nothing and the release that follows is silent.
