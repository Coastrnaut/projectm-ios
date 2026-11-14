# Feature Specification: SHOW-002 Timed Cue Advance

**Feature Branch**: `feature/show-002` (spec directory `208-show-002-timed-cue-advance`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row SHOW-002 (P1, size M, depends on SHOW-001, integrated). Observable behavior, verbatim:
"Advance cue after configurable dwell time." Acceptance, verbatim: "Injected clock fires one advance per cue
at configured deadline." Tech: scene timeline engine, monotonic clocks, Codable; deterministic timeline tests +
simulator.

Identifiers carry the roadmap ID: requirements `SHOW-002-R1…`, success criteria `SHOW-002-S1…`, tasks
`SHOW-002-T01…`, research decisions `SHOW-002-D1…`. Other features are cited by their own IDs: SHOW-001 (show
and cues), SCN-007 (cue transitions), SCN-012 (scene repair and unknown/missing reporting), SCN-015 (scene
lock), MOD-017 (quantized changes, applied on each cue step), UIX-002 (scene switcher), UIX-005 (performance
pad), OUT-010 / SHOW-014 (blackout), MIDI-006/007 and OSC (cue actions), ACC-004 (announcer lanes), QA-004
(migration matrix).

## Baseline (audit of 2026-11-14, commit `9baece96`)

| Area | What exists | What SHOW-002 adds |
|---|---|---|
| Cue list (`ShowControl.ShowCueList`) | Cues with stable IDs, label, optional SCN-007 transition; Next/Previous/Go to; no clock | An optional per-cue dwell ("advance after") |
| Show file (`show.json`, version 1) | Optional fields written only when set (SCN-004 folders, SCN-005 tags, SCN-007 transitions); lenient reading with warnings | An optional per-cue `advanceAfter` field, same pattern; no version bump |
| Stepping (`ShowCoordinator.next/previous/go`) | Every step source (buttons, arrow keys, performance pad, MIDI, OSC, scene switcher, Go to Cue) goes through one `perform` path that saves and applies the cue | The step path also (re)starts the cue's countdown |
| Clock | None in the show | A pure timeline engine with an injected monotonic clock |
| Pause, blackout, background | `userPaused`, OUT-010 blackout phase, scene phase | Each holds (freezes) the countdown |
| Scene lock (SCN-015) | Edits refused in `ShowCoordinator`; navigation allowed | Editing a dwell is an edit (refused while locked); timed advances are navigation (allowed) |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is configurable? → A: Each cue may carry its own dwell ("Advance after"): Off (the default, manual only) or a whole number of seconds from 1 s to 60 min (3600 s). It is stored in the show with the cue, so it travels with the show.
- Q: When does a cue's countdown start? → A: When the cue becomes active through any step that moves (Next, Previous, Go to Cue, scene switcher, performance pad, keys, MIDI, OSC, or a timed advance). The deadline is that moment plus the cue's dwell on a monotonic clock (never wall-clock time).
- Q: What does a manual step do to a running countdown? → A: It cancels it; the new cue's countdown (if it has a dwell) starts from the step. Going to the active cue again restarts its countdown.
- Q: What happens on the last cue? → A: The show stops there: the last cue never counts down (its dwell is kept but ignored), as SHOW-001's Next does not wrap. No loop option in this feature.
- Q: What happens at Standby? → A: Nothing counts down; the performer starts the show with Next or Go to Cue.

### Session 2026-11-14 (speckit-clarify)

- Q: Does a cue's transition time count inside its dwell? → A: Yes. The dwell counts from the step that made the cue active, so a 30 s cue with a 2 s crossfade is on screen 30 s in total; the performer sets one number per cue.
- Q: Does Duplicate Scene copy the cue's dwell? → A: Yes, as it copies the SCN-007 transition (SCN-003-R8 pattern); a template copy (SCN-011) or pack import (SCN-014) has no dwell.
- Q: What does a timed advance announce? → A: Exactly what a manual Next announces (the cue lane, ACC-004); no extra "auto" message, so a self-running show is no noisier for VoiceOver than a manual one.
- Q: Does an open scene repair report (SCN-012) hold the countdown? → A: Yes. While the repair report waits for the performer, the countdown holds, so the show never moves past a cue whose repair the performer is reading; it continues when the report closes.
- Q: Which dwell values does the editor offer? → A: Off, 1, 2, 3, 5, 10, 15, 20, 30 and 45 s, and 1, 1.5, 2, 3, 5, 10, 15, 20, 30, 45 and 60 min; a stored value not in the list (any whole second 1…3600 from a file) is shown and kept as its own entry. The performance pad's cue readout shows the same countdown.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A self-running show (Priority: P1)

A performer gives each cue a dwell (for example 30 s, 2 min, 45 s), presses Next once, and the show advances
by itself: each cue holds for its dwell, then the next cue's scene comes in with its transition. The last cue
stays.

**Why this priority**: It is the roadmap row.

**Independent Test**: With an injected clock and a five-cue show with dwells, step the clock; exactly one
advance happens per cue, at its deadline, none early and none twice.

**Acceptance Scenarios**:

1. **Given** a five-cue show with dwells 10, 20, 30, 40 and 50 s and the show on cue 1 at time 0, **When** the clock steps through time, **Then** advances happen at exactly 10, 30, 60 and 100 s (cue 1→2, 2→3, 3→4, 4→5), never one instant earlier, and the show stays on cue 5.
2. **Given** the show on cue 2 with a 20 s dwell, **When** the clock jumps 500 s at once, **Then** exactly one advance happens (to cue 3) and cue 3's countdown starts from that moment.
3. **Given** a cue without a dwell, **When** any amount of time passes, **Then** the show does not advance.

### User Story 2 - Manual control stays in charge (Priority: P1)

During a timed show the performer presses Next early, goes back with Previous, or jumps with Go to Cue. Each
manual step starts the new cue's countdown from that moment.

**Independent Test**: With the injected clock, a manual Next 4 s into a 10 s cue moves on and the next
advance is due at 4 s plus the new cue's dwell; the old deadline never fires.

**Acceptance Scenarios**:

1. **Given** cue 1 (10 s) started at 0, **When** the performer presses Next at 4 s, **Then** cue 2 (20 s) is active and the next advance is at 24 s; nothing happens at 10 s.
2. **Given** cue 3 counting down, **When** the performer presses Previous, **Then** cue 2's countdown restarts in full.

### User Story 3 - See and hold the countdown (Priority: P1)

The controls show "Next in 0:42" next to the cue status, and VoiceOver reads it. Pause, blackout and leaving
the app hold the countdown; it continues from the same remaining time when they end.

**Independent Test**: Pause at 6 s of a 10 s cue, wait 100 s, resume; the advance comes 4 s after resume.

**Acceptance Scenarios**:

1. **Given** a cue counting down with 4 s left, **When** the performer pauses for 100 s and resumes, **Then** the advance happens 4 s after resuming.
2. **Given** a cue counting down, **When** the output is blacked out, **Then** the countdown holds until it is restored.
3. **Given** a cue counting down, **When** the controls are shown, **Then** the cue row reads "Next in m:ss" (and "held" while held), and VoiceOver reads "next cue in 42 seconds".

### User Story 4 - Set a cue's dwell (Priority: P1)

In Settings → Show, each cue offers "Advance After…" (context menu, swipe action, VoiceOver action) with Off
and preset times. A cue with a dwell shows "Advance after 0:30" under its label.

**Independent Test**: Set cue 1 to 30 s; the show file stores it; relaunch keeps it; with the scene locked the
edit is refused.

**Acceptance Scenarios**:

1. **Given** a cue, **When** the performer chooses 30 s, **Then** the row shows "Advance after 0:30" and the show file stores it.
2. **Given** the scene is locked (SCN-015), **When** a dwell edit is attempted, **Then** it is refused with the lock message; timed advances keep happening.

### Edge Cases

- The clock jumps past several deadlines at once (a long frame stall, a test): one advance only; the next cue's countdown starts from the moment of that advance (no catch-up burst of scene changes).
- The active cue's scene is missing or needs repair (SCN-012): the position still moves as for a manual step, and the next countdown starts; the show can keep running past a broken cue.
- The active cue is removed, or the show is replaced: the countdown is cancelled.
- The active cue is moved so it becomes the last: at its deadline Next reports "at end" and nothing changes.
- The active cue's dwell is edited: its countdown restarts from the edit with the new dwell (Off cancels it).
- A step while held (paused, blacked out, repair report open, in the background): the new cue's countdown starts held with its full dwell.
- A show file with an invalid `advanceAfter` (not a whole number, 0, over 3600, a string): that dwell is dropped with a warning (SCN-012-style reporting), the rest of the show loads.
- A show written by this version opened by an older build: the unknown field is ignored (the older build keeps the show manual).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-002-R1**: Each cue MUST support an optional dwell: Off (default) or a whole number of seconds from 1 to 3600.
- **SHOW-002-R2**: The dwell MUST be stored in the show file as an optional per-cue field, written only when set (shows without dwells keep their bytes), with no format version change; an invalid stored dwell MUST be dropped with a warning while the rest of the show loads.
- **SHOW-002-R3**: When a cue becomes active by any step that moves, and it has a dwell and a next cue, the show MUST schedule exactly one advance at the step's monotonic time plus the dwell.
- **SHOW-002-R4**: At or after the deadline (never before), the show MUST advance once, through the same path as a manual Next (scene, transition, SCN-012 repair, MOD-017 queued changes, announcements).
- **SHOW-002-R5**: When the clock passes several deadlines at once, the show MUST advance once; the new cue's countdown starts at the moment of that advance.
- **SHOW-002-R6**: Any manual step MUST cancel the pending advance and start the new cue's countdown from the step.
- **SHOW-002-R7**: Pause, blackout (any phase other than live), an open scene repair report (SCN-012) and the app leaving the foreground MUST hold the countdown, keeping the remaining time; it MUST continue from that remaining time when no hold remains.
- **SHOW-002-R8**: The last cue, Standby and cues without a dwell MUST NOT count down.
- **SHOW-002-R9**: The cue row in the controls and the performance pad's cue readout MUST show the remaining time ("Next in m:ss", "held" while held), and VoiceOver MUST read it as part of the show status ("next cue in 42 seconds", "countdown held").
- **SHOW-002-R10**: The show editor MUST offer "Advance After…" per cue (context menu, swipe action, VoiceOver action) and show the dwell under the label; editing it MUST save at once, never apply a scene, and restart the active cue's countdown when it is the active cue.
- **SHOW-002-R11**: A dwell edit MUST be refused while the scene is locked (SCN-015); timed advances MUST continue while locked.
- **SHOW-002-R12**: The timeline MUST be a pure, deterministic engine with an injected monotonic clock, testable without the app, and MUST build on Linux.
- **SHOW-002-R13**: No network access, no new stored settings key, and no wall-clock time.
- **SHOW-002-R14**: Duplicate Scene MUST copy the source cue's dwell to the new cue.

### Key Entities

- **Cue dwell**: a cue's optional whole-second dwell (1…3600).
- **Advance timeline**: the pending advance — idle, running (cue and deadline), or held (cue and remaining time).
- **Monotonic clock**: a source of elapsed time that never goes backwards; the app's real one and a test's manual one.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-002-S1**: With an injected clock and a five-cue show with dwells, exactly 4 advances happen, each at its deadline (0 early, 0 duplicates), and the show ends on cue 5.
- **SHOW-002-S2**: A clock jump past three deadlines gives exactly 1 advance.
- **SHOW-002-S3**: A manual step resets the deadline: the old deadline never fires (0 advances at it), the new one fires once.
- **SHOW-002-S4**: A hold of any length leaves the remaining time unchanged (the advance comes the same remaining time after the hold ends).
- **SHOW-002-S5**: A show with dwells round-trips through the file byte for byte; a show without dwells is byte-identical to SHOW-001's output.
- **SHOW-002-S6**: In the app (simulator UI test under 30 s), a cue with a 2 s dwell advances by itself and the row shows the countdown.

## Assumptions

- Accuracy within a quarter of a second is enough for a visual show (the app checks the deadline four times a second while a countdown runs); tests use the injected clock, never wall-clock waits.
- A beat-synced advance is SHOW-003, not this feature. Cue sync over OSC is OSC-012.
- Simulator results prove behavior only, not timing on a device.
