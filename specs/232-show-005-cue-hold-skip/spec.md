# Feature Specification: SHOW-005 Cue Hold and Skip

**Feature Branch**: `feature/show-005` (spec directory `232-show-005-cue-hold-skip`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHOW-005-T01-T16 verified on the Mac, simulator "SHOW5 iPhone 17", iOS 27.2; no
device claim). ShowControl package 120 tests (1.8 s; 6 new in `ShowSkipTests`); app `CueHoldSkipAcceptanceTests` 7
(0.09 s, the roadmap acceptance); `CueHoldSkipUITests` 1 (12.8 s).

**Input**: Roadmap row SHOW-005 (P1, size S, depends on SHOW-001, integrated). Observable behavior, verbatim: "Pause
automation or skip selected cue without deleting it." Acceptance, verbatim: "Hold prevents automatic advances; manual
next remains available."

Identifiers carry the roadmap ID: requirements `SHOW-005-R1…`, success criteria `SHOW-005-S1…`, tasks
`SHOW-005-T01…`, research decisions `SHOW-005-D1…`. Other features are cited by their own IDs: SHOW-001 (show and
cues, `show.json`, one step path), SHOW-002 (dwell and timed advance, its holds), SHOW-003 (quantized cue steps),
SHOW-004 (the optional per-cue field pattern), SCN-003 (Duplicate Scene), SCN-015 (scene lock), UIX-002 (scene
switcher), UIX-005 (performance pad), ACC-004 (announcer lanes).

## Baseline (audit of 2026-11-14, commit `4cdca3a4`)

| Area | What exists | What SHOW-005 adds |
|---|---|---|
| Steps (SHOW-001) | Next, Previous and Go to Cue on a value-type cue list; every source (controls, keys, pad, MIDI, OSC, switcher, editor, timed advance, quantized step) runs through one step path | Next and Previous pass over skipped cues |
| Timed advance (SHOW-002) | A cue's dwell counts down on a monotonic clock; pause, blackout, a pending repair report and the background hold it, keeping the remaining time; a due advance runs a timed Next | A performer's **Hold** is one more hold source; a timed step already waiting for the beat is withdrawn and re-armed |
| Quantized steps (SHOW-003) | A timed request only fills an empty slot; a manual step replaces or cancels the waiting one | Nothing new beyond the withdrawal above |
| Optional per-cue fields (SHOW-002 `advanceAfter`, SHOW-004 `transitionOverride`) | Written only when set; read leniently with counted warnings; no version bump | An optional per-cue `skip`, same pattern |
| Scene lock (SCN-015) | Edits refused; navigation allowed | Skip edits are edits (refused while locked); Hold is performance state (allowed) |
| Cue row, performance pad, editor | Countdown "Next in 0:42" (", held"); pad readout with the countdown; editor rows with swipe, context and VoiceOver actions | A Hold button in the cue row, "Hold" in the pad readout, a "Skipped" row state and Skip actions in the editor |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Is Hold saved? → A: No. Hold is session state for the running show: it starts off at every launch and is not stored in the show or in settings (no new settings key). A hold that silently survived a relaunch would stop a show that the performer expects to run.
- Q: What does Hold freeze? → A: Only automatic (timed) advances. The countdown stops with its remaining time kept and resumes from that time when Hold is turned off (the SHOW-002 hold rule). Next, Previous, Go to Cue and every other manual source stay available and move exactly as without Hold.
- Q: What does a manual step do while Hold is on? → A: It moves; the new cue's countdown starts held with its full dwell and runs when Hold is turned off (SHOW-002: a cue that starts during a hold starts held).
- Q: Where is Skip stored? → A: In the show, as an optional per-cue boolean `skip`, written only when true (shows without skipped cues keep their bytes), read leniently (a value that is not a boolean is dropped with a counted warning). No format version change.
- Q: How does Skip change stepping? → A: Next and Previous (manual, timed or quantized, from every source) pass over skipped cues to the nearest cue that is not skipped. Go to Cue on a skipped cue still goes there (an explicit choice; the scene switcher and MIDI scene selection use Go to Cue). From a skipped cue, Next and Previous go to the nearest cue that is not skipped.
- Q: What if every cue is skipped? → A: Next and Previous do not move; a notice "All cues are skipped." shows and is announced on the cue lane; the Next and Previous buttons are disabled (SHOW-001-R13) and the status reads "All cues skipped".
- Q: How is it shown? → A: Hold: a "Hold" toggle button in the visualizer's cue row (VoiceOver "Hold timed advances", value on/off), the countdown line reads "Next in 0:42, held", and the performance pad's cue readout shows "Hold" (VoiceOver ", hold on") with a VoiceOver action to toggle it. Skip: a skipped cue's row is dimmed with "Skipped" under its label (VoiceOver ", skipped"); actions "Skip Cue" / "Don't Skip Cue" in the context menu, a trailing swipe "Skip"/"Unskip" next to Delete and a VoiceOver action.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered with the recommended option (owner rules 4 and 9).

