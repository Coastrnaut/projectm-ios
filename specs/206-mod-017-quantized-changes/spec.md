# Feature Specification: MOD-017 Quantized Parameter Changes

**Feature Branch**: `feature/mod-017` (spec directory `206-mod-017-quantized-changes`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (MOD-017-T01-T11 verified on the Mac: PerformanceControl and LibraryBackup package tests on the host, app unit and UI tests on a private iOS 27.2 simulator; no ADR, no device task)

**Input**: User description: "Implement MOD-017 (Quantized parameter changes) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Apply discrete changes on beat, bar or cue boundaries." Acceptance, verbatim:
"Change requested between beats applies exactly once at next boundary." Priority P1, depends on ANL-005 (beat
tracking) and MOD-001 (typed parameter registry)."

Identifiers in this feature carry the roadmap ID: requirements `MOD-017-R1…`, success criteria `MOD-017-S1…`,
research decisions `MOD-017-D1…`, tasks `MOD-017-T01…`. Other features are cited by their own IDs: ANL-005
(beat tracker), ANL-006 (tempo confidence), SHOW-001 (show cue list), SHOW-003 (beat-quantized cue advance, not
integrated), SHOW-011 (tap tempo and the one tempo snapshot), MOD-001 (registry), MOD-010 (macros), MOD-012
(modulation matrix), UIX-003 (inspector), UIX-004 (parameter shelf), SCN-008 (snapshots), SCN-015 (scene lock),
ACC-004 (announcer lanes).

## Baseline: what exists today (audit of 2026-11-14, commit `d518a943`)

| Question | Today |
|---|---|
| Beat grid | SHOW-011 `TempoSnapshot` (PerformanceControl) is the one tempo every consumer reads: origin (manual tap, ANL-005 estimate at confidence ≥ 0.5, or none), BPM, period in nanoseconds and a beat anchor on the monotonic analysis-bus clock; `nextBeat(atOrAfter:)` and `beatPhase(at:)` already exist. `TempoCoordinator.snapshot` holds it in the app. No downbeat (bar) detection exists. |
| Cue boundaries | SHOW-001 `ShowCoordinator.next/previous/go(to:)` apply a cue's scene through `show.applyScene` (wired in `AppCoordinator+Show.swift`). Every show scene step (buttons, keys, MIDI, scene switcher) passes there. |
| Beat-quantized cue advance | SHOW-003 is **not integrated**; there is no boundary logic to reuse beyond `TempoSnapshot.nextBeat`. |
| Parameter writes | `ParameterInspectorTargets.target(for:settings:)` is the get/set choke point over `AppSettings` for the inspector, shelf, macros and snapshots; SCN-015 refuses its `set` while the scene is locked. Discrete registry parameters with a control today: glow on/off (boolean), circular spectrum bar count and linear spectrum orientation (enums), linear spectrum spacing (fixed choices). |
| Quantized changes | **None.** Every write applies at once. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: What happens in Beat or Bar mode when there is no tempo to wait for? → A: The change applies immediately (no timeout), and the announcement says "applied now, no tempo". A bounded timeout was rejected: a change landing at an arbitrary, unrelated moment is less predictable than an immediate one. A tempo without phase (an estimate with no beat time) counts as no tempo. Cue mode with an empty show applies immediately too (MOD-017-R6).
- Q: Where is a bar boundary without downbeat detection? → A: Every 4 beats counted from the tempo grid's anchor (the last tap, or ANL-005's latest beat), 4/4 only; the boundary is computed once at request time and not moved by later tempo changes, so every wait is bounded by one bar (MOD-017-R4).
- Q: Which edits are quantized? → A: Only discrete parameters (boolean, enum, integer, fixed choices) written from the inspector, the parameter shelf and macros. Snapshot recall, cue scenes, undo/redo, MIDI/OSC live values and modulation are never quantized: they are recalls or continuous inputs, and quantizing them would split one recall into two moments (MOD-017-R2, R3).
- Q: How do cues and scene changes interact with the queue? → A: In Cue mode the cue step is the boundary: queued changes apply right after the next cue's scene is applied (so they land on top of it) and are then gone. In Beat or Bar mode a cue step (any show scene change) clears the queue with the announcement "Queued changes cleared". Changing the mode also clears it (MOD-017-R5, R8).
- Q: When exactly does a request "between beats" apply, and what about clock jumps? → A: At the first boundary strictly after the request time; a request exactly on a beat waits for the next one. The app checks the queue at each due boundary on the monotonic analysis clock; if the app was suspended past several boundaries, the change applies once at the first check after its boundary. Changes due in the same check apply in request order. The mode is a device setting (`settings.modulation.quantize`, absent = Off), excluded from library backups like the other device-only performance settings (MOD-017-R1, R5, R10).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Switch on the beat (Priority: P1)

A performer turns Quantize to Beat. Between beats they switch the glow on in the inspector. The control shows the
change as queued; on the next beat the glow switches on, once, and later beats change nothing.

**Why this priority**: This is the roadmap row and its acceptance.

**Independent Test**: With a synthetic beat grid and an injected clock, request a change mid-beat and step the
clock across several boundaries.

**Acceptance Scenarios**:

