# Research: MIDI-006 MIDI Note Triggers

## MIDI-006-D1: one normalisation point for velocity 0

- **Decision**: `MIDIEvent.noteEdge` is the only place that decides on/off: `.on` for `.noteOn` with value > 0,
  `.off` for `.noteOff` or `.noteOn` with value 0, nil otherwise. The parsers keep producing `.noteOff` for
  velocity 0 (`MIDIEvent.channelVoice`, used by both the byte parser and the UMP decoder), so the event stream
  itself is already normalised; the router reads only `noteEdge`.
- **Rationale**: MIDI 1.0 defines note on with velocity 0 as note off; running status makes it the common
  form. One property covers events from any producer (tests, a later MIDI 2.0 path).
- **Alternatives**: normalising only in the router (parsers' streams would differ); a second check in each
  consumer (two points drift).

## MIDI-006-D2: edges, not messages

- **Decision**: the router keeps the set of mapped keys that are down. A note on for a key already down does
  nothing; a note off for a key not down does nothing. Trigger fires on the down edge; hold engages on the
  down edge and releases on the up edge. A trigger fires at most once per binding per delivered batch.
- **Rationale**: the row's "consistently" and the brief's "no double toggle"; a glitchy controller or two
  sources sending the same note cannot flip a hold twice. The batch cap bounds a flood to the 30 Hz drain
  rate without a new rate limiter (OSC-009's limiter is keyed by OSC sources and parameter targets and does
  not fit).
- **Alternatives**: fire on every note on (double toggles); a time-based debounce (needs a clock, no gain).

## MIDI-006-D3: stuck notes

- **Decision**: release all held keys when the input stops receiving, when a listed MIDI input disappears
  (events carry no source, so per-source release is impossible by design: MIDI-002-R7), on System Reset; release
  a channel's keys on CC 120 (All Sound Off) and 123 (All Notes Off); release a binding's key when it is deleted,
  replaced or moved.
- **Rationale**: a controller unplugged mid-press never sends its note off.

## MIDI-006-D4: storage beside the CC lines

- **Decision**: `note:<ch>:<note>=<action>[;mode=hold][;unknown…]` lines in `settings.midi.mappings`, written
  after the CC lines. `mode=trigger` reads as trigger and is not written. A `note:` line that cannot be read
  (unknown action, mode not allowed for the action, bad numbers) is kept verbatim at the end. CC lines are read
  by MIDI-003/004's unchanged code, which already skips `note:` lines.
- **Rationale**: no new key (no backup, erase or allow-list change); a newer version's actions (MIDI-007's
  `cue.go:<scene>`) survive this version's saves.
- **Alternatives**: a separate key (three more registrations, and backup/erase split).

## MIDI-006-D5: actions

- **Decision**: Next cue and Previous cue call `ShowCoordinator.next()` / `previous()` (the keyboard path: no
  controls shown); Black out toggle calls OUT-010 `toggleBlackout()`; Black out while held calls
  `setBlackout(true)` on engage if the output was not already blacked out, and `setBlackout(false)` on release
  only if it did the black out and the output is still blacked out.
- **Rationale**: existing, announced, safe calls (restore keeps OUT-010's fade and spacing). Trails and Pause
  have no one-call path without UI side effects; Go to scene is MIDI-007.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R11 and S1-S6 each map to at least one task; no constitution conflict. Fixed: contract N4's learn
announcement text was ambiguous (now exact strings); T13 now names the "note already used moves" edge case.
