# Feature Specification: SCN-015 Scene Lock Mode

**Feature Branch**: `feature/scn-015` (spec directory `197-scn-015-scene-lock`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SCN-015 (P1, size S, depends on SCN-001, integrated). Observable behavior, verbatim:
"Prevent accidental editing while in performance mode." Acceptance, verbatim: "Locked scene ignores edit
gestures but permits cue navigation."

Identifiers carry the roadmap ID: requirements `SCN-015-R1…`, success criteria `SCN-015-S1…`, tasks
`SCN-015-T01…`, research decisions `SCN-015-D1…`. Other features are cited by their own IDs: SCN-001 (scene
document), SCN-002 (autosave), SCN-004 (scene folders), SCN-005 (scene tags), SCN-007 (cue transitions),
SCN-008 (snapshots), SCN-010 (undo/redo), SCN-011 (templates), SCN-014 (scene packs), SHOW-001 (show and
cues), SHOW-011 (tap tempo), OUT-010 (blackout), UIX-003 (parameter inspector), UIX-004 (parameter shelf),
MOD-010 (macros), MOD-012 (modulation matrix), MIDI-003/006/007 (MIDI mappings, note and scene actions),
OSC-001 (OSC), ACC-004 (announcer lanes).

## Baseline: every way the live scene can be edited (audit of 2026-11-14, commit `6c52dd38`)

| Edit path | Where it writes today | Lock decision |
|---|---|---|
| Settings › Visual: visual choice, bars, orientation, spacing, glow, smoothing, Lissajous, oscilloscope, radial, beat rings | `AppSettings` properties bound directly by Settings controls | Locked (controls disabled) |
| Parameter inspector (UIX-003), Reset | `ParameterInspectorTargets.target(for:settings:).set` | Locked (refused at the target) |
| Parameter shelf (UIX-004) in the controls and in Settings | the same targets | Locked (refused at the target; strip disabled) |
| Macros (MOD-010) | `MacroCoordinator.setValue` (rewrites the macro value, then the targets) | Locked (refused in `setValue`) |
| Modulation matrix (MOD-012) | not in this tree yet (being merged) | Locked by the Settings section rule once present (follow-up noted) |
| Snapshots (SCN-008): save, rename, delete, recall | `SceneSnapshotCoordinator` (the scene carry, then the targets) | Locked (refused in the coordinator) |
| Layers (CMP-015), photo, slideshow, video loop/speed, logo, text, colors, Color grade, Trails, effect chain | Settings sections and their coordinators | Locked (Settings sections disabled) |
| Show editor (SHOW-001, SCN-003, SCN-007, SCN-011): add, add from template, rename, delete, reorder, duplicate scene, rename scene, transitions | `ShowCoordinator` edit methods | Locked (refused in the coordinator; gestures and menu items removed) |
| Scene folders (SCN-004), tags (SCN-005), scene pack import (SCN-014) | `ShowCoordinator` folder and tag methods, `installImportedScene` | Locked (refused in the coordinator) |
| Undo and redo (SCN-010): buttons, ⌘Z / ⇧⌘Z | `SceneHistoryCoordinator.undo/redo` | Locked (refused; buttons disabled) |
| Preset next/previous/random, browser, audition | the preset coordinator (projectM preset, not the scene document) | Allowed (performance) |
| Show cue next/previous/go (buttons, arrow keys, MIDI-006/007 notes and program changes) | `ShowCoordinator.next/previous/go` | Allowed (performance) |
| Blackout (OUT-010), tap tempo (SHOW-011), pause | their own coordinators | Allowed (performance) |
| MIDI CC (MIDI-003) and OSC parameter values | the live host's external values (never `AppSettings`, never the scene) | Allowed (performance input) |
| Sensory safety, Reduce flashing, audio, recording, OSC/MIDI switches | device settings, not scene content | Allowed (safety and device settings stay reachable) |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What does the lock protect? → A: The scene the performer built: every visual parameter of the live scene, its layers and media choices, macros, snapshots, the show's cue list (cues, labels, order, transitions, scene names), scene folders and tags, and the undo history. It does not freeze the output: cue navigation, blackout, tap tempo, pause and preset changes keep working.
- Q: Is a preset change an edit? → A: No. Choosing, auditioning or stepping presets is performance (as on a hardware VJ deck); it does not change the scene document.
- Q: Are MIDI and OSC parameter values edits? → A: No. They are live performance input that never writes the scene document or `AppSettings`; they keep working while locked. MIDI and OSC cue actions also keep working.
- Q: Where is the lock? → A: A "Lock scene" button in the visualizer's controls and a "Scene lock" section at the top of Settings. Default off. It persists across launches (a performer who locked before a crash stays locked).
- Q: How does the user unlock? → A: Deliberately: tapping "Unlock scene" (controls or Settings) asks for confirmation ("Unlock scene?" with Unlock and Cancel); only Unlock unlocks. Locking needs no confirmation.
- Q: What indicator shows the lock? → A: A "Scene locked" badge with a lock symbol in the visualizer's top status stack, shown whether or not the controls are visible; the controls' lock button shows a closed lock; Settings and the show editor show a "Scene locked" note.
- Q: What does a refused edit do? → A: Nothing changes; the coordinator records "Scene locked. Unlock the scene to edit." as its message (shown where that screen shows messages) and VoiceOver announces it.
- Q: Accessibility? → A: VoiceOver reads the lock button as "Lock scene"/"Unlock scene" with value "Locked"/"Unlocked"; Settings' section offers the same; locking announces "Scene locked", unlocking announces "Scene unlocked" (library lane, ACC-004).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Lock before the show (Priority: P1)

A performer finishes building the scene and show, locks the scene, and performs. A mis-tap on a slider, a
swipe on a cue or ⌘Z on the keyboard does nothing to the scene.

**Why this priority**: It is the roadmap row.

**Independent Test**: Lock; try every edit path through the app's coordinator APIs; the scene document,
the show and the settings are byte-identical afterwards.

**Acceptance Scenarios**:

1. **Given** the scene is locked, **When** the user (or code) tries an inspector write, a macro move, a snapshot recall, a cue delete, a cue reorder, a transition edit or undo, **Then** each is refused and the scene, the show and the settings are unchanged byte for byte.
2. **Given** the scene is locked, **When** the user swipes left on a cue in the show editor, **Then** no Delete action appears and the cue stays.
3. **Given** the scene is locked, **When** Settings opens, **Then** the scene-editing sections are disabled and a note says the scene is locked.

### User Story 2 - Perform while locked (Priority: P1)

While locked, the performer steps cues (buttons, arrow keys, MIDI), blacks out, taps tempo and changes presets.

**Why this priority**: The roadmap acceptance requires cue navigation to keep working.

**Independent Test**: Lock; Next, Previous and Go to cue apply their scenes; blackout and tap tempo work.

**Acceptance Scenarios**:

1. **Given** a locked scene and a show with three cues, **When** the user presses Next, Previous and Go to cue 3, **Then** each cue's scene is applied.
2. **Given** a locked scene, **When** the user blacks out and restores, and taps tempo, **Then** both work as unlocked.

### User Story 3 - Unlock deliberately (Priority: P1)

After the show, the performer unlocks with a confirmation and edits again.

**Independent Test**: Unlock (confirm); an inspector write and a cue delete succeed.

**Acceptance Scenarios**:

1. **Given** the scene is locked, **When** the user taps Unlock scene and cancels, **Then** the scene stays locked.
2. **Given** the scene is locked, **When** the user taps Unlock scene and confirms, **Then** the scene is unlocked, VoiceOver announces "Scene unlocked" and edits work again.
3. **Given** the scene was locked when the app quit, **When** it launches again, **Then** it is still locked.

### Edge Cases

- A cue apply while locked writes settings through the cue path; that is navigation, not an edit, and is allowed. The undo history restarts as before (SCN-010-R9) but undo stays refused.
- Undo/redo buttons read as disabled while locked even when history exists.
- An edit sheet that was already open when the lock turned on (rename alert, transition sheet): its commit is refused by the coordinator.
- A recovery offer (PERF-010 Reopen) and launch restore are not edits; they apply as before.
- A scene pack import, template add or Add Current Scene while locked is refused with the message.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-015-R1**: The app MUST offer a scene lock, off by default, persisted on the device across launches.
- **SCN-015-R2**: Locking MUST need one action ("Lock scene" in the controls or Settings); unlocking MUST need a confirmation.
- **SCN-015-R3**: While locked, every scene edit listed in the baseline as "Locked" MUST be refused at the coordinator that owns the write (not only hidden in the UI): parameter writes through the Settings targets (inspector, shelf, snapshots), macro value changes, snapshot save/rename/delete/recall, show edits (add, template add, pack import, rename, delete, move, duplicate, rename scene, transitions), folder and tag edits, undo and redo.
- **SCN-015-R4**: A refused edit MUST change nothing (scene document, show file, settings) and MUST report "Scene locked. Unlock the scene to edit." to the screen's message area and VoiceOver.
- **SCN-015-R5**: While locked, cue navigation (Next, Previous, Go to cue from buttons, keys, MIDI notes and program changes), blackout, tap tempo, pause, preset changes, MIDI CC and OSC values MUST work as when unlocked.
- **SCN-015-R6**: While locked, edit entry points MUST be disabled or hidden: Settings' scene-editing sections, the controls' parameter shelf strip, the show editor's add buttons, Edit button, swipe-to-delete, drag reorder and edit menu items, the undo/redo buttons and shortcuts. Safety and device settings stay enabled.
- **SCN-015-R7**: A "Scene locked" badge MUST show on the visualizer whenever the scene is locked, independent of the controls' visibility.
- **SCN-015-R8**: Locking and unlocking MUST be announced to VoiceOver ("Scene locked", "Scene unlocked"); the lock control MUST expose its state as an accessibility value and a named action.
- **SCN-015-R9**: The lock setting MUST be listed in the device-test allowed keys, the Library settings policy (excluded from backups: it is session state) and the UI-test reset.
- **SCN-015-R10**: The scene format MUST NOT change; no network access is added.

### Key Entities

- **Scene lock**: one Boolean on the device (`settings.scene.locked`), with the refusal message and the announcements.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-015-S1**: With the scene locked, 7 of 7 representative edit attempts (inspector write, macro move, snapshot recall, cue delete, cue reorder, transition edit, undo) are refused and the scene document, show file and settings are byte-identical.
- **SCN-015-S2**: With the scene locked, Next, Previous and Go to cue each apply their cue's scene (3 of 3); blackout and tap tempo work.
- **SCN-015-S3**: After unlocking, the same edits succeed.
- **SCN-015-S4**: The lock survives a relaunch.
- **SCN-015-S5**: In the app, a swipe-to-delete on a cue while locked leaves the cue; Next advances the cue; unlocking with confirmation works — in a UI test under 30 s.

## Assumptions

- The performer uses one device; the lock is not shared with an external display (the output shows no badge).
- MOD-012's matrix toggles live in a Settings section; once merged, they follow R6 through the Settings rule and need a coordinator guard (follow-up for the merge).
- Simulator results prove behavior only, not performance on a device.
