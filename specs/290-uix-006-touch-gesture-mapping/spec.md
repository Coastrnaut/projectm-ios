# Feature Specification: UIX-006 Touch Gesture Mapping

**Feature Branch**: `feature/uix-006` (spec directory `290-uix-006-touch-gesture-mapping`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: Roadmap row UIX-006 (P2, size M, depends on SHOW-001, integrated). Observable behavior, verbatim:
"Assign supported gestures to safe performance actions." Acceptance, verbatim: "Gesture conflicts have explicit
precedence and can be disabled."

Identifiers carry the roadmap ID: requirements `UIX-006-R1…`, success criteria `UIX-006-S1…`, research decisions
`UIX-006-D1…`, tasks `UIX-006-T01…`. Other features are cited by their own IDs: SHOW-001 (show and cues), SHOW-011
(tap tempo), SHOW-014 (emergency blackout), SHOW-015 / SCN-015 (performance lock = scene lock), OUT-010 (output
blackout), UIX-013 (HUD), CAM-005 (double-tap camera focus), OUT-007 (corner-pin drags), MIDI-006 / MIDI-008 (note and
transport action catalogues), FR-042 (tap shows or hides the controls), FR-070 (VoiceOver), FILE-005 / FILE-011
(settings backup and erase).

## Baseline: gestures on the visualizer today (audit of 2026-11-15, commit `761e85e7`)

| Gesture or shortcut | Where | Owner | UIX-006 decision |
|---|---|---|---|
| One-finger tap: show or hide the controls (FR-042) | `visualizerTapArea` | `AppCoordinator.toggleControls` | Unchanged, never mappable; lowest precedence |
| One-finger double-tap: camera focus (CAM-005) | `visualizerTapArea`, only while the camera visual shows | `CameraFocusGesture` | Unchanged; double-tap is not offered for mapping |
| Long press | nowhere on the visualizer | — | Not offered (see Clarifications) |
| One-finger swipe for presets | nowhere (presets step with buttons, keys, MIDI) | — | Not offered |
| Two- and three-finger gestures | nowhere | — | **gap**: the new mappable set |
| Corner-pin drags (OUT-007), vector path drags (SHD-008), timeline scrub (SHOW-007), split divider (UIX-007) | their editors, not the visualizer's tap area | their views | Unchanged; shortcuts exist only on the visualizer's tap area |
| Emergency blackout button and B key (SHOW-014) | persistent button, hardware key | `OutputBlackout` | Unchanged; blackout is not offered for gestures |
| Keys: ← → Page Up/Down (cues), ⌘K (scene switcher), ⌘Z/⌘⇧Z, ⌘⇧M (MIDI panic), Escape | `ShowKeyCommands` and others | the coordinator | The action pattern mirrored: cue steps call the same quiet `show.next()/previous()` |
| MIDI note actions (MIDI-006/008): next/previous cue, blackout, play/pause | `MIDINoteActionPerformer` | the coordinator | The safe-action idea reused; the gesture catalogue is narrower (below) |
| Performance lock (SHOW-015 = SCN-015 `SceneLock`) | `settings.scene.locked` | `SceneLock.refusesEdit()` | Blocks editing the mapping; never blocks a mapped action |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Which gestures can be mapped? → A: Six multi-finger gestures on the visualization: two-finger tap, three-finger tap, and two-finger swipe left, right, up and down. Single-finger gestures stay with the existing tap (FR-042) and CAM-005's double-tap. Rejected: double-tap (CAM-005 already uses it for camera focus, and mapping it would delay every single tap that shows the controls); long press (a resting finger or palm on a stage device triggers it, and SHOW-015 already rejected long press as hard to discover and in conflict with VoiceOver); three-finger swipes and four or more fingers (iOS uses them for undo/redo and iPad multitasking).
- Q: Which actions can a gesture run? → A: A safe catalogue only: None, Next cue (Go), Previous cue, Next preset, Previous preset, Tap tempo and Show/hide HUD. Each is navigation or a reversible view preference; none deletes, saves, erases, records or changes the scene. "Go" is SHOW-001's Next (the show's Go). Rejected: anything destructive or that writes the library.
- Q: Can a gesture black out or restore the output? → A: No. Blackout keeps its dedicated emergency button, the B key, OUT-010's controls and MIDI. An accidental two-finger brush must never black out (or bring back) the audience's output; a mistaken restore is worse than a mistaken black-out. Rejected: blackout in the catalogue.
- Q: Do mapped actions reveal the controls? → A: No. Like the keyboard and MIDI paths they act quietly, so the audience output is not covered by the controls; each action still announces on its usual VoiceOver lane (cue lane, preset change).
- Q: What is the precedence between overlapping gestures? → A: One documented order, highest first: three-finger tap; two-finger swipe (left, right, up, down; only one direction is ever recognised for one touch, the order only makes the rule total); two-finger tap; then the unmapped one-finger tap (controls). A three-finger tap contains a two-finger tap, so both are recognised and the three-finger one wins; a two-finger touch that moves past the swipe threshold is a swipe and never also a tap. Exactly one action runs per touch sequence.
- Q: What happens when the winning gesture is set to None? → A: It is removed from the contest and the next gesture in precedence that was also recognised wins (a three-finger tap with "Three-finger tap: None" runs the two-finger tap's action); if none remains, no action runs and the touch falls through to the existing single-tap behavior.
- Q: Is there a master switch, and is it on by default? → A: Yes: "Gesture shortcuts" in Settings › Performance, off by default and on a fresh install. While it is off no gesture is recognised and the visualizer behaves exactly as before. Each gesture can also be set to None.
- Q: What is mapped when the switch is first turned on? → A: Two-finger swipe left: Next cue; right: Previous cue; up: Next preset; down: Previous preset; two-finger tap and three-finger tap: None. Swipes match the keyboard's ← → direction convention for cues (swiping content left moves forward).
- Q: What happens while VoiceOver runs? → A: Gesture shortcuts are suspended automatically: VoiceOver owns two-, three- and four-finger gestures, so the app never installs its recogniser while VoiceOver is on. Settings says so beside the switch. Every mapped action stays reachable through the existing buttons, keys and accessibility actions, so Switch Control and Full Keyboard Access are unaffected.
- Q: Does the performance lock block gestures? → A: No: mapped actions are performance actions (the lock never blocks navigation, SCN-015). The lock blocks editing the mapping: the switch and the pickers are disabled with the lock's note "Scene locked. Unlock the scene to edit.", and a write that still reaches the setting is refused through `refusesEdit()`.
- Q: Is the mapping stored and backed up? → A: Yes: one preference on the device (switch plus mapping), included in the FILE-005 library backup like the other performance preferences (Show HUD), erased with the Settings category (FILE-011) and by the UI-test reset. Unknown or damaged stored values read as the defaults.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Step the show with a gesture (Priority: P2)

A performer turns on Gesture shortcuts and, mid-show with the controls hidden, swipes two fingers left on the
visualization: the show goes to the next cue; a two-finger swipe right goes back. The controls stay hidden.

**Why this priority**: It is the roadmap row.

**Independent Test**: With the switch on and the default mapping, deliver a recognised two-finger swipe left to the
app: the show advances one cue; nothing else changes.

**Acceptance Scenarios**:

1. **Given** Gesture shortcuts are on and "Two-finger swipe left" is Next cue, **When** the user swipes left with two fingers, **Then** the show steps to the next cue and the controls do not appear.
2. **Given** "Two-finger tap" is Next preset, **When** the user taps with two fingers, **Then** the next preset loads and the controls are not toggled.
3. **Given** a mapping is changed, **When** the app relaunches, **Then** the same mapping is in force.

### User Story 2 - Conflicts resolve predictably (Priority: P2)

Overlapping gestures always resolve the same way, and a gesture set to None hands over to the next one.

**Independent Test**: Feed every overlapping pair of recognised gestures to the resolver with various mappings and
compare with the precedence table.

**Acceptance Scenarios**:

1. **Given** both three-finger tap and two-finger tap are recognised and both mapped, **When** resolved, **Then** the three-finger tap's action wins.
2. **Given** the three-finger tap is None, **When** the same touch is resolved, **Then** the two-finger tap's action wins; with both None, nothing runs.
3. **Given** a swipe and a tap are both reported, **When** resolved, **Then** the swipe wins.

### User Story 3 - Off means off (Priority: P2)

With the master switch off (the default), while VoiceOver runs, or with every gesture set to None, no gesture runs an
action and the visualizer behaves as before.

**Acceptance Scenarios**:

1. **Given** the switch is off, **When** any multi-finger gesture is made, **Then** nothing runs.
2. **Given** VoiceOver is running, **When** the switch is on, **Then** no gesture is recognised and Settings says shortcuts are paused while VoiceOver is on.
3. **Given** the scene is locked, **When** the user opens Settings › Gesture shortcuts, **Then** the switch and pickers are disabled with the lock note, and mapped gestures still run.

### Edge Cases

- A two-finger touch that moves more than a tap's slop but less than a swipe's threshold is neither: nothing runs.
- A touch held longer than a tap (0.5 s) without moving is not a tap; a swipe that takes longer than 1 s is not a swipe.
- Four or more fingers: nothing runs (system gestures).
- Next preset with an empty scope or a failed load: the preset coordinator's own handling (nothing changes, nothing announced).
- Next cue with no show or at the last cue: SHOW-001's own handling (no wrap, no change).
- Stored mapping with an unknown gesture or action name (a newer backup): ignored; that gesture reads as its default.

## Requirements *(mandatory)*

- **UIX-006-R1**: The app MUST offer exactly six mappable gestures on the visualization (two-finger tap, three-finger tap, two-finger swipe left, right, up, down) and MUST NOT map one-finger gestures.
- **UIX-006-R2**: Each gesture MUST map to one action from the safe catalogue: None, Next cue, Previous cue, Next preset, Previous preset, Tap tempo, Show/hide HUD. The catalogue MUST NOT contain blackout, restore or any action that deletes, saves, erases, records or edits the scene.
- **UIX-006-R3**: Overlapping gestures MUST resolve by the fixed precedence three-finger tap > two-finger swipes (left, right, up, down) > two-finger tap; at most one action runs per touch sequence.
- **UIX-006-R4**: A gesture set to None MUST be removed from resolution, so the next recognised gesture in precedence wins, or nothing runs.
- **UIX-006-R5**: A "Gesture shortcuts" master switch MUST exist, off by default; while off, no gesture is recognised and no action runs.
- **UIX-006-R6**: While VoiceOver is running, gesture shortcuts MUST be suspended (no recogniser installed), and Settings MUST say so.
- **UIX-006-R7**: Mapped actions MUST run the same coordinator paths as the existing controls (SHOW-001 cue step, preset step with its announcement, SHOW-011 tap, UIX-013 HUD), without revealing the controls.
- **UIX-006-R8**: While the scene is locked (SHOW-015), mapped actions MUST still run, and editing the switch or the mapping MUST be refused (controls disabled with the lock note; writes refused through the lock).
- **UIX-006-R9**: The switch and the mapping MUST persist on the device in one preference, included in the library backup (FILE-005), erased with Settings (FILE-011) and by the UI-test reset; unknown stored values read as defaults.
- **UIX-006-R10**: Tap and swipe recognition MUST use documented thresholds: a tap moves at most 20 pt and lasts at most 0.5 s; a swipe moves at least 50 pt along its dominant axis within 1 s, with exactly two fingers.
- **UIX-006-R11**: With the switch off, the visualizer's existing gestures (FR-042 tap, CAM-005 double-tap) MUST behave exactly as before; with it on, a one-finger tap still toggles the controls without added delay.

### Key Entities

- **Performance gesture**: one of the six mappable gestures; carries its precedence rank.
- **Gesture action**: one entry of the safe catalogue.
- **Gesture shortcut configuration**: the master switch and the gesture → action mapping (missing = default).
- **Touch summary**: the most fingers down at once, the average movement and the duration of one touch sequence; classified into the set of recognised gestures.

## Success Criteria *(mandatory)*

- **UIX-006-S1**: For every pair of overlapping recognised gestures and every mapping of them (mapped or None), the resolver returns the documented winner (pure tests, all pairs).
- **UIX-006-S2**: With the switch off, no recognised gesture set yields an action (pure test) and the visualizer installs no recogniser.
- **UIX-006-S3**: Each catalogue action, invoked through the gesture path, produces the same observable change as its existing control (app tests: Next cue advances the show by one cue, Next preset changes the preset, Tap tempo records a tap, HUD toggles).
- **UIX-006-S4**: A mapping set in Settings survives a relaunch (app test and UI test).
- **UIX-006-S5**: On the simulator, a two-finger tap mapped to Next preset changes the preset without toggling the controls; with it set back to None, a two-finger tap changes no preset (UI test under 30 s).
- **UIX-006-S6**: On a physical device, each mapped gesture runs its action reliably with fingers, and VoiceOver's own multi-finger gestures are unaffected ({device}).

## Assumptions

- SHOW-001's show, SHOW-011's tap tempo and UIX-013's HUD exist and are reused unchanged.
- Simulator results are never device evidence; S6 is a `{device}` task.
- The gestures are recognised only on the visualization's tap area on the device screen; the external display has no touch.