- Q: Is turning Hold on or off announced? → A: Yes, on the cue lane (ACC-004): "Hold on, timed advances paused" and "Hold off". The toggle's own VoiceOver value also changes (on/off). Rejected: silent (a performer using VoiceOver with controls hidden would not know the state changed).
- Q: Does a cue reached explicitly (Go to Cue) while skipped still count down its own dwell? → A: Yes: the cue is active and its dwell applies; its timed advance goes to the next cue that is not skipped (or none). Skip only decides where Next and Previous land.
- Q: Does the next-cue media warm-up (PERF-005) follow Skip? → A: Not in this feature. It may warm a skipped cue's media; that costs a little memory, never correctness. Recorded as out of scope.
- Q: Does Hold change the show file or a backup? → A: No. Hold is never written; FILE-005 backups carry the `skip` flags automatically because they re-encode `show.json` through the show's own decode and encode.
- Q: What does a skip value other than `true` in a file do? → A: `false` and absent mean not skipped (a writer never writes `false`); any other JSON type (number, string, object) is dropped with a counted warning `droppedSkipFlags(n)` and the show loads.

### Session 2026-11-14 (speckit-implement)

- Q: Which swipe edge carries Skip? → A: The trailing edge, next to Delete (Delete first, so a full swipe still deletes). The leading row (Go, Duplicate, Name, Transition, Into, Advance, MIDI) is already wider than an iPhone screen: in the simulator a seventh leading action sat at x = 475 on a 402-point screen and could not be tapped. Custom trailing actions replace `onDelete`'s automatic swipe, so Delete is declared there too (hidden while locked) and Edit mode keeps `onDelete` (research SHOW-005-D8).

### Session 2026-11-14 (speckit-analyze)

- Consistency pass over spec, plan and tasks: R1 → T05, T09; R2 → T09; R3 → T05, T06, T09; R4 → T05, T12; R5 → T02, T03, T11; R6 → T02, T10, T11, T12; R7 → T05, T10, T12; R8 → T08, T13, T14; R9 → T10, T12; R10 → T16; R11 → T07. S1-S2 → T09, S3 → T11, T12, S4 → T11, S5 → T14. No constitution conflict. Two fixes applied: T12 now tests that Duplicate Scene copies the flag (R9 had no test), and T11 tests that skipping the active cue keeps the position (an edge case without a test).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hold the timed show (Priority: P1) — MVP

A performer runs a show where each cue advances after 30 s. The band extends a song; they press Hold. The countdown
stops at 0:12 and no cue advances by itself; they press Next when the song ends and the show moves one cue. Later
they release Hold and the next countdown runs.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: With an injected clock, a cue with a 30 s dwell; Hold on at 18 s; advance the clock past the
deadline: no move. Manual Next: exactly one cue. Hold off: the countdown resumes with the kept remaining time and fires
then.

**Acceptance Scenarios**:

1. **Given** cue 1 with a 30 s dwell is counting down and Hold is turned on at 18 s, **When** time passes the deadline (and far beyond), **Then** the show does not advance and the countdown shows 0:12 held.
2. **Given** Hold is on, **When** the performer presses Next, **Then** the show moves exactly one cue (to the next cue that is not skipped).
3. **Given** Hold was turned on with 12 s left, **When** Hold is turned off, **Then** the advance happens 12 s later, not earlier and not after a full dwell.
4. **Given** a timed step is waiting for the next beat (SHOW-003), **When** Hold is turned on, **Then** the waiting step is withdrawn and the advance happens at once (quantized) when Hold is turned off.

### User Story 2 - Skip a cue without deleting it (Priority: P1)

A performer drops cue 3 tonight but keeps it in the show. They mark it Skip; Next from cue 2 goes to cue 4, Previous
from cue 4 goes to cue 2, and the timed advance from cue 2 goes to cue 4. The row shows "Skipped". Next week they
unskip it.

**Independent Test**: Step over one and several skipped cues with Next, Previous and a timed advance; Go to a skipped
cue; skip every cue; round-trip the flag through the show file; refuse the edit while the scene is locked.

**Acceptance Scenarios**:

