# Feature Specification: SHOW-010 Beat Grid

**Feature Branch**: `feature/show-010` (spec directory `254-show-010-beat-grid`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHOW-010-T01-T11 verified on the Mac, simulator "SHOW10 iPhone 17", iOS 27.2;
T12 `{device}` open; no device claim). ShowControl 154 tests (1.3 s; 8 new in `BeatGridTests`, the roadmap acceptance);
app `ShowBeatGridAcceptanceTests` 4 (0.04 s); `ShowBeatGridUITests` 1 (11.7–13.4 s).

**Input**: Roadmap row SHOW-010 (P1, depends on ANL-005 and SHOW-007, both integrated). Observable behavior, verbatim:
"Display beat and bar positions using manual or estimated BPM." Acceptance, verbatim: "120 BPM test renders beat ticks
every half second."

Identifiers carry the roadmap ID: requirements `SHOW-010-R1…`, success criteria `SHOW-010-S1…`, tasks `SHOW-010-T01…`,
research decisions `SHOW-010-D1…`. Other features are cited by their own IDs: ANL-005 (tempo estimate), ANL-006 (tempo
confidence), SHOW-003 (beat-quantized cues), SHOW-007 (show timeline, scrub bar, playhead), SHOW-008 (keyframe tracks),
SHOW-011 (tap tempo and the shared tempo snapshot), MOD-017 (quantized parameter changes), ACC-005 (accessible sliders).

## Baseline (audit of 2026-11-14, commit `ae588a5d`)

| Area | What exists | Gap for this row |
|---|---|---|
| Tempo (SHOW-011, ANL-005, ANL-006) | One tempo snapshot for every consumer: a manual tap tempo first, else ANL-005's estimate at confidence ≥ 0.5, else none. It carries the BPM, the beat period in whole nanoseconds and an anchor beat on the monotonic analysis clock (nil when the estimate has no beat time). Bars are 4/4 from the anchor (SHOW-003, MOD-017). | Nothing shows where the beats and bars fall. |
| Show timeline (SHOW-007) | `ShowTimeline` lays timed cues end to end from 0:00; the transport row shows Play/Pause, a custom scrub bar over the whole timeline, the position text and Loop. The position comes from the show driver's playhead on its own monotonic clock. | No beat or bar marks on the bar. |
| Keyframe tracks (SHOW-008) | Tracks are edited as a list; a keyframe is added at the playhead. | No time axis to draw a grid on. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Where is the grid shown? → A: As tick marks on the SHOW-007 timeline row's scrub bar (beats short, bars tall), plus a one-line grid readout next to the position text ("Bar 3 · Beat 2 · 120 BPM", or "No tempo"). The SHOW-008 keyframe editor is a list with no time axis, so it gets no ticks.
- Q: Which tempo? → A: SHOW-011's tempo snapshot, unchanged: manual tap tempo first, else the ANL-005 estimate at confidence ≥ 0.5, else none. With no tempo nothing is drawn and the readout says "No tempo".
- Q: How is the grid placed on the show timeline? → A: Beats are one period apart (60 s / BPM, in whole nanoseconds as SHOW-011 defines it) and bars every fourth beat, 4/4 counted from the tempo's anchor beat. The anchor is placed on the show timeline where that beat fell, measured through the playhead while the show plays; while the show is paused or at Standby the last placement is kept; with no anchor (an estimate without a beat time) or before any placement the grid starts at 0:00.
- Q: How dense can the grid get? → A: Bounded. At most 512 ticks for any window, and drawn ticks are at least 4 points apart: when beats would be closer, only bars are drawn; when bars would also be closer, every 2nd, 4th, 8th… bar. The model never returns more than the bound.
- Q: How are bars numbered? → A: 0:00 always lies in bar 1; bars count up from there (bar 1 may start just before 0:00 when the anchor is not on 0:00), beats 1 to 4 within a bar.
- Q: Snap keyframe add or seek to the nearest beat? → A: Not in this row. Seeks and keyframe adds keep SHOW-007/SHOW-008 behavior; SHOW-003 and MOD-017 already quantize cue and parameter changes to the grid. The model offers the nearest-beat time for a later row.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered with the recommended option (owner rules 4 and 9).

- Q: Where is the grid shown when the show has no timed cue (no SHOW-007 row)? → A: Nowhere. The grid needs a show timeline; without one there is no row and nothing is drawn (no new control elsewhere).
- Q: What does the readout follow while the performer drags the scrub bar? → A: The scrub preview time (the same time the position text shows), so the performer sees the bar and beat they would land on; otherwise the playhead.
- Q: How often does the grid update? → A: With the timeline row's existing redraw (twice a second while on screen and not dragging) and on any tempo change; no new timer and no per-frame work.
- Q: Is the anchor placement smoothed? → A: No. While playing it is recomputed on every redraw from the playhead and the tempo's anchor (both monotonic clocks, differences only); the error is far below one point at timeline scale, and smoothing would lag behind new taps.
- Q: How is the tempo source worded? → A: Manual is "tap tempo" and an accepted estimate is "detected" (VoiceOver: "120 BPM, tap tempo, bar 3 beat 2"); an estimate below the 0.5 confidence floor is no tempo ("No tempo"), exactly as SHOW-011's snapshot reports it.

### Session 2026-11-14 (speckit-analyze)

