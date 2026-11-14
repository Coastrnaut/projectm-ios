# Data Model: MIDI-007 MIDI Scene Selection

## Scene mapping (`MIDISceneBinding`)

| Field | Type | Rules |
|---|---|---|
| key | `MIDIControlKey` | kind `.programChange` (number = program 0–127) or `.noteOn` (note 0–127); channel 0–15 |
| sceneID | String | 1–64 characters of letters, digits, `-`, `_`, `.` |
| extraSegments | [String] | unknown `;` segments, verbatim, in order |

Line: `pc:<ch>:<program>=cue.go:<sceneID>[;<extra>…]` or `note:<ch>:<note>=cue.go:<sceneID>[;<extra>…]`.

## Program cue mode (`MIDIProgramCueMode`)

`off` (no line, the default) · `anyChannel` (`pc:*:*=cue.position`) · `channel(n)` (`pc:<n>:*=cue.position`).

## Scene mapping list (`MIDISceneBindingList`)

- `bindings` (≤ 128): no two share a key; no two share a scene ID. Later repeats are dropped on read.
- `programCueMode`: the first readable mode line wins; later mode lines are dropped.
- `keptLines`: `pc:` and `note:…=cue.go:` lines that cannot be read, verbatim.
- `storageLines` = bindings, then the mode line, then kept lines.
- `bind(key, sceneID)` replaces the key's and the scene's previous mappings (outcome added / replaced / moved / full);
  `remove(sceneID:)`, `remove(key:)`.

## Scene command (`MIDISceneCommand`)

`.scene(id, key)` or `.cue(index, key)` (0-based position).

## State transitions

Learn: idle → learning (scene ID, 30 s deadline) → bound / timed out / cancelled → idle. Routing has no state.
