# Research: MIDI-013 MIDI Panic

## MIDI-013-D1: Reset in the router and press rule, after the source-loss release

- **Decision**: `MIDINoteRouter.panic(bindings:)` calls the existing `releaseAll(bindings:)` (the path MIDI-006-R6 and
  MIDI-011-R5 use when the input stops or a source is lost), then `MIDIPressFilter.reset()` clears the down set, the
  per-key last-press times and the same-batch set.
- **Rationale**: the release commands are exactly those of a source loss, so `MIDINoteActionPerformer` restores a
  hold blackout only if the hold made it (MIDI-006 Clarifications). Clearing last-press times means a press right
  after panic is a fresh press even within the old 30 ms repeat window (MIDI-008-D3): the user asked to forget.
- **Alternatives**: a new release path in the app (duplicates the hold logic, risks a second restore rule); clearing
  only the down set (a stale last-press time could drop the first press after panic).

## MIDI-013-D2: Drop queued input

- **Decision**: `MIDIInputCoordinator.discardPending()` drains the ring into a scratch buffer and delivers nothing;
  the clock, active-sensing and dropped counters are untouched.
- **Rationale**: messages queued before the command (at most one display tick) would otherwise re-press keys right
  after the reset. Late note-offs that arrive after panic are ignored by the press rule (the key is up).
- **Alternatives**: keep them (a held pad's repeated note-ons could re-engage immediately); stop and restart the input
  (drops connections, announces nothing useful, slower).

## MIDI-013-D3: Learn cancelled, nothing stored, one announcement

- **Decision**: `panic()` cancels the CC, trigger and scene learn sessions with no binding (like Cancel, without the
  "cancelled" text), sets the screen status to "MIDI reset." and announces "MIDI reset" on the `.midi` lane on every
  run. It never calls `save()`, never touches live CC values, scene bindings, the show or listening.
- **Rationale**: the spec's "do not change stored mappings or the current scene"; the announcement confirms the
  command even when nothing was held (VoiceOver users cannot see the state).

## MIDI-013-D4: `midi.panic` as a trigger action

- **Decision**: a seventh `MIDINoteAction`, `panic = "midi.panic"`, trigger only, row "MIDI panic" appended to the
  Transport rows. The coordinator intercepts its `.fire` in the router step: commands before it in the batch are
  performed, then `panic()`; commands after it are dropped. The performer ignores `.panic`. Threshold triggers do not
  offer it (`ThresholdTriggerAction` has no such raw value).
- **Rationale**: a controller pad can clear its own stuck neighbours without the screen. The line format is MIDI-006's
  (`note:<ch>:<n>=midi.panic`, also `ccbtn:` and `rt:`), so profiles (MIDI-012) carry it; older versions keep the
  line verbatim as an unreadable trigger line.
- **Alternatives**: a separate `panic:` line tag (a new list for one action); no MIDI trigger (spec allows it, but it
  is cheap here).

## MIDI-013-D5: Keyboard shortcut ⌘⇧M

- **Decision**: ⌘⇧M, on the visualizer (a hidden key command while Settings is closed) and on the Settings button.
- **Rationale**: existing shortcuts are the arrows, Page Up/Down (cues), B (emergency blackout), Escape (cancel
  actions), ⌘K (scene switcher), ⌘Z and ⌘⇧Z (scene history). ⌘. is avoided (UIKit maps it to Escape); ⌘⇧M is not an
  iPadOS system shortcut. Only one of the two registrations is live at a time (the visualizer's is removed while
  Settings is shown).
