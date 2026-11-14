# Research: MIDI-007 MIDI Scene Selection

## MIDI-007-D1: stored form in the existing list

- **Decision**: scene mappings are lines in `settings.midi.mappings`: `pc:<ch>:<program>=cue.go:<sceneID>` and
  `note:<ch>:<note>=cue.go:<sceneID>`, unknown `;` segments kept; the position mode is one line
  `pc:<ch|*>:*=cue.position`. Save order: `cc:` lines, MIDI-006 `note:` lines, scene bindings, the mode line, kept
  scene lines.
- **Rationale**: no new UserDefaults key (FILE-005 backup and the Settings erase already cover the key); MIDI-006
  already keeps `note:…=cue.go:` lines verbatim, so a build without MIDI-007 preserves them and this build reads them.
- **Alternatives**: a separate key for the mode (three registration places, no gain); storing mappings in scenes
  (applying a scene would then change mappings, the opposite of the acceptance).

## MIDI-007-D2: one owner per line

- **Decision**: `MIDISceneBindingList` owns every `pc:` line and every `note:` line whose action starts with
  `cue.go:`; `MIDINoteBindingList` skips those. Unreadable lines are kept by their owner only, so nothing is written
  twice.
- **Alternatives**: both lists keeping unknown lines (duplicates on save).

## MIDI-007-D3: routing and debounce

- **Decision**: a mapped program change, or a mapped note's down edge (`noteEdge == .on`), produces a command; the
  newest command in a batch wins (one scene applied per drain). Explicit program mappings are checked before the
  position mode. The performer drops a command for the current scene (`list.activeSceneID`) or, in position mode,
  the current cue index. Scene notes need no down-key state: a repeated note on targets the current scene and is
  dropped by the debounce.
- **Rationale**: the brief's debounce; a foot controller often resends the program on every press; one apply per
  tick bounds a flood without a rate limiter.
- **Alternatives**: applying every command in order (wasteful applies); a time debounce (needs a clock).

## MIDI-007-D4: position mode off by default

- **Decision**: off; one setting: Off, Any channel, or Channel 1–16. Program n → cue n + 1.
- **Rationale**: many controllers send program changes when the user picks a patch; on by default would move a
  running show unasked. One channel or all channels covers the common setups; per-channel sets add UI for no
  acceptance need.

## MIDI-007-D5: missing scenes

- **Decision**: a scene ID with no cue in the show changes nothing and announces "Scene not found." on `.midi`; a
  position past the last cue announces "Cue n not found.". A cue whose scene file is unreadable goes through
  SHOW-001's Go to Cue (repair report or notice), as a tap on Go would.

## MIDI-007-D6: learn

- **Decision**: a third `MIDILearnSession<String>` (scene IDs) with `isSceneEligible` (program change, or note on with
  velocity > 0), sharing the timeout, Cancel, status line and the single-session rule. The learning message is
  removed from the batch before notes and scenes are routed, so it fires nothing. A learned note frees the same key
  in MIDI-006's list (and a MIDI-006 note learn frees a scene key); a scene keeps one key.
- **Alternatives**: a scene keeping one program and one note (two rows per scene, harder learn UI).

## MIDI-007-D7: bank select out of scope

- **Decision**: CC 0/32 are not tracked; programs match on channel and number. A later `;bank=` segment can extend
  the line without breaking this reader (an unknown segment is kept).

## MIDI-007-D8: applying a scene never writes mappings

- **Decision**: only learn, delete, Undo and the mode picker call `save()`. `applyShowScene` sets look settings
  through Settings' setters and never touches the mappings key. Tests compare the stored value byte-for-byte
  (property-list encoding) before and after a selection, with a scene that carries SCN-001 bindings.
