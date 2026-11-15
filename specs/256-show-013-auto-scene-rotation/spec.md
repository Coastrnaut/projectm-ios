# Feature Specification: SHOW-013 Auto Scene Rotation

**Feature Branch**: `feature/show-013` (spec directory `256-show-013-auto-scene-rotation`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SHOW-013 (P1, depends on SHOW-001, integrated). Observable behavior, verbatim: "Rotate only within
selected local scene collection on timer or beat." Acceptance, verbatim: "Seeded rotation excludes disabled scenes and
avoids immediate repeats."

Identifiers carry the roadmap ID: requirements `SHOW-013-R1…`, success criteria `SHOW-013-S1…`, tasks `SHOW-013-T01…`,
research decisions `SHOW-013-D1…`. Other features are cited by their own IDs: SHOW-001 (manual cue list), SHOW-002 (timed
cue advance), SHOW-003 (beat-quantized cues), SHOW-005 (Hold, skip), SHOW-007 (timeline transport, Loop), SHOW-011 (tap
tempo, tempo snapshot), SCN-004 (scene folders), SCN-007 / SHOW-004 (cue transitions), SCN-012 (repair report), UIX-002
(quick scene switcher), MOD-008 (seeded stepped random), FR-072 (Reduce flashing), FILE-005 / FILE-011 (backup and
Settings erase).

## Baseline (audit of 2026-11-14, commit `5fb23871`)

| Area | What exists | Gap for this row |
|---|---|---|
| Local scenes (SHOW-001, SCN-004) | The show's cues are the app's named local scenes; each cue refers to a stored scene. Scene folders (SCN-004) group scenes in a tree; `ShowCoordinator.goToScene` goes to a scene's first cue. | Nothing changes scenes by itself except a cue's dwell (SHOW-002). |
| Step path (SHOW-001 to SHOW-007) | Every step (Next, Go to, the timed advance, Loop's wrap) goes through one path: validation, SCN-012 repair report, the cue's transition resolved with Reduce Motion and Reduce flashing (SCN-007, SHOW-004), the cue announcement, `cueStarted`. `timedGo(to:)` is quantized like SHOW-002's advance (SHOW-003). | No rotation. |
| Timing (SHOW-002, SHOW-003, SHOW-011) | A monotonic clock and a hold (pause, blackout, repair report, background, Hold) drive the timed advance; SHOW-011's tempo snapshot gives `nextBoundary(after:beats:)` (bars of 4 beats). | No timer or bar count between rotations. |
| Seeded randomness (MOD-008, presets) | MOD-008's `SteppedRandom` gives a pure level per (seed, step) with SplitMix64; preset Random never repeats the current preset and stays uniform. | No seeded scene pick. |
| Rotation | None found (`grep` for rotation, shuffle, auto scene in the app and packages: only geometry rotation). | Everything in this row. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is the "selected local scene collection"? → A: The show's scenes (distinct scene IDs in show order), either all of them or one SCN-004 scene folder including its subfolders. A folder that no longer exists counts as "All scenes".
- Q: How are scenes disabled? → A: Every scene in the collection has an "in rotation" toggle (on by default) in a rotation list in Settings. The flag belongs to the rotation, not to the cue: SHOW-005's skip flag and the cue list are untouched.
- Q: How is the next scene chosen? → A: A pure, seeded plan: the enabled scenes of the collection minus the scene shown now; one of them is drawn with MOD-008's `SteppedRandom` level for (seed, step), uniform over the candidates. Same seed and steps give the same sequence; a disabled scene is never chosen; the current scene is never chosen again while two or more scenes are enabled.
- Q: What happens with one or zero enabled scenes? → A: One enabled scene: rotation never switches ("Only one scene is in rotation."). Zero: rotation stays idle and says "No scenes are in rotation." Neither is an error; turning rotation on is allowed and it starts as soon as two scenes are enabled.
- Q: Which timing modes? → A: Timer (15 s to 10 min, default 1 min) on the monotonic clock, or every N bars (1 to 64, default 8) on SHOW-011's tempo grid (bars of 4 beats). Bars mode without a tempo with phase falls back to the timer interval.
- Q: How does a switch happen? → A: Through the show's step path to the scene's first cue: the cue's transition (SCN-007/SHOW-004, Reduce Motion and Reduce flashing applied), SCN-012's repair report, the cue announcement. Timer switches are quantized like SHOW-002's timed advance (SHOW-003); bar switches already fall on a bar and step at once.
- Q: Does a manual scene change matter? → A: Any step that moves the show (Next, Previous, Go to, the switcher, MIDI, the timed advance, a seek) restarts the rotation interval from that moment.
- Q: What happens while the show plays on its timeline (SHOW-002/SHOW-007)? → A: Rotation pauses while a timed cue's countdown runs unheld, and while the timed advance's other holds apply (pause, blackout, repair report, app in background, Hold). When the pause ends the interval restarts. The show's timeline always wins.
- Q: Which settings are stored? → A: The mode, interval, bar count, collection and disabled scenes, in one UserDefaults key `settings.show.rotation` (a device performance choice like SHOW-007's Loop: excluded from backups, erased with Settings, cleared by the UI-test reset). Rotation on/off is session state: off at every launch, so a launch never starts switching scenes by itself (as SHOW-001 never reapplies a cue at launch).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rotate scenes on a timer (Priority: P1) — MVP

A VJ has a show of eight scenes and switches rotation on with a 30 s timer. Every 30 s the output changes to another
scene of the show, never the same one twice in a row, with each scene's own transition.

**Independent Test**: Pure seeded tests of the plan plus a coordinator test with an injected clock: after 30 s the
show's active scene changes through the step path.

**Acceptance Scenarios**:

1. **Given** five enabled scenes and seed S, **When** the plan picks 1000 steps (each from the previous pick), **Then** no pick equals the previous one, and the same seed gives the same 1000 picks again.
2. **Given** rotation on with a 30 s timer and an injected clock, **When** 29 s pass, **Then** nothing changes; **When** 30 s pass, **Then** the show moves to another scene's first cue.
3. **Given** rotation on, **When** the performer presses Next 10 s before the deadline, **Then** the next rotation happens 30 s after that Next.

### User Story 2 - Choose the collection and disable scenes (Priority: P1)

The VJ picks the folder "Set A" and turns off "Strobe" in the rotation list. Rotation now only shows the other scenes of
Set A.

**Acceptance Scenarios**:

1. **Given** a collection of five scenes with two disabled, **When** the plan runs 1000 steps, **Then** neither disabled scene ever appears.
2. **Given** the folder "Set A" chosen, **When** rotation picks, **Then** only scenes in Set A or its subfolders appear.
3. **Given** one enabled scene, **When** rotation ticks, **Then** nothing switches and Settings says "Only one scene is in rotation."
4. **Given** zero enabled scenes, **When** rotation is on, **Then** it stays idle and Settings says "No scenes are in rotation."

### User Story 3 - Rotate on the beat (Priority: P2)

With a tapped tempo of 120 BPM and "every 8 bars", the scene changes on the downbeat every 16 s.

**Acceptance Scenarios**:

1. **Given** 120 BPM with phase and 8 bars, **When** rotation arms at time t, **Then** the deadline is the 8th bar line strictly after t.
2. **Given** no tempo, **When** rotation arms in bars mode, **Then** the timer interval is used.
3. **Given** a very fast tempo and 1 bar, **When** rotation arms, **Then** the deadline is the first bar line at least 4 s away (15 s with Reduce flashing on).

### Edge Cases

- The show has no cues, or the collection is empty: rotation is idle ("No scenes are in rotation.").
- The active cue is outside the collection: any enabled scene can be picked.
- A scene is deleted or moves to another folder: the collection is recomputed at every pick; stale disabled IDs are ignored and dropped on the next save.
- A pick whose step does not move (a quantized step waiting, a manual step already waiting): the rotation waits for the next move, which rearms it.
- The scene needs repair (SCN-012): the repair report holds rotation until it is closed.
- Reduce flashing on: the cue transition is resolved as for any step; bars mode never switches more often than every 15 s.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-013-R1**: The collection MUST be the show's distinct scene IDs in show order, all of them or those whose SCN-004 folder is the chosen folder or one of its subfolders (an unknown folder counts as all).
- **SHOW-013-R2**: The plan MUST be a pure function of (collection, disabled set, current scene, seed, step): it MUST never return a disabled scene, MUST never return the current scene while two or more scenes are enabled, MUST be uniform over the remaining candidates, and MUST return "idle, no scenes" for zero and "idle, one scene" for one enabled scene.
- **SHOW-013-R3**: The timer interval MUST be 15 s to 600 s on a monotonic clock; bars mode MUST use the Nth bar line (4 beats) strictly after the arm time from SHOW-011's tempo, fall back to the timer without a tempo with phase, and keep at least 4 s between switches (15 s with Reduce flashing).
- **SHOW-013-R4**: A due rotation MUST go to the picked scene's first cue through the show's step path (timer: quantized like SHOW-002's timed advance; bars: at once), so transitions, Reduce Motion, Reduce flashing, repair and announcements are a cue step's.
- **SHOW-013-R5**: Every step that moves the show MUST restart the interval from that moment.
- **SHOW-013-R6**: Rotation MUST pause while a timed cue's countdown runs unheld (SHOW-002/SHOW-007) and while the timed advance's holds apply (pause, blackout, repair report, background, Hold); the interval restarts when the pause ends.
- **SHOW-013-R7**: Settings MUST offer: Rotate scenes (on/off, off at launch), Collection (All scenes or a folder), Change (Timer or Bars), the interval or bar count, a status line ("Next scene in 0:42", "Next scene in 8 bars", "Paused while the show plays", "Held", "No scenes are in rotation.", "Only one scene is in rotation."), and a "Scenes in rotation" list with one toggle per scene of the collection.
- **SHOW-013-R8**: The mode, interval, bars, collection and disabled scenes MUST be stored in `settings.show.rotation` (excluded from backups, erased with Settings, cleared by the UI-test reset); unreadable values MUST fall back to the defaults.
- **SHOW-013-R9**: No network access, no wall-clock assertions in tests; ShowControl MUST keep building on Linux.

### Key Entities

- **Rotation settings**: mode (timer, bars), interval seconds, bars, folder (optional), disabled scene IDs.
- **Rotation plan**: collection, disabled set; pick(current, seed, step) → scene or idle reason.
- **Rotation schedule**: arm time, settings, tempo bar lines, Reduce flashing → deadline and whether it is on the beat.

## Success Criteria *(mandatory)*

- **SHOW-013-S1**: Over 1000 seeded steps, disabled scenes appear 0 times, immediate repeats 0 times, and the same seed reproduces the sequence exactly (roadmap acceptance).
- **SHOW-013-S2**: With an injected clock, a 30 s timer switches at 30 s and not before; a manual step restarts it; bars mode at 120 BPM switches on the 8th bar line.
- **SHOW-013-S3**: An app test shows rotation driving real scene switches through the show's step path (the applied scene changes).
- **SHOW-013-S4**: A UI test (under 30 s) sees rotation switch the seeded show's scene by itself.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks rotation on D1 with a tapped tempo.
- Weighted picks, ordered (non-random) rotation and per-scene durations are out of scope.
