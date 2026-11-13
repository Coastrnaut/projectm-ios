# Feature Specification: SHOW-011 Tap Tempo

**Feature Branch**: `feature/show-011` (spec directory `027-show-011-tap-tempo`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHOW-011 (Tap tempo) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Let user set manual BPM and
clear override." Acceptance, verbatim: "Four taps establish tempo; reset returns to estimated
state." Dependencies: ANL-005 (integrated); the estimate comes through the ANL-016 event bus
(integrated). Honor the repository constitution and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHOW-011-R1…`, success criteria `SHOW-011-S1…`, tasks `SHOW-011-T01…`. The
requirements of ANL-005 (`specs/021-anl-005-adaptive-beat-tracker/spec.md`) and ANL-016
(`specs/024-anl-016-analysis-event-bus/spec.md`) stay in force; this feature reads their output
and changes neither.

## Baseline: what exists today (audit of 2026-11-13, commit `97e498d`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Tempo estimate | ANL-005's tracker runs inside the ANL-016 pipeline: feature frames carry tempo and confidence (0…1, 0.5 or more is "high"), beat events carry the tempo, the period and the predicted beat's sample position, all stamped on one monotonic clock. | Nothing in the app reads tempo. The only pipeline belongs to the circular spectrum and runs only while that visual is shown; with projectM shown (the default) no tempo is computed. |
| Manual tempo | None. | No way to set a tempo by hand or to clear it. |
| Consumers | None yet. SHOW-003 (beat-quantized cues), SHOW-010 (beat grid), UIX-005 (performance controls), MOD-009 (tempo-synced LFO) and MIDI-010 (MIDI clock) will need one tempo to follow. | No single tempo source that says where its tempo came from. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Where does the app's estimate come from, given that the normalized ring's analysis tap has exactly one reader and only the circular spectrum runs a pipeline today? → A: Whichever visual is shown owns the one analysis. While the circular spectrum is shown, the tempo reads a second subscription on that visual's existing pipeline (a small hook on its analyzer; the analyzer's behavior is unchanged). While projectM is shown, the coordinator runs its own ANL-016 pipeline on the analysis tap. Exactly one pipeline reads the tap at any time, and each runs only while its visual runs, so the tempo analysis stops with pause, background, lock and Stop (PERF-011) like the rest of the presentation, and its estimate is cleared when it stops (SHOW-011-R14). A second tap or a shared app-wide pipeline would change AudioCore or the circular spectrum's ownership, which this row does not need.
- Q: Which taps make a sequence, and what are the limits? → A: The supported range is ANL-005's, 60-200 BPM: an interval below 300 ms is a "too fast" rejection (the tap is ignored, so a double-tap bounce cannot break a sequence); an interval over 1 s up to 2 s is "too slow" and restarts the sequence at that tap; over 2 s is a pause and restarts silently. The tempo is 60 s over the median of the last (up to) 8 intervals: four taps give three intervals, and the median ignores one mistimed tap, which a mean would not (SHOW-011-R2 to R6).
- Q: Does a manual tempo survive leaving the visualizer or relaunching? → A: It survives Stop, source switches, pause and background within a launch (the performer set it on purpose) and is never stored: a relaunch starts with no manual tempo. Nothing about tempo is written to disk (SHOW-011-R16).
- Q: Where does the tempo model live, and how is it tested without real tap timing? → A: A new package `Packages/PerformanceControl` (the roadmap's package for live-performance rows) holds the pure model with no clock of its own (every call takes a monotonic time in nanoseconds), plus a small reader that turns ANL-016 frames and beat events into estimates. Tests pass times explicitly. The app's UI test uses a DEBUG-only launch argument that makes each tap advance a synthetic clock by a fixed interval, because UI taps are not precisely timed (SHOW-011-R11, S6).
- Q: Where do the controls go, and when is Reset offered? → A: In the visualizer controls overlay, in both layouts, as one tempo group: the readout, the Tap button and a Reset tempo button that appears only while a manual tempo is set. They are shown for both visuals; the Tap control's accessibility value is the progress ("2 of 4 taps") or the tempo. Announcements use the system's VoiceOver announcement (SHOW-011-R12, R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set the tempo by tapping (Priority: P1)

A performer watching the visualizer taps a Tap button in time with the music. After the fourth tap
the controls show the tapped tempo in BPM, marked "Manual", and everything that follows a tempo
uses it from then on, with its beats lined up on the last tap.

**Why this priority**: It is the row's observable behavior and the first half of its acceptance.

**Independent Test**: Feed four taps 500 ms apart into the tempo source on a test clock and read
120 BPM, source manual, next beat 500 ms after the last tap; in the app, tap four times and read
"120 BPM, Manual".

**Acceptance Scenarios**:

1. **Given** no manual tempo, **When** the user taps four times 500 ms apart, **Then** the tempo is
   120 BPM from the fourth tap, its source is manual, and its beats fall on the last tap and every
   500 ms after it.
2. **Given** taps 500 ms apart with up to ±20 ms of timing error each, **When** the fourth tap
   arrives, **Then** the tempo is within ±1 BPM of 120.
3. **Given** three taps, **When** no fourth follows, **Then** there is no manual tempo and the
   source shown is unchanged; the Tap control shows how many taps it has (3 of 4).
4. **Given** a manual tempo, **When** the user keeps tapping, **Then** each further tap refines the
   tempo from the recent taps and moves the beats onto the newest tap.

---

### User Story 2 - Clear the override (Priority: P1)

The performer resets the tapped tempo. The readout returns to the detected tempo ("Detected") when
the analysis has a confident estimate, and to "no tempo" (—) when it does not.

**Why this priority**: The second half of the acceptance.

**Independent Test**: Set a manual tempo, supply a confident estimate of 126 BPM, reset, read 126
BPM estimated; repeat without an estimate and read no tempo.

**Acceptance Scenarios**:

1. **Given** a manual tempo and a confident estimate, **When** the user resets, **Then** the tempo
   is the estimate's, its source is estimated and its beats follow the analysis.
2. **Given** a manual tempo and no confident estimate, **When** the user resets, **Then** there is
   no tempo (source none, no BPM, no beats).
3. **Given** a reset, **When** the user taps again, **Then** a new sequence starts from the first
   tap; the old taps do not count.

---

### User Story 3 - Taps that cannot be a tempo (Priority: P2)

Taps too fast or too slow to be a musical tempo, and a long pause between taps, must not produce a
wrong tempo.

**Independent Test**: Taps 250 ms apart (240 BPM) and 1.5 s apart (40 BPM) give feedback and no
tempo; four taps after a 3 s pause start a fresh sequence.

**Acceptance Scenarios**:

1. **Given** a tap sequence, **When** a tap comes faster than the fastest supported tempo
   (200 BPM), **Then** that tap is rejected with "too fast" feedback and the sequence continues
   without it.
2. **Given** a tap sequence, **When** a tap comes slower than the slowest supported tempo (60 BPM)
   but within the pause limit, **Then** it is rejected with "too slow" feedback and a new sequence
   starts at that tap.
3. **Given** two taps, **When** the next tap comes after a long pause, **Then** a new sequence
   starts at that tap with no feedback, and four more taps are needed.
4. **Given** a manual tempo, **When** a rejected or restarting tap arrives, **Then** the manual
   tempo stays until four taps of the new sequence replace it or the user resets.

---

### User Story 4 - Accessible tempo controls (Priority: P2)

A VoiceOver user finds the Tap control, hears the tempo and its source, is told when a tempo is set
or cleared, and can reset with one action. Larger text sizes still show the readout.

**Independent Test**: The UI test reads the Tap control's and the readout's accessibility labels
and values; the announcement texts are unit-tested.

**Acceptance Scenarios**:

1. **Given** the controls, **When** VoiceOver focuses the tempo readout, **Then** it reads the
   tempo and its source ("120 BPM, manual"; "No tempo").
2. **Given** a fourth tap or a reset, **When** it takes effect, **Then** VoiceOver announces the new
   state ("Tempo set to 120 BPM"; "Manual tempo cleared. Detected tempo 126 BPM" or "Manual tempo
   cleared. No tempo").
3. **Given** a rejected tap, **When** it is rejected, **Then** VoiceOver announces "Tap slower" or
   "Tap faster".

---

### User Story 5 - One tempo for later features (Priority: P3)

A later feature (beat grid, quantized cues, tempo-synced modulation, MIDI clock) asks one tempo
source for the current tempo, where it came from, how sure it is and when the next beat falls, on
the same monotonic clock as the analysis.

**Independent Test**: A consumer reads the source's snapshot after taps and after estimates and
gets the documented fields; snapshots encode and decode unchanged.

**Acceptance Scenarios**:

1. **Given** a manual tempo, **When** a consumer asks for the next beat after a time, **Then** it
   gets the first beat of the tapped grid after that time.
2. **Given** an estimated tempo, **When** a consumer asks, **Then** the next beat follows the
   analysis's beat positions.

### Edge Cases

- Taps arrive while no source is running: the visualizer controls exist only while a source runs,
  so taps always happen on the visualizer; the tempo source does not need audio for a manual tempo.
- Stopping the source or leaving the visualizer: the analysis estimate is cleared; a manual tempo
  stays until reset or relaunch.
- The app goes to the background or the device locks: analysis stops with the presentation; a
  manual tempo stays; the estimate is cleared and returns when analysis resumes.
- Two taps at the same instant (bounce): rejected as too fast.
- An estimate disappears while manual: nothing visible changes; the reset then shows "no tempo".
- Switching between projectM and the circular spectrum: the estimate continues from whichever
  analysis runs; the manual tempo is unaffected.
- Relaunch: no manual tempo is restored.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-011-R1**: The tempo source MUST combine a manual override set by taps with the analysis
  estimate and report exactly one current state: manual, estimated or none.
- **SHOW-011-R2**: A manual tempo MUST be established by the fourth accepted tap of a sequence;
  fewer than four taps MUST NOT change the current tempo.
- **SHOW-011-R3**: The manual tempo MUST be 60 seconds divided by the median of the sequence's most
  recent intervals (at most 8), so a single mistimed tap does not move it.
- **SHOW-011-R4**: Each further accepted tap MUST refine the manual tempo by the same rule and move
  its beat phase to that tap.
- **SHOW-011-R5**: Supported tempos MUST be 60 to 200 BPM (ANL-005's range). An interval shorter
  than 300 ms MUST be rejected as too fast (the tap is ignored); an interval longer than 1 s and at
  most 2 s MUST be rejected as too slow and start a new sequence at that tap.
- **SHOW-011-R6**: An interval longer than 2 s MUST start a new sequence at that tap without
  feedback.
- **SHOW-011-R7**: The manual tempo's beats MUST fall on the last accepted tap and every period after
  it.
- **SHOW-011-R8**: Reset MUST clear the manual tempo and the tap sequence; the state MUST then be
  estimated when a confident estimate exists and none otherwise.
- **SHOW-011-R9**: An estimate MUST count only while its confidence is at least 0.5 (ANL-005's
  "high"); its beats MUST follow the analysis's most recent beat position and its tempo.
- **SHOW-011-R10**: The tempo source MUST expose one read API: tempo in BPM (absent for none),
  source, confidence (1 for manual, the estimate's for estimated, 0 for none), beat period, and the
  next beat at or after a given time on the monotonic clock the analysis uses.
- **SHOW-011-R11**: The tempo source MUST take every time as an argument (no clock of its own), so
  results depend only on the inputs; its snapshot MUST be encodable and decodable unchanged.
- **SHOW-011-R12**: The visualizer controls MUST offer a Tap control, a tempo readout ("120 BPM" with
  "Manual" or "Detected"; "—" for none) and a Reset tempo action shown while a manual tempo is set.
- **SHOW-011-R13**: The Tap control and readout MUST have accessibility labels and values naming
  the tempo and source; setting, clearing and rejected taps MUST be announced; the readout MUST
  scale with Dynamic Type.
- **SHOW-011-R14**: The app MUST obtain the estimate from an ANL-016 pipeline while a visual is
  running; that analysis MUST stop when the visual pauses, the app cannot present (PERF-011) or the
  source stops, and the estimate MUST be cleared when it stops.
- **SHOW-011-R15**: No tempo value MUST reach projectM (Constitution VIII, ADR-0008 decision 5).
- **SHOW-011-R16**: The manual tempo MUST NOT be stored; a relaunch starts without one.
- **SHOW-011-R17**: Using the tempo controls MUST restart the controls' auto-hide delay like every
  other control.

### Key Entities

- **Tap sequence**: the accepted tap times of the current attempt (at most 9 kept), their intervals.
- **Manual tempo**: BPM, period and the anchor tap; exists from the fourth tap until reset.
- **Tempo estimate**: BPM, confidence and the most recent beat time from the analysis.
- **Tempo snapshot**: source, BPM, confidence, period, anchor beat; what consumers read.
- **Tap outcome**: what a tap did (counting n of 4, established, refined, too fast, too slow,
  restarted after a pause), for feedback.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-011-S1**: Four taps 500 ms apart give 120 BPM exactly, manual, from the fourth tap; with
  ±20 ms jitter the tempo is within ±1 BPM of 120.
- **SHOW-011-S2**: Three taps never produce a manual tempo; a pause over 2 s always restarts the
  count.
- **SHOW-011-S3**: Taps outside 60-200 BPM never produce a tempo outside 60-200 BPM.
- **SHOW-011-S4**: After reset the state equals the estimate's (with a confident estimate) or none
  (without), in 100% of the test cases.
- **SHOW-011-S5**: A consumer's next beat after a manual tempo is the last tap plus a whole number
  of periods, within 1 ms.
- **SHOW-011-S6**: In the app, four taps and a reset show "Manual" then leave it, in one UI test of
  under 30 s; each unit test runs in about a second or less, the package suite in under a minute
  (owner rule 7).

## Hand-off to SHOW-003, SHOW-010, UIX-005, MOD-009 and MIDI-010

The tempo source is the one tempo these rows follow: they read its snapshot (BPM, source, period,
next beat) and never re-derive tempo from the analysis themselves. MIDI-010 can become another
override kind beside manual without changing readers. UIX-005 may move the Tap control into its
performance layout; the control's identifiers stay.

## Assumptions

- The controls overlay is the place for the Tap control until UIX-005 designs performance
  controls.
- A single tap tempo for the whole app (no per-preset tempo).
- The estimate's confidence threshold (0.5) is ANL-005's "high"; ANL-006's named confidence states
  may refine it later.
- No audio, network or device access beyond what the visualizer already uses.
