# Feature Specification: SHOW-007 Timeline Transport

**Feature Branch**: `feature/show-007` (spec directory `243-show-007-timeline-transport`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHOW-007-T01-T15 verified on the Mac, simulator "SHOW7 iPhone 17", iOS 27.2;
T16 `{device}` open; no device claim). ShowControl 128 tests (1.7 s; 5 new); app `ShowTransportAcceptanceTests` 7
(0.1 s, the roadmap acceptance); `ShowTimelineUITests` 1 (8.5 s).

**Input**: Roadmap row SHOW-007 (P1, size L, depends on SHOW-001, integrated). Observable behavior, verbatim: "Provide
play, pause, scrub and loop for local show timeline." Acceptance, verbatim: "Seek updates scheduled parameter values
without duplicate events."

Identifiers carry the roadmap ID: requirements `SHOW-007-R1…`, success criteria `SHOW-007-S1…`, tasks
`SHOW-007-T01…`, research decisions `SHOW-007-D1…`. Other features are cited by their own IDs: SHOW-001 (show, cues,
the one step path), SHOW-002 (cue dwell and timed advance), SHOW-003 (beat/bar quantized steps), SHOW-004 (transition
override), SHOW-005 (Hold and Skip), SHOW-006 (rehearsal), SCN-007 (cue transitions), MOD-017 (quantized parameter
changes, Cue mode), MOD-007/008 (LFOs), SCN-010 (scene history), ACC-004 (announcer lanes), ACC-005 (accessible
sliders), UIX-005 (performance pad), UIX-013 (HUD).

## Baseline (audit of 2026-11-14, commit `5d6b34da`)

