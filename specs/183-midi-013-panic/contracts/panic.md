# Contract: MIDI panic (MIDI-013)

## P1 Package (PerformanceControl, Linux-testable)

- `MIDIPressFilter.reset()`; `MIDIPressFilter.isEmpty: Bool` (no down keys, no last-press times, no same-batch presses).
- `MIDINoteRouter.panic(bindings: MIDINoteBindingList) -> [MIDINoteCommand]`: the `releaseAll` commands (one `.release`
  per held key bound to a hold target, ordered by channel then number), then the filter is reset.
  `MIDINoteRouter.isIdle: Bool` = `filter.isEmpty`.
- `MIDINoteAction.panic` raw value `midi.panic`, `allowsHold == false`; `MIDINoteTarget.panic` id `midi.panic`, title
  "MIDI panic", last in `MIDINoteTarget.all`.

## P2 App

- `MIDIInputCoordinator.discardPending() -> Int`: queued messages dropped, count returned.
- `MIDIMappingCoordinator.panic()`: cancels learning (no binding), discards queued input, performs the router's panic
  commands through `performNotes`, sets `lastMessage = "MIDI reset."`, announces `MIDIMappingCoordinator.panicText`
  ("MIDI reset") on the injected `.midi` announcer. Never writes `settings.midi.mappings`.
- A `.fire` of a `midi.panic` binding runs `panic()` after the batch's earlier commands; later commands in the batch
  are dropped.
- `MIDIPanicShortcut.key == "m"`, `MIDIPanicShortcut.modifiers == [.command, .shift]`.

## P3 UI

- Settings › MIDI: button "MIDI Panic" (`midiPanicButton`), hint "Releases every held MIDI key and trigger and stops
  learning. Mappings and the scene stay.", shortcut ⌘⇧M; always enabled.
- Visualizer: hidden ⌘⇧M key command while Settings is closed; VoiceOver action "MIDI panic" on the visualization
  while "Listen for MIDI devices" is on.
- DEBUG with `-uitestFakeMIDI`: "Hold Note" (`midiFakeHoldNote`, note on 60 channel 1, no release) and the readout
  `midiHeldProbe` ("<n> held").
