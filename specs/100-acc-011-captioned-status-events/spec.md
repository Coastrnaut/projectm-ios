# Feature Specification: ACC-011 Captioned Status Events

**Feature Branch**: `feature/acc-011` (spec directory `100-acc-011-captioned-status-events`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row ACC-011 (docs/FEATURE_ROADMAP_AUTONOMOUS.md line 459). Observable behavior,
verbatim: "Provide accessible textual feedback for capture and recording state." P0, size M, depends on
UIX-001 (integrated). Acceptance, verbatim: "Every state transition has a visible text label and
accessibility announcement." Verification: accessibility unit and UI tests, then a VoiceOver pass on a
device in the last stage.

Identifiers carry the roadmap ID: requirements `ACC-011-R1…`, success criteria `ACC-011-S1…`, transitions
`ACC-011-X1…`, tasks `ACC-011-T01…`. Other features are cited by their own IDs: FR-010/FR-013/FR-015/FR-042/
FR-070 (feature 001 states, messages, indicator, accessibility), ACC-004 (the shared announcer, its gate
and its user-caused rule), ACC-006 (wrapping status rows at accessibility sizes), ACC-001 (MotionPolicy),
AUD-007 (route indicator), AUD-012 (source switch), AUD-014 (interruptions), AUD-015 (background notice),
REC-001 (Save Frame), REC-003 (Record), REC-012 (ready panels and share), REC-015 (disk guard), FILE-013
(permission notices), CAM-001/CAM-002/CAM-012 (camera notices and badge), OSC-007 (listener badge),
OUT-010/SHOW-014 (blackout), SCN-012 (repair sheet), PERF-010 (recovery offer).

## Baseline: what exists today (audit of 2026-11-14, commit `82d23496`)

"Capture and recording state" covers the audio source (the capture), the visual capture features (Save
Frame, Record, their result panels and sharing), and the status indicators that sit next to them on the
visualizer (camera, OSC listener, output blackout, background notice, recovery offer, repair sheet,
output route).

| # | Status | Visible text today | Announced today | Posted by |
|---|---|---|---|---|
| B1 | Source state (waiting, active, silent, no audio, paused, interrupted, stopped, ended by system) | indicator "<mode> · <state>" (FR-042), banner with FR-015 message | every change (FR-070) | direct `UIAccessibility.post` (`SourceStatusIndicator.announce`), not rate-limited |
| B2 | "Switching source…" (AUD-012) | indicator | yes, same path as B1 | direct |
| B3 | In-App Playback on hold (AUD-014) | banner detail | yes (status + explanation) | direct, a second post next to B1's for the same change |
| B4 | Background notice (AUD-015) | notice view | yes, once | direct, from the view's task |
| B5 | Output route change (AUD-007) | route explanation, 4 s | yes when worded | direct (RouteCoordinator default) |
| B6 | Save Frame refusal, failure, "Frame saved." (REC-001) | notice | **no** | — |
| B7 | "Frame ready" / "Recording ready" panels (REC-012) | panel title | **no** | — |
| B8 | Share result notice (REC-012) | notice | **no** | — |
| B9 | Recording started / stopped (REC-003) | "REC m:ss" / "Finishing…" indicator | yes | ACC-004 announcer, kind recording |
| B10 | Recording refusals, automatic stops (REC-003, REC-015), failures, "Recording saved." | notice | yes | announcer, kind recording |
| B11 | Camera notices: denied, restricted (FILE-013), unavailable, paused by system (CAM-001/002) | permission notice | yes | direct |
| B12 | Camera on / Front camera on (CAM-012/002) | badge | **no** | — |
| B13 | Camera off (user's Stop camera) | **none** (the badge goes) | yes | direct |
| B14 | OSC listening on port N (OSC-007) | badge | **no** | — |
| B15 | OSC off (badge Stop) | **none** (the badge goes) | yes | direct, from the view |
| B16 | Output blacked out / Restoring output (OUT-010) | badge | yes | announcer, kind output |
| B17 | Output restored | **none** (the badge goes) | yes | announcer, kind output |
| B18 | Recovery offer shown (PERF-010) | card | yes, once | direct, from the view |
| B19 | "Last scene reopened." (PERF-010) | **none** (the card goes) | yes | direct |
| B20 | Repair report shown (SCN-012) | sheet | yes | direct (coordinator default) |

Gaps: five statuses are not announced (B6, B7, B8, B12, B14); four end states have no visible text (B13,
B15, B17, B19); eleven announcements bypass ACC-004's rate rule (B1-B5, B11, B13, B15, B18-B20), and B1
and B3 can speak twice for one change.

## Clarifications

### Session 2026-11-14

Answered under owner delegation (rule 4, recommended option each time).

- Q: Are automatic source changes between active, silent and no audio still announced, or only
  user-caused ones? → A: Still announced (FR-070 already requires it), now through the announcer's
  `source` kind, so a burst within 1 s speaks the first and the latest state and an identical repeat
  within 2 s is dropped. ACC-011-R4 lists this under "required by an earlier requirement".
- Q: How long does a status caption stay, where does it sit and how does it go? → A: 4 s, in the
  visualizer's top status stack under the source indicator; a newer caption replaces it; it appears and
  goes with no animation (nothing to route through MotionPolicy), wraps at accessibility sizes, and is a
  static text with identifier `statusCaption`.
- Q: When is the OSC listener announced? → A: "OSC listening on port N" when the badge appears (nil → a
  port) while the app is active — a network listener opening is privacy-relevant even at launch; "OSC
  off" only for the user's Stop on the badge (with a caption), never for a transient close.
- Q: What happens to system changes while the app is in the background or locked? → A: They are not
  spoken or captioned (the router checks the app is active); on return AUD-015's background notice
  summarizes them, and the indicator shows the current state. The background notice itself is announced
  (kind `background`).
- Q: How is completeness enforced so a new state cannot ship silent? → A: One catalog type maps every
  status enum to a row with exhaustive `switch`es (no `default:`), so a new case fails to compile until
  it has a row; a unit test enumerates each enum's cases (`CaseIterable`, plus an exhaustive list for the
  two enums with associated values) and asserts non-empty visible text and announcement; a script check
  (`scripts/check_status_events.py`, run by `test_scripts.py`) fails on any direct
  `UIAccessibility.post`/`AccessibilityNotification` in the capture and recording files (ACC-011-S2).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Hear every capture and recording change, without spam (Priority: P1)

A VoiceOver user starts a source, records, saves a frame and loses the source to the system. Each change is
spoken once, in the words the screen shows; quick bursts (waiting → active within a second) end on the
latest state rather than a queue of stale ones.

**Why this priority**: it is the roadmap's acceptance; a blind performer cannot see the indicator.

**Independent Test**: drive the fake source and the recording through their states and read the last
announcement; a unit test walks the transition table with a fake clock.

**Acceptance Scenarios**:

1. **Given** In-App Playback is waiting, **When** audio arrives, **Then** "In-App Playback · Active audio"
   is spoken and shown.
2. **Given** a source is active, **When** the system interrupts it, **Then** the interruption is spoken
   although the user did not cause it.
3. **Given** waiting changes to active and then to silent within one second, **Then** two announcements are
   spoken: the first state at once and the latest one when the window closes.
4. **Given** the user taps Save Frame, **When** the frame is offered, **Then** "Frame ready" is spoken.

### User Story 2 - See every change as text (Priority: P1)

A deaf or hard-of-hearing user, or anyone not looking at the icons, sees a text caption for each change,
including changes whose indicator disappears (camera off, OSC off, output restored, last scene reopened).

**Independent Test**: stop the camera, restore the output; a short caption appears with the text.

**Acceptance Scenarios**:

1. **Given** the output is blacked out, **When** the user restores it, **Then** "Output restored" appears as
   a caption for a few seconds.
2. **Given** a state is shown only by colour or an icon, **Then** a text label is added next to it.

### User Story 3 - A new state cannot ship silent (Priority: P1)

A developer adds a capture or recording state. A test fails until the state has a row in the table with
visible text and an announcement.

**Independent Test**: the completeness test enumerates every case of the source-state, recording-state,
recording stop/refusal, camera-state and blackout-phase enums and requires a row.

### Edge Cases

- Identical text within 2 s (ACC-004 rule) is dropped, e.g. the state and hold changes of one interruption.
- VoiceOver off: the system drops announcements; captions still show.
- The background: changes while the app is away are neither spoken nor captioned; AUD-015's notice
  summarizes them on return.
- Reduce Motion: captions appear and go without animation or through MotionPolicy.
- Accessibility text sizes: captions wrap (ACC-006).
- The iOS camera permission prompt is system UI: VoiceOver reads it itself; it gets no app announcement.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-011-R1**: The app MUST keep one transition table (contract C1) listing, for every capture and
  recording status in the baseline, the visible text, the announcement text, the announcement kind, the
  cause (user or system) and whether the end state needs a caption.
- **ACC-011-R2**: Every row MUST have non-empty visible text and a non-empty announcement, except rows the
  table marks as system-presented (only the camera permission prompt).
- **ACC-011-R3**: Every capture and recording announcement MUST go through ACC-004's announcer and its gate
  (per-kind window 1.0 s, identical text dropped within 2.0 s). Direct posts for B1-B5, B11, B13, B15 and
  B18-B20 MUST move onto it. New kinds MAY be added.
- **ACC-011-R4 (announcement rule)**: a change is announced when the user caused it, or when it is
  safety-relevant, or when an earlier requirement already announces it (FR-070, AUD-014, AUD-015, AUD-007,
  CAM-001, PERF-010, SCN-012). Safety-relevant system changes include: capture ended by the system,
  interruption, source failure, permission denied or lost, camera paused by the system, any automatic
  recording stop (storage, limit, background, size, visual, writer failure), and a network listener opening.
  Not announced: automatic preset changes (ACC-004-R6), elapsed-time ticks, camera starting → running, and
  the blackout's internal fade phases.
- **ACC-011-R5**: One source change MUST produce one announcement: when In-App Playback goes on hold, the
  hold text (status plus explanation) replaces the plain status text.
- **ACC-011-R6**: Save Frame notices, "Frame ready", "Recording ready", share notices, "Camera on" /
  "Front camera on" and "OSC listening on port N" MUST be announced (gaps B6-B8, B12, B14).
- **ACC-011-R7**: End states with no persistent text (camera off, OSC off, output restored, last scene
  reopened) MUST show a transient status caption with the row's visible text for 4 s in the top status
  stack, replaced by a newer caption, with no animation, wrapping at accessibility sizes, exposed to
  accessibility as static text.
- **ACC-011-R10**: While the app is not active, system-caused rows MUST NOT be spoken or captioned.
- **ACC-011-R11**: A script check MUST fail on any direct announcement post in the capture and recording
  files listed in contract C2.
- **ACC-011-R8**: Contract-pinned UI text (UIStrings and its contracts) MUST NOT change.
- **ACC-011-R9**: DEBUG builds MUST expose the announcer's last text (ACC-004 `announcementProbe`) and the
  caption (`statusCaption`) to UI tests.

### Key Entities

- **StatusEvent**: one row: kind, visible text, announcement, cause, caption flag.
- **Transition table**: the catalog of rows, keyed by the status enums.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-011-S1**: 100% of table rows have visible text and an announcement (system-presented rows excepted),
  checked by a unit test over every enum case.
- **ACC-011-S2**: Zero direct announcement posts remain for capture and recording statuses (code search).
- **ACC-011-S3**: A burst of three changes within one second produces at most two announcements, ending on
  the latest state (unit test, fake clock).
- **ACC-011-S4**: The UI test sees the source, hold, blackout and caption transitions in under 30 s.
- **ACC-011-S5**: A VoiceOver user on D1 hears each transition of the quickstart once (device task, last).

## Assumptions

- Scope is the visualizer's capture and recording statuses in the baseline; preset, cue, favorite and
  playback-transport announcements (ACC-004, PlayQueue, TransportBar) are unchanged.
- Captions reuse existing texts; no new contract-pinned strings are added to UIStrings.
- Simulator results are not device evidence; the VoiceOver pass is a `{device}` task left open.
- ACC-004 spoke "Output restored" when the restore was requested; it is now spoken when the output is
  live again, with "Restoring output" while the restore waits or fades in (research ACC-011-D3). ACC-004's
  texts are unchanged.