| Area | What exists | Gap for this row |
|---|---|---|
| Steps (SHOW-001) | `ShowCoordinator.perform` is the one step path: it moves the position, reads and validates the cue's scene, drives the cue's transition (SCN-007/SHOW-004) and applies the scene (`applyScene`, which also runs MOD-017's `cueApplied`, scene history restart, previews and media prewarm). | No notion of time across cues. |
| Timed advance (SHOW-002) | Each cue may carry a dwell (1 s…60 min). `ShowAdvanceTimeline` (pure, injected monotonic clock) holds one pending advance: running, held (remaining kept) or idle. The last cue has no countdown (no wrap). | No position within the show, no seek, no loop. |
| Quantized steps (SHOW-003) | Steps may wait for the beat or bar; a waiting step fires later through the step path. | A seek must not leave a waiting step to fire afterwards. |
| Hold / Skip (SHOW-005) | The performer's Hold freezes timed advances keeping the remaining time; skipped cues are passed over by Next/Previous and the timed advance. | Hold is the "pause" this row needs; no "play" wording or position. |
| Scheduled parameter values | The only values scheduled along the show are each cue's scene values, applied at cue boundaries; MOD-017 Cue mode applies queued changes on top of the next cue. LFOs (MOD-007/008) are free-running, not scheduled by the show. There are no automation lanes. | Seeking must apply the destination's values exactly once. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: What is the show timeline? → A: The cues in show order that are not skipped, each lasting its dwell, placed end to end from 0:00. The timeline ends at the first such cue that has no dwell (an open end: the timed advance stops there too); later cues are reachable by Next and Go to Cue but are not on the timeline. A show with no timed cue has no timeline and the transport is not shown.
- Q: What are the "scheduled parameter values"? → A: The scene values each cue applies at its start (SHOW-001), with MOD-017's Cue-mode changes on top. No automation lanes are added. A seek resolves the cue active at that time and its elapsed time, applies that cue's scene once and positions its countdown; it never applies the cues it passes over.
- Q: What are Play and Pause? → A: Pause is SHOW-005's Hold (one state, not a second hold): the countdown freezes with its remaining time. Play is Hold off. At Standby, Play also seeks to 0:00 (applies the first timeline cue once).
- Q: How does scrubbing avoid duplicate events? → A: While the performer drags, only a preview position ("Cue 3 · Drop at 0:12") is shown; nothing is applied. Releasing commits one seek. A seek to a time inside the active cue only moves its countdown (no scene apply, no transition, no announcement); a seek to another cue applies that cue once. Repeating the same seek changes nothing.
- Q: How does a seek interact with transitions and quantized steps? → A: A seek lands on the target state: the destination scene comes in as a cut (Reduce flashing's minimum fade still applies, as for every cue), replacing any transition in progress. A seek is not quantized (it is a transport jump, not a cue step) and withdraws a step waiting for the beat or bar, so nothing fires afterwards.
- Q: What is Loop? → A: An explicit opt-in toggle, off by default, remembered on this device (`settings.show.loop`, not backed up, erased with Settings). With Loop on and a timeline without an open end, the last timeline cue counts down and the show wraps to the first timeline cue, exactly once per pass (quantized like a timed advance). With Loop off nothing changes from SHOW-002.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered with the recommended option (owner rules 4 and 9).

- Q: Does the position keep moving through the last timeline cue when Loop is off (SHOW-002 shows no countdown there)? → A: Yes. The position tracks elapsed time in every timed cue, the last one included, and stops at the end of the timeline; SHOW-002's "Next in" text is unchanged (still none on the last cue without Loop).
- Q: Does a seek or a loop wrap post a VoiceOver announcement? → A: No. A seek is the performer's own action and the slider's value speaks the new position; a wrap is a timed advance (which announces nothing today). Only Play/Pause keep SHOW-005's Hold announcements ("Hold on, timed advances paused" / "Hold off") on the cue lane, so nothing is announced twice.
- Q: How large is one VoiceOver swipe on the scrub slider? → A: 5 seconds (ACC-005 grid from 0:00), each swipe one committed seek; the spoken value is ACC-005's seconds form ("75.0 seconds") and the visible text beside it reads "1:15 / 2:30". (Implementation note, 2026-11-14: the track is a custom scrub bar with the ACC-005 modifier, because a system slider in the controls lost its release under XCUITest drags; the end of a drag, released or cancelled, commits the one seek.)
- Q: Is a seek an edit (refused while the scene is locked; recorded in scene history)? → A: No. A seek is a performance action like a step: allowed while locked (SCN-015), it restarts scene history as every cue apply does (SCN-010) and saves the show's position.
- Q: Where is the transport shown? → A: Only in the visualizer's cue row (with the controls), under Previous/Next, when a timeline exists. The performance pad (UIX-005), the HUD (UIX-013), the external display and recordings are unchanged.

### Session 2026-11-14 (speckit-analyze)

- Consistency pass: R1 → T02, T03; R2 → T05, T06, T07, T09; R3 → T09; R4 → T02, T03, T07, T09; R5 → T04, T05, T09; R6 → T11, T12; R7 → T10, T12; R8 → T08, T13; R9 → T03, T14, T15; R10 → T06, T09, T12. S1 → T09; S2, S3 → T12; S4 → T13. No constitution conflict. Fixes applied: R10 was listed before R9 (reordered); R5's Reduce flashing fade and R10's "allowed while locked" and "no announcement" had no named test (added to T09); T14's Linux note reworded.
 *(mandatory)*

### User Story 1 - Scrub to a point in the show (Priority: P1) — MVP

A VJ runs a timed show of five cues. During a rehearsal they drag the show's timeline to 1:15, inside cue 3: the
output jumps straight to cue 3's look, cue 3's countdown shows the time it has left, and cue 2's look never flashes
on the way.

**Independent Test**: Five cues with 30 s dwells, active cue 1; seek to 75 s: exactly one scene apply (cue 3), cue 3's
countdown reads 15 s, no transition, announcement or quantized step for cue 2.

**Acceptance Scenarios**:

1. **Given** cue 1 active, **When** the performer seeks to 75 s, **Then** cue 3 is applied once and its countdown shows 15 s.
2. **Given** that seek, **When** the same seek is repeated, **Then** nothing new is applied, announced or driven.
3. **Given** a seek inside the active cue, **When** it commits, **Then** only the countdown moves.
4. **Given** the performer drags across several cues, **When** they release, **Then** exactly one apply happens (the destination) and nothing during the drag.
5. **Given** cue 2 is skipped, **When** the timeline is built, **Then** cue 2 has no span and seeks never land on it.

### User Story 2 - Play, pause and loop (Priority: P1)

The VJ presses Pause: the countdown freezes; Play continues it with the same remaining time. For an installation they
turn Loop on: after the last cue the show starts again at cue 1, forever, one wrap per pass.

**Acceptance Scenarios**:

1. **Given** cue 2 with 18 s left, **When** paused for 10 minutes and played, **Then** it still has 18 s left.
2. **Given** Loop on, **When** two passes elapse, **Then** the show wrapped exactly twice and applied each cue once per pass.
3. **Given** Loop off, **When** the last cue's dwell ends, **Then** nothing happens (SHOW-002 unchanged).
4. **Given** Standby, **When** Play is pressed, **Then** the first timeline cue is applied once.

### Edge Cases

- No cue has a dwell: no timeline; the transport row is hidden.
- The active cue is not on the timeline (a skipped cue reached by Go to, or a cue after the open end): the position reads "Off timeline"; a seek still works.
- A timeline ending in an open-ended cue: Loop is unavailable (dimmed, "Loop needs every cue timed").
- A seek to the very end without Loop lands on the last timeline cue with 0 s left (nothing more happens).
- A seek while a step waits for the beat: the waiting step is withdrawn silently.
- A seek during a transition in progress: the destination appears as a cut.
- A seek while held (paused): it lands held with the new remaining time.
- The scene is locked (SCN-015): transport is a performance action and stays available.
- A seek to a cue whose scene needs review: SCN-012's repair report opens once, as for any step.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-007-R1**: The show timeline MUST place the non-skipped cues end to end by dwell, end at the first cue without a dwell, and map any time to one cue and its elapsed time, and a cue and elapsed time back to a time.
- **SHOW-007-R2**: A seek MUST resolve the destination cue and elapsed time; to another cue it MUST apply that cue's scene exactly once (no intermediate cue applied, driven or announced) and set its countdown to the remaining dwell; inside the active cue it MUST only move the countdown.
- **SHOW-007-R3**: Repeating a seek to the same time MUST fire no new apply, transition, announcement or quantized step.
- **SHOW-007-R4**: Scrubbing MUST show a preview position while dragging and commit exactly one seek on release.
- **SHOW-007-R5**: A seek MUST land on the target state (a cut; Reduce flashing's minimum fade still applies), MUST NOT be quantized and MUST withdraw a waiting quantized step.
- **SHOW-007-R6**: Pause MUST be SHOW-005's Hold (remaining time kept) and Play MUST release it; Play at Standby MUST seek to 0:00.
- **SHOW-007-R7**: Loop (opt-in, off by default, key `settings.show.loop`, device-only: not backed up, erased with Settings and by the UI-test reset) MUST wrap from the last timeline cue to the first exactly once per pass; it MUST be unavailable for a timeline with an open end.
- **SHOW-007-R8**: The transport row (Play/Pause, position and total, scrub slider, Loop) MUST appear in the cue row only when a timeline exists, with VoiceOver labels and values; the slider MUST use the ACC-005 accessible slider (one 5 s swipe = one seek).
- **SHOW-007-R9**: No network access, no new show-file field, no wall-clock assertions in tests; ShowControl MUST keep building on Linux.
- **SHOW-007-R10**: The timeline position MUST advance through every timed cue, the last included, and stop at the end; seeks and wraps MUST NOT post announcements (Play/Pause keep the Hold announcements); a seek MUST be allowed while the scene is locked.

### Key Entities

- **Show timeline**: ordered entries (cue, start, span or open end) and the total duration.
- **Seek plan**: nothing, move the countdown, or apply one cue, with the remaining time.
- **Scrub**: the drag's preview time and its single commit.
- **Loop setting**: a device preference.

## Success Criteria *(mandatory)*

- **SHOW-007-S1**: With an injected clock and a recorder of every event (scene applies, transitions driven, announcements, MOD-017 applies, quantized steps), a seek across three cues records exactly one apply (the destination) and zero events for the passed-over cues; a repeated seek records zero new events.
- **SHOW-007-S2**: With Loop on, two full passes record exactly two wraps and each cue applied exactly twice; with Loop off, zero wraps.
- **SHOW-007-S3**: Pause and Play keep the remaining dwell to the second, across a 10-minute pause.
- **SHOW-007-S4**: A UI test (under 30 s) scrubs the timeline and sees the cue row move to the destination cue.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks scrubbing during a live show on D1.
- MIDI, OSC and keyboard control of the transport are out of scope (SHOW-001's keys, MIDI-006/008 note actions are unchanged).
- The performance pad (UIX-005) and HUD (UIX-013) are unchanged; they keep showing SHOW-002's countdown, which a seek updates.