1. **Given** cues 1-5 with cue 3 skipped, **When** Next is pressed on cue 2, **Then** cue 4 becomes active; Previous from 4 gives 2.
2. **Given** cues 2 and 3 skipped, **When** Next on cue 1 or a timed advance from cue 1, **Then** cue 4 becomes active.
3. **Given** every cue after the active one is skipped, **Then** Next is unavailable and the active cue gets no countdown.
4. **Given** a skipped cue, **When** the performer chooses Go to Cue on it, **Then** it becomes active.
5. **Given** every cue is skipped, **When** Next is requested, **Then** nothing moves and "All cues are skipped." is shown and announced.
6. **Given** the scene is locked, **When** a Skip edit is attempted, **Then** it is refused with the lock message and nothing is saved; Hold still works.
7. **Given** a show with skipped cues, **When** it is saved and read back, **Then** the same cues are skipped and the bytes match; a show without skipped cues has no `skip` key.

### Edge Cases

- Hold on with no countdown running: nothing to freeze; a cue started later starts held.
- A skipped cue reached by Go to Cue counts down its own dwell and advances to the next cue that is not skipped.
- A `skip` value that is not a boolean in a file is dropped with a counted warning; the show loads.
- Hold together with pause, blackout, a repair report or the background: the countdown runs only when none of them holds.
- A Skip edit makes the active cue's last remaining next cue skipped: its countdown is cancelled (nothing to advance to); unskipping does not start a countdown until the next step.
- Skipping the active cue does not move the show.
- Duplicate Scene copies the cue's Skip flag (the copy behaves like its source).
- Reordering, renaming or moving cues keeps each cue's flag (it belongs to the cue ID).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-005-R1**: The show MUST offer a Hold that, while on, prevents every automatic (timed) advance, keeping the countdown's remaining time; turning it off MUST resume the countdown from the kept time.
- **SHOW-005-R2**: While Hold is on, every manual step (Next, Previous, Go to Cue from every source) MUST remain available and behave as without Hold.
- **SHOW-005-R3**: Turning Hold on while a timed step waits for the beat or bar MUST withdraw that step, and turning Hold off MUST make it due again at once.
- **SHOW-005-R4**: Hold MUST be session state: off at launch, never stored, and allowed while the scene is locked.
- **SHOW-005-R5**: Each cue MUST support an optional Skip flag stored in the show as an optional per-cue field written only when set, read leniently (invalid → dropped with a counted warning), with no format version change.
- **SHOW-005-R6**: Next and Previous (manual, timed and quantized) MUST pass over skipped cues; Go to Cue MUST still reach a skipped cue; when every cue is skipped a step MUST NOT move and MUST show and announce a notice.
- **SHOW-005-R7**: Skip edits MUST save at once, never apply a scene or move the position, be refused while the scene is locked, and cancel a countdown that no longer has a cue to advance to.
- **SHOW-005-R8**: The cue row MUST offer the Hold toggle and the performance pad MUST show the Hold state, both with VoiceOver; the editor MUST show skipped cues dimmed with "Skipped" and offer Skip/Unskip as context menu, swipe and VoiceOver actions (hidden while locked).
- **SHOW-005-R9**: Duplicate Scene MUST copy the Skip flag.
- **SHOW-005-R11**: Turning Hold on or off MUST be announced on the cue lane.
- **SHOW-005-R10**: No network access, no new stored settings key, no wall-clock time.

### Key Entities

- **Hold**: a show-level, session-only switch that freezes timed advances.
- **Skip flag**: a cue's optional stored mark that makes Next and Previous pass over it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-005-S1**: In the acceptance test, with Hold on, 0 automatic advances happen at or after the deadline (checked at the deadline and 10 minutes past it), and one manual Next moves exactly one (non-skipped) cue.
- **SHOW-005-S2**: After Hold off, the advance happens exactly when the kept remaining time has elapsed (not 1 tick earlier).
- **SHOW-005-S3**: Next, Previous and the timed advance pass over one and over several skipped cues in every tested case; every-cue-skipped gives no move and one notice.
- **SHOW-005-S4**: A show with skipped cues round-trips byte for byte; a show without them is byte-identical to the output before this feature.
- **SHOW-005-S5**: In the app (simulator UI test under 30 s), Hold shows in the cue row and the editor shows a cue as skipped after the Skip action.

## Assumptions

- Simulator results prove behavior only; no device task is needed for this feature.
- The PERF-005 next-cue media warm-up does not follow Skip in this feature.
- MIDI, OSC and keyboard shortcuts for Hold are out of scope (they can map to it later); the Hold toggle is in the controls and, for VoiceOver, on the pad readout.