- Consistency pass: R1 → T02, T03; R2 → T02, T03, T05; R3 → T02, T03; R4 → T04, T06; R5 → T05, T06, T07; R6 → T07, T08, T09; R7 → T03, T10. S1, S2 → T03; S3 → T03, T06; S4 → T09. No constitution conflict (no network, no storage, public APIs, ShowControl stays Foundation-only).
- Fix applied: S3's 0.01-point tolerance was not named in the tasks; T03 and T06 now assert it.
 & Testing *(mandatory)*

### User Story 1 - See the beats on the show timeline (Priority: P1) — MVP

A VJ taps tempo at 120 BPM and plays a timed show. Tick marks appear along the timeline every half second, a taller tick
every two seconds marks each bar, and the readout shows "Bar 3 · Beat 2 · 120 BPM" as the playhead moves.

**Independent Test**: A pure model test: a 120 BPM tempo with its anchor at 0:00 gives beat ticks at exactly 0, 0.5, 1.0 …
seconds (whole nanoseconds) over a window, bar ticks every 2 s, and a shifted anchor shifts every tick by the offset.

**Acceptance Scenarios**:

1. **Given** a 120 BPM manual tempo anchored at 0:00, **When** the grid for 0:00–0:10 is computed, **Then** there are 21 beat ticks exactly 500,000,000 ns apart and bar ticks at 0, 2, 4, 6, 8, 10 s.
2. **Given** the same tempo anchored 0.25 s into the timeline, **When** the grid is computed, **Then** every tick is 0.25 s later (modulo the period) and the first bar is at 0.25 s.
3. **Given** no tempo, **When** the timeline row is shown, **Then** no ticks are drawn and the readout says "No tempo".
4. **Given** a 120 BPM tempo on a 20 s timeline drawn 300 points wide, **When** the row lays out, **Then** each beat tick's x position is the time's fraction of the timeline across the track.

### User Story 2 - Hear the position with VoiceOver (Priority: P1)

A blind VJ moves to the grid readout and hears "120 BPM, tap tempo, bar 3 beat 2" (or "detected" for an estimate, or "No
tempo").

**Acceptance Scenarios**:

1. **Given** a manual 120 BPM tempo and the playhead at 4.5 s with the anchor at 0:00, **When** VoiceOver reads the readout, **Then** it says "120 BPM, tap tempo, bar 3 beat 2".
2. **Given** an estimated tempo, **When** read, **Then** the source says "detected".

### Edge Cases

- A very long show at a fast tempo: drawn ticks are decimated to bars or every n-th bar and never exceed the bound.
- The tempo changes (new taps, a new estimate): the next redraw (at most 0.5 s later) shows the new grid.
- Loop: the timeline row shows one pass, so the grid is drawn across one pass; it is not reset at the wrap.
- An estimate with no beat time: the grid has the right spacing and starts at 0:00 (or the last placement).
- A window that starts before the anchor: beats before the anchor are drawn too.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-010-R1**: Given a tempo (BPM, period in whole nanoseconds, anchor time on the show timeline, source manual or estimated) and a time window, the grid MUST return every beat time in the window exactly anchor + k × period (integer nanoseconds), marking every fourth beat from the anchor as a bar.
- **SHOW-010-R2**: The grid MUST return no ticks when there is no tempo, and MUST never return more than 512 ticks for a window; when the drawn spacing would be under 4 points it MUST draw only bars, then every 2nd, 4th, 8th… bar.
- **SHOW-010-R3**: The grid MUST give the bar and beat at a time (bar 1 contains 0:00; beats 1–4) and the nearest beat time.
- **SHOW-010-R4**: The app MUST place the tempo's anchor on the show timeline through the playhead while the show plays, keep the last placement while paused or at Standby, and use 0:00 with no anchor or before any placement.
- **SHOW-010-R5**: The SHOW-007 timeline row MUST draw the ticks over its scrub track at x = inset + (time / duration) × usable width (bars taller than beats) without changing the scrub gesture, and show a readout "Bar B · Beat b · N BPM" or "No tempo" for the displayed time (the scrub preview while dragging, else the playhead), refreshed with the row's existing twice-a-second redraw.
- **SHOW-010-R6**: The readout MUST be a VoiceOver element with the value "N BPM, tap tempo|detected, bar B beat b" or "No tempo".
- **SHOW-010-R7**: No network access, no new UserDefaults key, no stored state, no wall-clock assertions in tests; ShowControl MUST keep building on Linux.

### Key Entities

- **Beat grid tempo**: BPM, period (ns), anchor on the show timeline (ns), source (manual, estimated).
- **Tick**: a time on the show timeline, its beat index from the anchor, whether it starts a bar.
- **Grid position**: bar number and beat in bar at a time.

## Success Criteria *(mandatory)*

- **SHOW-010-S1**: At 120 BPM, consecutive beat ticks are exactly 0.5 s apart (integer nanoseconds, every pair in a 10 s window) and bars exactly 2 s apart; an anchor offset shifts every tick by that offset.
- **SHOW-010-S2**: No tempo gives zero ticks; any window and tempo give at most 512 ticks.
- **SHOW-010-S3**: The timeline row's layout puts each 120 BPM tick at the expected x position (within 0.01 point).
- **SHOW-010-S4**: A UI test (under 30 s) with a seeded 120 BPM tempo sees the grid and its readout on the timeline row.

## Assumptions

- Simulator results prove behavior only; a `{device}` task checks the grid against audible beats on D1.
- Time signatures other than 4/4, snapping, and a grid in the keyframe editor are out of scope.
- The grid is drawn only where the SHOW-007 row is shown (a show with timed cues); without a timeline nothing is shown.
