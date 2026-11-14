# Feature Specification: SHOW-003 Beat-Quantized Cue Advance

**Feature Branch**: `feature/show-003` (spec directory `214-show-003-beat-quantized-cues`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHOW-003-T01-T14 verified on the Mac: PerformanceControl, ShowControl and LibraryBackup package tests on the host, app unit and UI tests on a private iOS 27.2 simulator; no ADR, no device task)

**Input**: User description: "Implement SHOW-003 (Beat-quantized cue advance) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Queue next cue for the next detected beat or bar." Acceptance, verbatim: "Synthetic
beats trigger once and missing tempo uses explicit fallback." Priority P1, depends on SHOW-001 (manual cue list) and
ANL-005 (beat tracking)."

Identifiers in this feature carry the roadmap ID: requirements `SHOW-003-R1…`, success criteria `SHOW-003-S1…`,
research decisions `SHOW-003-D1…`, tasks `SHOW-003-T01…`. Other features are cited by their own IDs: SHOW-001 (cue
list), SHOW-002 (timed cue advance), SHOW-011 (tap tempo and the one tempo snapshot), ANL-005 (beat tracker), MOD-017
(quantized parameter changes), SCN-015 (scene lock), UIX-005 (performance pad), ACC-004 (announcer lanes), MIDI-006/007
(MIDI cue steps), UIX-002 (scene switcher).

## Baseline: what exists today (audit of 2026-11-14, commit `cd89f309`)

| Question | Today |
|---|---|
| Beat grid | SHOW-011 `TempoSnapshot` (PerformanceControl): manual tap tempo first, else ANL-005's estimate; period and beat anchor on the monotonic analysis clock. MOD-017 added `TempoSnapshot.nextBoundary(after:beats:)` (first grid point strictly after a time, every `beats` beats from the anchor). |
| Quantized timing | MOD-017 `QuantizedChangeQueue` (Off/Beat/Bar/Cue) queues discrete **parameter** changes; `ParameterQuantizer` in the app owns it, its UserDefaults mode, the wake-up task and the announcements; its "no tempo" fallback applies at once and announces it. |
| Cue steps | SHOW-001 `ShowCoordinator.next/previous/go(to:)` share one `perform` path (scene, SCN-007 transition, SCN-012 repair, MOD-017 cue-mode queue right after the scene loads). Callers: controls row, keyboard and clicker keys, performance pad (UIX-005), MIDI notes (MIDI-006), MIDI scene actions (MIDI-007), scene switcher (UIX-002), the show editor's Go. |
| Timed advance | SHOW-002 `ShowAutoAdvanceCoordinator.tick()` calls `show.next()` once per due cue. |
| Beat-quantized cue steps | **None.** Every cue step applies at once. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Is quantizing cue steps a separate setting from MOD-017's "Quantize changes", and which values does it offer? → A: A separate, opt-in show setting "Quantize cue steps" with Off (default), Beat and Bar, stored on the device (`settings.show.quantizeCues`, absent = Off), excluded from library backups and erased with Settings like MOD-017's mode. MOD-017's Cue value has no meaning for a cue step and is not offered. Off keeps every step exactly as before (SHOW-003-R1).
- Q: What does a second request before the boundary do: replace the queued step, advance two cues, or cancel? → A: At most one step waits. The same request again (Next after Next, Previous after Previous, Go to the same cue) cancels it, matching MOD-017's "a request equal to the current value cancels it" and the tap-again-to-cancel gesture; a different request replaces it (latest wins). Two cues are never advanced at one boundary: advancing two would make a double press on a clicker skip a cue at an unpredictable moment (SHOW-003-R3).
- Q: What happens without a tempo? → A: Matching MOD-017: no timeout and no waiting; the step applies at once and VoiceOver announces "Cue changed now, no tempo". A tempo without phase (an estimate with no beat time) counts as no tempo. The boundary is computed once at request time from SHOW-011's snapshot and is not moved by later tempo changes, so a wait never exceeds one beat or one bar (SHOW-003-R2, R5).
- Q: Does a SHOW-002 timed advance wait for the boundary too? → A: Yes: when it comes due while quantizing is on, it is queued as a Next for the next beat or bar like a manual Next, so timed shows land on the beat too. It never cancels or replaces a performer's queued request (a performer's choice wins); the next cue's countdown starts when the step actually applies (SHOW-003-R6).
- Q: How is a queued step shown, cancelled, and ordered with other boundary work? → A: The show controls row and the performance pad show "Cue queued for the next beat" (or bar) and VoiceOver announces it on the cue lane, plus "Queued cue cancelled" on a cancel. Cancel by repeating the same request or by changing the mode (the app has no Standby control; SHOW-001 keeps Standby internal). The scene lock does not affect cue steps (SCN-015 allows cue navigation). At the boundary, MOD-017 Beat/Bar parameter changes due by then apply first, then the cue step runs through the unchanged step path, so MOD-017's cue-mode queue still applies right after the cue's scene loads; a queued Go to a cue removed meanwhile does nothing (SHOW-003-R4, R7, R8).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Next cue on the beat (Priority: P1)