1. **Given** Beat mode and a tempo, **When** a discrete change is requested between beats, **Then** it is not applied before the next beat, is applied exactly once at that beat, and later beats do not re-apply it.
2. **Given** a queued change, **When** the same parameter is changed again before the boundary, **Then** only the latest request applies, once.
3. **Given** a queued change, **When** the user sets the parameter back to its current value, **Then** the queued change is cancelled and nothing changes at the boundary.

### User Story 2 - Switch on the bar or the cue (Priority: P1)

**Independent Test**: The same as Story 1 with bar boundaries (every 4 beats from the grid's anchor) and with cue
steps.

**Acceptance Scenarios**:

1. **Given** Bar mode, **When** a change is requested mid-bar, **Then** it applies exactly once at the next bar boundary, not at the beats in between.
2. **Given** Cue mode, **When** a change is requested between cues, **Then** it applies exactly once right after the next cue's scene is applied, and a further cue does not re-apply it.

### User Story 3 - Know what is waiting (Priority: P2)

**Independent Test**: Queue a change and read the control's queued indication and the VoiceOver announcements.

**Acceptance Scenarios**:

1. **Given** a queued change, **When** the inspector or shelf shows that parameter, **Then** it reads "Queued for the next beat" (bar, cue) and VoiceOver announced the queueing.
2. **Given** the change applies, **When** the boundary passes, **Then** the queued indication disappears and VoiceOver announces the applied value.

### Edge Cases

- No tempo (or a tempo without phase) in Beat or Bar mode: the change applies immediately and the announcement says so (fallback, MOD-017-R6).
- Cue mode without any cue in the show: the change applies immediately (MOD-017-R6).
- The scene is locked when the change is requested: refused as today (SCN-015), nothing queued.
- The scene is locked when the boundary passes: the change is refused at that moment (SCN-015 announcement) and dropped.
- A scene change (cue step) in Beat or Bar mode: the queue is cleared and the drop announced.
- Mode changed while changes are queued: the queue is cleared and the drop announced.
- Undo/redo (SCN-010) is an edit of the same scene, not a scene change: the queue is kept.
- Cue mode with cues but no step taken: the change waits until the performer steps (the wait is the performer's choice; switching the mode to Off clears it).
- Continuous parameters (glow intensity, radius, threshold): never queued.
- Tempo changes after a request: the boundary computed at request time stands (bounded wait).
- Clock jumps over several boundaries (app suspended): the change applies once at the first tick after its boundary.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-017-R1**: A quantize mode with four values — Off (default), Beat, Bar, Cue — is offered in Settings and remembered on the device.
- **MOD-017-R2**: Only discrete parameters are quantized: boolean, enumeration and integer kinds, and parameters whose control offers fixed choices. Continuous parameters always apply at once.
- **MOD-017-R3**: The user edit paths — inspector, parameter shelf and macros — are quantized. Scene recall paths (cues, snapshots, undo/redo) and live-value inputs (MIDI, OSC, modulation) are not.
- **MOD-017-R4**: A quantized request is queued with its boundary: Beat → the first beat of the tempo grid strictly after the request; Bar → the first bar boundary strictly after it (bars of 4 beats counted from the grid's anchor); Cue → the next cue step. At most one queued change per parameter; a later request replaces it, and a request equal to the current value cancels it.
- **MOD-017-R5**: At its boundary each queued change is applied exactly once, through the same write path, and removed. Changes whose boundaries a single tick passes apply in request order.
- **MOD-017-R6**: Fallback: without a tempo with phase (Beat, Bar) or without any cue (Cue), the change applies immediately and the announcement says why.
- **MOD-017-R7**: The scene lock is checked at request and again at apply time; a refused apply drops the change.
- **MOD-017-R8**: The queue is cleared, with an announcement, when the mode changes and on a scene change in Beat or Bar mode. In Cue mode the cue step is the boundary.
- **MOD-017-R9**: A queued parameter's control shows its requested value with a visible "Queued for the next beat|bar|cue" indication; queueing and applying are announced on the parameter lane (ACC-004).
- **MOD-017-R10**: All timing uses the monotonic analysis clock passed in as an argument; the boundary logic reads no clock itself.

### Key Entities

- **Quantize mode**: Off, Beat, Bar, Cue; one per device.
- **Queued change**: a parameter, its requested value, the request time and its boundary (a time for Beat/Bar, "next cue" for Cue).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-017-S1**: In Beat, Bar and Cue modes, a change requested between boundaries is applied 0 times before, exactly 1 time at, and 0 further times after the next boundary over at least 3 further boundaries.
- **MOD-017-S2**: With five requests for one parameter before a boundary, exactly one value (the last) is applied.
- **MOD-017-S3**: Without a tempo, 100 % of Beat/Bar requests apply immediately with the fallback announcement.
- **MOD-017-S4**: A change whose boundary passes while the scene is locked is never applied.
- **MOD-017-S5**: The queued indication is visible for every queued parameter and gone after its boundary.

## Assumptions

- The beat grid is SHOW-011's `TempoSnapshot` (manual tap tempo first, else ANL-005's estimate); there is no downbeat detection, so bars count from the grid's anchor in 4/4.
- The mode is session-independent device state (a UserDefaults key) and is excluded from library backups like other performance settings.
- SHOW-003 (beat-quantized cue advance) is not integrated; this feature does not quantize cue steps themselves.
