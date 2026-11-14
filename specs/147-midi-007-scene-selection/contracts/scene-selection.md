# Contract: MIDI-007 scene selection

## S1 — line codec (PerformanceControl)

- `MIDISceneBinding(storageLine:)` reads `pc:<0-15>:<0-127>=cue.go:<id>` and `note:<0-15>:<0-127>=cue.go:<id>`;
  anything else is nil. `storageLine` writes the same form; extras follow in order.
- `MIDISceneBinding.isSceneLine(_:)`: true for every `pc:` line and every `note:` line whose action starts with
  `cue.go:` (readable or not).
- `MIDIProgramCueMode(storageLine:)` reads `pc:*:*=cue.position` and `pc:<0-15>:*=cue.position`.
- `MIDINoteBindingList(storageLines:)` ignores scene lines; `MIDIBindingList` (MIDI-003) ignores them as before.

## S2 — list

`MIDISceneBindingList(storageLines:)`, `storageLines`, `bind(_:to:)`, `remove(sceneID:)`, `remove(key:)`,
`binding(forKey:)`, `binding(forScene:)`, `programCueMode`, `isEmpty` (no bindings and mode off), capacity 128.

## S3 — router

`MIDISceneRouter.route(_ batch: [MIDIEvent], list:) -> MIDISceneCommand?`: for each event in order, a program change
with a binding → `.scene`; else a program change matching the mode's channel → `.cue(program)`; a note with
`noteEdge == .on` and a binding → `.scene`; the last one wins. Other events: nothing.

## S4 — app

- `MIDIMappingCoordinator`: `sceneBindings`, `sceneRows`, `startLearningScene(_ sceneID:)`, `deleteSceneMapping(_:)`,
  `setProgramCueMode(_:)`, `learningSceneID`, `sceneDisplayName` (set by the app), `performScenes` (set by the app).
  Learn result "<name> mapped to program 5 on channel 1." / "… note C4 on channel 1."; moves add
  " (moved from <name or trigger title>)".
- `MIDISceneActionPerformer.perform(_:)`: `.scene(id)` → nothing when `id` is the active cue's scene; "Scene not
  found." when no cue shows `id`; else Go to Cue for its first cue. `.cue(i)` → nothing when cue i is active;
  "Cue <i+1> not found." when out of range; else Go to Cue.
- Applying never writes `settings.midi.mappings`.
- UI identifiers: `showAssignMIDI` (swipe action), sheet `midiSceneAssign`, status `midiSceneAssignStatus`, done
  `midiSceneAssignDone`, remove `midiSceneAssignRemove`; MIDI Mappings rows `midiScene.<sceneID>`, delete
  `midiSceneDelete.<sceneID>`, picker `midiProgramCueMode`; DEBUG `midiFakeSendProgram`.