A performer turns on "Quantize cue steps: Beat". Between beats they press Next cue. The show says the cue is queued
for the next beat; on that beat the next cue's scene appears, once, and later beats change nothing.

**Why this priority**: This is the roadmap row and its acceptance.

**Independent Test**: With a synthetic beat grid and an injected clock, request Next mid-beat and step the clock
across several beats.

**Acceptance Scenarios**:

1. **Given** Beat quantizing and a tempo, **When** Next is requested between beats, **Then** the show does not move before the next beat, moves exactly one cue at that beat, and later beats do not move it again.
2. **Given** Bar quantizing, **When** Next is requested mid-bar, **Then** the show moves exactly once at the next bar boundary and not at the beats inside the bar.
3. **Given** a queued Next, **When** the performer presses Next again before the boundary, **Then** the queued step is cancelled and nothing moves at the boundary.
4. **Given** a queued Next, **When** the performer presses Previous (or Go to another cue) before the boundary, **Then** only the latest request applies, once.

### User Story 2 - No tempo: explicit fallback (Priority: P1)

**Independent Test**: With no tempo, request Next while quantizing is on.

**Acceptance Scenarios**:

1. **Given** Beat or Bar quantizing and no tempo with phase, **When** Next is requested, **Then** the show moves at once and VoiceOver announces "Cue changed now, no tempo".

### User Story 3 - Know what is waiting (Priority: P2)

**Acceptance Scenarios**:

1. **Given** a queued step, **When** the controls or the performance pad show the cue, **Then** they show "Cue queued for the next beat" (or bar) and VoiceOver announced it.
2. **Given** the step applies or is cancelled, **Then** the indication disappears.

### Edge Cases

- No tempo, or a tempo without phase: the step applies at once with the fallback announcement.
- A timed advance (SHOW-002) comes due while quantizing: it waits for the next boundary too (see Clarifications).
- A timed advance comes due while a performer's request is already queued: the performer's request stands.
- The queued Go target cue is removed before the boundary: nothing moves at the boundary.
- Next at the last cue (or Previous at the first): nothing to queue; the outcome is the same as today.
- The quantize mode changes while a step is queued: the step is cancelled with an announcement ("Queued cue cancelled").
- The scene lock (SCN-015) is on: cue navigation is still allowed, so steps queue and apply as usual.
- A parameter change (MOD-017 Beat/Bar) due at the same boundary as a cue step: it is applied first, then the cue.
- The app is suspended past several boundaries: the step applies once at the first check after its boundary.
- Tempo changes after a request: the boundary computed at request time stands (bounded wait).

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-003-R1**: A show setting "Quantize cue steps" with Off (default), Beat and Bar is offered in Settings and remembered on the device.
- **SHOW-003-R2**: While Beat or Bar is chosen, every cue step request (Next, Previous, Go to a cue, from any control, key, MIDI or the scene switcher) is queued for the first beat (Beat) or bar boundary (Bar, every 4 beats from the grid's anchor) strictly after the request.
- **SHOW-003-R3**: At most one step is queued. A different request replaces it (latest wins); the same request again cancels it. A step is never applied twice and two requests never advance two cues.
- **SHOW-003-R4**: At its boundary the queued step is applied exactly once through the same step path as an immediate step (scene, transition, repair, MOD-017 cue-mode changes right after the scene), then removed.
- **SHOW-003-R5**: Fallback: without a tempo with phase, a request applies at once and the announcement says it moved now with no tempo.
- **SHOW-003-R6**: A due timed advance (SHOW-002) is a Next request that waits for the boundary like a manual one; it never cancels or replaces a queued request.
- **SHOW-003-R7**: A queued step is shown ("Cue queued for the next beat|bar") in the show controls and the performance pad, and queueing, cancelling and the fallback are announced on the cue lane (ACC-004).
- **SHOW-003-R8**: Changing the quantize mode cancels a queued step with an announcement.
- **SHOW-003-R9**: All timing uses the monotonic analysis clock passed in as an argument; the boundary logic reads no clock itself.

### Key Entities

- **Cue quantize mode**: Off, Beat, Bar; one per device.
- **Queued cue step**: the request (Next, Previous, Go to cue), the request time and its boundary time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-003-S1**: With synthetic beats, a step requested between boundaries moves the show 0 times before, exactly 1 time at, and 0 further times over at least 3 further boundaries (Beat and Bar).
- **SHOW-003-S2**: Without a tempo, 100 % of requests apply at once with the fallback announcement.
- **SHOW-003-S3**: Two different requests before a boundary apply only the latest, once; the same request twice applies nothing.
- **SHOW-003-S4**: A timed advance due while quantizing moves the show exactly once, at the next boundary.

## Assumptions

- The beat grid is SHOW-011's tempo snapshot; there is no downbeat detection, so bars count from the grid's anchor in 4/4 (as MOD-017).
- The mode is device state, excluded from library backups and erased with Settings, like MOD-017's mode.
- With Off (the default) every step behaves exactly as before.
