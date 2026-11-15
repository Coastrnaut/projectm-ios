# Feature Specification: MED-012 Countdown Overlay

**Feature Branch**: `feature/med-012` (spec directory `265-med-012-countdown-overlay`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-012 (Countdown overlay) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Render a timer controlled by
scene or manual trigger." Acceptance, verbatim: "Countdown reaches zero once and stops without
negative values." Priority P2, size M, depends on MED-009 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `MED-012-R1…`, success criteria
`MED-012-S1…`, tasks `MED-012-T01…`. Other features are cited by their own IDs: MED-009 (text
layer), MED-010 (logo overlay), MED-011 (clock overlay, the pattern this row follows), SHOW-001
(cue list), SHOW-002 (timed advance), SHOW-007 (transport), SCN-001 (scene format), ACC-004
(announcer), FILE-005 (library backup), FILE-011 (local data erase), REC-007 (recording countdown).

## Baseline: what exists today (audit of 2026-11-14, commit `b4f8c249`)

The row's gap status is "Gap candidate". The audit confirms the gap: nothing draws a countdown over
the picture. REC-007's "recording countdown" is a pre-roll before a recording starts, shown as device
chrome only; it is not content and has no scene or cue trigger.

| Area | Behaviour today | What this row reuses or adds |
|---|---|---|
| Clock overlay (MED-011) | A versioned setting (`settings.clock.overlay`), a formatter, a "report only changed strings" helper, a coordinator that attaches a MED-009 text layer named "clock" as the top entry of every compositor visual (Photo, Video, Camera, Text), whole-second ticks only while shown, a Settings section, a DEBUG fixed-clock fixture and probe. | The countdown is the same kind of overlay: a second text layer above the clock, fed a new string only when the shown second changes. The change-reporting helper, the stored-value decoding and the layer attachment are shared, not copied. |
| Text layer (MED-009) | Rasterizes a `TextOverlaySpec` only when the spec changes; CMP-013 reuses the picture in between. | Unchanged; drawn with the same style model. |
| Show cues (SHOW-001) | A cue shows a stored scene; applying it sets the scene's look. | A scene may carry a countdown duration; applying that scene through a cue starts the countdown. |
| Scene format (SCN-001) | Unknown top-level fields are kept verbatim (`extra`); MED-006/007/010 add optional fields without a version change. | One optional top-level field, `countdown`. |
| Timed advance (SHOW-002), transport (SHOW-007) | Monotonic clocks drive dwell and position. | Same rule: the countdown runs on a monotonic clock, never wall time. |

## Clarifications

### Session 2026-11-14 (speckit-specify, speckit-clarify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: What time does the countdown use? → A: A monotonic clock that keeps counting while the device
  sleeps (the system's continuous clock), never the wall clock, so changing the device's time or
  time zone never moves it. Tests inject a clock they advance by hand.
- Q: What durations are allowed? → A: 1 second to 99 minutes (5,940 s), whole seconds. Default
  5:00.
- Q: How is the remaining time shown? → A: Whole seconds rounded up, so a five-minute countdown shows
  "05:00" at its start and "00:00" only when it has finished. Below an hour: "mm:ss"; from an hour up:
  "h:mm:ss" ("1:39:00"). Never negative: after zero it shows "00:00" and stays there.
- Q: What happens at zero? → A: It holds "00:00" (no flashing: conservative under the flash-safety
  rules) and a "Countdown finished" VoiceOver announcement is made once, through the shared
  announcer. The finished event fires exactly once per run, even when updates skip past zero or the
  app returns from the background after zero.
- Q: Pause and resume? → A: Yes: Start, Pause (keeps the remaining time) and Reset (back to the full
  duration, stopped, re-armed). Start on a finished countdown restarts it from the full duration.
- Q: Where are the manual controls? → A: In a "Countdown" section of Settings, after the Clock
  section: Show Countdown, Minutes and Seconds steppers, Start/Pause/Resume, Reset, position and
  alignment. Not in the visualizer's control bar in this row (that bar is shared and crowded); the
  countdown keeps running when Settings closes.
- Q: How does a scene or cue start it? → A: A scene may carry an optional `countdown` field with a
  duration in whole seconds. When a show cue applies such a scene, the countdown restarts with that
  duration. Restoring the last scene at launch or reopening it does not start a countdown (only a
  performer's cue does). A malformed field reads as absent and is kept verbatim.
- Q: How is that field written? → A: Settings › Countdown › "Start From New Cues": while on, scenes
  added to the show as cues record the current duration, so their cue starts the countdown. Scenes
  imported with the field keep it.
- Q: Does a cue turn the overlay on? → A: No. A cue starts the countdown; Show Countdown stays the
  performer's choice (the footer says so). A cue never changes a saved preference.
- Q: Is the countdown content or chrome? → A: Content, like the clock: a layer of the compositor
  visuals' stacks, above the clock, so it reaches captures, recordings and the external display.
  projectM and the native visuals have no compositor and show none.
- Q: Default placement and look? → A: Top, centre, 8 % of the picture height, white bold Menlo
  (fixed-width digits) with the default outline; off by default.
- Q: Is the running state saved? → A: No. The settings (shown, duration, cue recording, placement)
  are saved; a running countdown is session state and starts stopped at the full duration after a
  relaunch.

- Q: What is shown when Show Countdown is on but the countdown has not started? → A: The full
  duration ("05:00"), stopped. A stopped, paused or finished countdown still shows its value.
- Q: What happens when the duration is changed while it runs? → A: The countdown resets: stopped at
  the new duration, re-armed (a change of the length is a new run, never a jump mid-run).
- Q: What step do the duration steppers use? → A: Minutes 0–99 in steps of 1 and seconds 0–59 in
  steps of 1; a total of 0 is raised to 1 s and anything above 99:00 is lowered to 99:00.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run a countdown by hand (Priority: P1)

A performer sets five minutes, turns on Show Countdown, taps Start, and sees "05:00" count down over
the Photo, Video, Camera or Text visual; at zero it shows "00:00" and stops.

**Why this priority**: it is the row's observable behaviour and its acceptance.

**Independent Test**: with an injected clock, the strings at given elapsed times are exact, zero is
reached once, and nothing below zero is ever shown.

**Acceptance Scenarios**:

1. **Given** Show Countdown is off (the default), **When** a compositor visual is shown, **Then** no countdown is drawn.
2. **Given** 5:00 is set and shown, **When** Start is tapped, **Then** "05:00" is drawn, "04:59" one second later and "04:00" a minute later.
3. **Given** a running countdown, **When** its time passes zero (even by an hour), **Then** "00:00" is drawn, the finished event fires once, and the text is not redrawn again.
4. **Given** a running countdown, **When** Pause is tapped and time passes, **Then** the remaining time stays; **When** Start is tapped, **Then** it continues from there.
5. **Given** a finished countdown, **When** Reset is tapped, **Then** it shows the full duration, stopped, and a later run fires its finished event again once.

### User Story 2 - Start it from a cue (Priority: P2)

A performer adds a scene to the show with "Start From New Cues" on; going to that cue starts the
countdown with the recorded duration.

**Independent Test**: a scene with the field round-trips through the scene format; applying it starts
the countdown with its duration; a scene without it leaves the countdown alone.

**Acceptance Scenarios**:

1. **Given** a scene with a 90-second countdown, **When** its cue is applied, **Then** the countdown restarts at "01:30" and runs.
2. **Given** a scene without the field or with a malformed one, **When** its cue is applied, **Then** the countdown is unchanged.
3. **Given** a scene with the field, **When** it is saved and read back, **Then** the duration is the same.

### Edge Cases

- Frames or ticks skip past zero, or the app is in the background at zero: the next update shows "00:00" and fires the finished event once.
- Repeated updates after zero fire nothing and draw nothing new.
- The duration changes while running: the countdown resets to the new duration, stopped.
- Durations below 1 s or above 99 min are clamped (settings) or read as absent (scene field).
- The device's wall clock or time zone changes during a run: the countdown is unaffected.
- A damaged or newer stored setting reads as the defaults (off); a damaged one is removed.
- projectM or a native visual is shown: no countdown is drawn; it keeps running and shows when a compositor visual returns.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-012-R1**: The app MUST offer a countdown overlay drawn as text over the compositor visuals (Photo, Video, Camera, Text), off by default.
- **MED-012-R2**: The countdown MUST run on an injected monotonic clock (never the wall clock); remaining = max(0, duration − elapsed running time).
- **MED-012-R3**: Display: whole seconds rounded up, "mm:ss" below an hour and "h:mm:ss" from an hour up; never negative; "00:00" held after zero.
- **MED-012-R4**: The finished event MUST fire exactly once per run (across skipped updates, large jumps and repeated updates after zero); Reset and a new Start re-arm it. At zero a "Countdown finished" announcement is made through the shared announcer; nothing flashes.
- **MED-012-R5**: Manual control: Start (or Resume), Pause and Reset; duration 1 s to 99 min.
- **MED-012-R6**: The countdown is drawn by the MED-009 text layer, with the MED-011 change-only update path: the layer is given a new string only when the shown second changes, so it redraws at most once per second while running and never after zero.
- **MED-012-R7**: The countdown is a layer of the compositor stack, above the clock, so it appears in captures, recordings and on the external display.
- **MED-012-R8**: A scene MAY carry an optional `countdown` field (whole seconds, 1…5,940). Applying a scene with it through a show cue restarts the countdown with that duration; launch restore and reopen do not. A malformed field reads as absent and is kept verbatim; no scene version change.
- **MED-012-R9**: Settings › Countdown: Show Countdown, Minutes, Seconds, Start/Pause/Resume, Reset, Start From New Cues, Position and Alignment, with a note on which visuals show it.
- **MED-012-R10**: The settings are one versioned value (`settings.countdown.overlay`): missing → defaults; damaged → defaults and removed; newer → defaults, left untouched. A backed-up preference (FILE-005), erased with Settings (FILE-011), removed by the UI-test reset. The running state is not saved.
- **MED-012-R11**: Nothing leaves the device; no new permission.

### Key Entities

- **Countdown**: a duration, the running time accumulated so far, whether it is running, and whether its finished event has fired.
- **Countdown settings**: shown or not, the duration, whether new cues record it, and the text style.
- **Scene countdown**: the optional duration a scene carries for its cue.

## Success Criteria *(mandatory)*

- **MED-012-S1**: A 5:00 countdown shows exactly "05:00", "04:59", "04:00", "00:01" and "00:00" at 0, 1, 60, 299.5 and 300 s; a 99-minute one shows "1:39:00" (roadmap acceptance).
- **MED-012-S2**: Over an overrun of up to 10 hours past zero, no value below zero is ever shown and the finished event fires exactly once, including after a single large jump.
- **MED-012-S3**: While running, the layer receives one new string per second; after zero it receives none.
- **MED-012-S4**: A scene's countdown survives a save and load unchanged; a cue applying it starts the countdown with that duration.
- **MED-012-S5**: Settings survive a relaunch; a short UI test turns the countdown on, starts it and sees it drawn with a fixed clock.

## Assumptions

- The device's monotonic clock is trusted.
- One countdown at a time; several timers are out of scope.
