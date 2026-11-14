# Contract: MIDI-003 MIDI Learn

## L1 Pure model (`PerformanceControl`, Linux-testable)

- `MIDILearnEligibility.isEligible(_ event: MIDIEvent) -> Bool`: control change, number ≤ 119.
- `MIDIControlBinding`: `key`, `target`, `storageLine`, `init?(storageLine:)`.
- `MIDIBindingList`: invariants of data-model.md; `bind`, `remove(target:)`, `target(for:)`,
  `binding(for:)`, `bindings`, `storageLines`, `init(storageLines:allowedTargets:)`, `capacity = 64`.
- `MIDILearnSession`: `start(target:now:)`, `handle(_ batch: [MIDIEvent], now:) -> MIDILearnOutcome?`,
  `expire(now:) -> MIDILearnOutcome?`, `cancel() -> MIDILearnOutcome?`, `timeout = 30 s`,
  `target`, `isLearning`. `handle` returns at most one `.bound` per call (MIDI-003-R2, R3).
- `MIDIBindingValues.values(for batch:, bindings:, registry:, skipping index:) -> [ParameterID: Double]`:
  linear over each continuous target's range; newest wins; skipped index ignored.
- `MIDILearnCatalog.learnable(in registry:, applied:) -> [ParameterDescriptor]`: external control,
  continuous, in `applied`, registration order.

## L2 App coordinator (`MIDIMappingCoordinator`, main actor)

- `rows: [MIDIMappingRow]` (one per learnable parameter: id, name, control text or "Not mapped",
  combined accessibility label), `statusText`, `learningTarget`, `canLearn`, `canUndo`,
  `liveValues`.
- `startLearning(_ id:)`, `cancelLearning()`, `deleteMapping(_ id:)`, `undo()`, `open()`,
  `close()` (clears undo; learning is cancelled).
- `receive(_ batch:)`: the input client handler; handles learning first, then values.
- Input client `"mappings"` registered iff learning or bindings exist.
- Storage: `settings.midi.mappings` `[String]`, written on every list change, read at init.
- Announcements through the injected `.midi` announce closure: learning started, bound (with the
  status text), timed out. Never values.
- `applyValues: @MainActor ([ParameterID: Double]) -> Void` called with the full live map after
  each change.

## L3 Host (`NativeSpectrumHost`)

- `externalValues: [ParameterID: Double]`; glow IDs replace the manual intensity, radius,
  threshold, knee before MOD-002 and the ACC-012 clamp. Unknown IDs are ignored. Empty = FX-001 path.

## L4 Identifiers (accessibility)

`midiMappingsLink`, `midiMappingsStatus`, `midiMappingsCancel`, `midiMappingsUndo`,
`midiMapping.<parameter ID>` (row), `midiLearn.<parameter ID>`, `midiDelete.<parameter ID>`,
`midiFakeSendCC` (DEBUG, on the mappings screen too).
