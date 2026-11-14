# Contract: a cue's dwell in `show.json` (SHOW-002)

## D1 Writing

- A cue with a dwell carries `"advanceAfter": <integer seconds 1…3600>` in its cue object; a cue without one has no key.
- Keys stay sorted (`advanceAfter` sorts first in the cue object). A show without dwells is byte-identical to SHOW-001/SCN-007 output.
- `format` stays `projectm-ios.show`, `version` stays 1.

Example cue: `{"advanceAfter":30,"id":"…","label":"Intro","scene":"…"}`

## D2 Reading (lenient)

| Stored value | Result |
|---|---|
| absent or `null` | no dwell |
| integer 1…3600 (JSON number without fraction, e.g. `30` or `30.0`) | that dwell |
| `0`, negative, > 3600, fractional (`2.5`), string, object, array, bool | dropped; one count in `ShowDecodeWarning.droppedDwells(n)` per show |

The rest of the show always loads; nothing is refused because of a dwell.

## D3 Timeline (engine, `ShowAdvanceTimeline`)

- T1: A cue started at `t` with dwell `d` and a next cue → exactly one advance, at the first tick with time ≥ `t + d`; never before.
- T2: A tick at time ≥ several deadlines → one advance; the new cue's countdown starts at that tick's time.
- T3: A manual step cancels the pending advance and starts the new cue's countdown at the step's time.
- T4: Holding keeps the remaining time; releasing continues from it. A step while held starts held with the full dwell.
- T5: The last cue, Standby and Off never count down.

## D4 App

- Every step that moves calls `cueStarted` (`ShowCoordinator.perform`), so buttons, keys, pad, MIDI, OSC, switcher, Go to Cue and timed advances are all covered.
- A timed advance is `ShowCoordinator.next()`; nothing else is different.
- Holds: `userPaused`, `externalDisplay.blackoutPhase != .live`, `sceneRepair.pending != nil`, `!appIsActive`.
- `setDwell` is an edit: refused while the scene is locked (SCN-015 message); saves at once; never applies a scene; restarts the active cue's countdown.
- Accessibility identifiers: `showCueCountdown` (cue row), `showCueDwell` (swipe action), `cueDwellPicker`, `cueDwellDone`.
