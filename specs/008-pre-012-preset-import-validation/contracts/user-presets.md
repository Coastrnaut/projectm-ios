# Contract: user presets (PRE-012)

## `MilkdropPresetValidator.validate(_ bytes: [UInt8], knownTextures: Set<String>) -> PresetValidation`

Pure, bounded, iterative. Returns `rejection: PresetQuarantineReason?`, `warnings`,
`licenseLines`. Order of checks (the first failing one is the reason): binary content → line
length → line count → header → settings → per block: size, statement length, nesting, balance,
shader completeness. Guarantees: never traps for any byte sequence; time linear in the input; at
most a constant multiple of the input in memory.

## `UserPresetLibrary` (actor)

| Call | Result |
|---|---|
| `load()` | Reads the index, empties `incoming/`, applies a leftover trial record (R17, R18). Idempotent. Returns availability. |
| `setContext(_:)` | Built-in hashes (blob hash → name and pack title), takedown hashes, known texture names. |
| `importFile(at:) async -> PresetImportOutcome` | `.added(preset)`, `.waiting(preset)`, `.quarantined(preset)`, `.refused(reason)`. Never throws. |
| `runPendingTrials() async` | Tries every `pending` preset, oldest first, stopping at the first `unavailable`. |
| `beginProving(id)` / `endProving(id, proven:)` | Writes / removes the record (R18). |
| `quarantineOnScreenFailure(id, message:)` | R19. |
| `remove(id)` | Deletes the record and its file (playable, pending or quarantined). |
| `data(for id)` | The stored bytes of a **playable** preset; nil otherwise (R20). |
| `snapshot` | Records by state, availability. |

Invariants:

1. `data(for:)` never returns bytes of a `pending` or `quarantined` record, and no other call
   exposes them to a renderer.
2. A refusal changes no byte under the directory (S2).
3. After a failed index write, memory, the index and the files are as before the call (R25).
4. A file is in `files/` iff its record is `pending` or `playable`; in `quarantine/` iff
   `quarantined`.
5. With a trial record present at `load()`, no trial of the named preset runs in that or any
   later launch (R17).

## `PresetTrialRunning` (PresetLibrary) and `PresetTrialing` (Rendering)

`run(data, timeout) async -> passed | failed(message) | timedOut | unavailable(reason)`. Never
throws, never blocks the caller's actor, returns within `timeout` plus scheduling slack. After
`timedOut`, calls return `unavailable` until the abandoned work ends. While the app cannot
present frames, calls return `unavailable` and a running trial is cancelled as `unavailable`.

## UI identifiers (XCUITest)

`node:myPresets`, `importPreset`, `userPresetsEmpty`, `preset:<name>` (the shared preset row), `pendingPreset:<name>`, `quarantineLink`, `quarantined:<name>`, `quarantineReason:<name>`,
`deleteQuarantined`, `presetInfo`, alert title "Import Preset".

## Launch arguments (Debug builds)

`-uitestImportPreset <path>` imports that file through the picker's result path once the
visualizer is running; `-uitestResetNotice` also removes the user-preset folder.
