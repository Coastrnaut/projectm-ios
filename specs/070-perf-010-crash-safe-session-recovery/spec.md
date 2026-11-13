# Feature Specification: PERF-010 Crash-Safe Session Recovery

**Feature Branch**: `feature/perf-010` (spec directory `070-perf-010-crash-safe-session-recovery`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement PERF-010 (Crash-safe session recovery) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer reopening last locally saved
scene after abnormal exit." Acceptance, verbatim: "Simulated crash never reopens camera or network
listener without consent." P0, effort M, depends on SCN-002 (scene autosave)."

Identifiers in this feature carry the roadmap ID: requirements `PERF-010-R1…`, success criteria
`PERF-010-S1…`, tasks `PERF-010-T01…`. Other features' IDs are cited as they are: SCN-002 (scene
autosave and launch restore; ADR-0028 amendment), CAM-001/CAM-012 (camera, session only; "Camera on"
badge), OSC-001/OSC-007/OSC-009 (OSC receiver, its persisted toggle and listener badge; ADR-0008 OSC
ruling), OUT-001/OUT-010 (external display, blackout), REC-003/REC-012 (recording and share leftovers).

## Baseline: what starts by itself at launch today (audit of 2026-11-13, commit `9b012a2`)

The app cannot tell a clean exit from an abnormal one: every launch is handled the same way.

| Area | After a normal exit | After a crash or kill | Gap for this row |
|---|---|---|---|
| Audio source | Nothing: the notice (first launch) or the source chooser; no source starts until the user picks one (FR-002). | Same. | None. |
| Camera | Never: Camera is session only (CAM-001-R11), the stored visual is the one chosen before Camera, and the camera runs only while the user-chosen Camera visual is shown. | Same. | None in behavior; needs a regression test after an abnormal exit. |
| OSC listener | **Opens at launch** when the stored toggle `settings.osc.enabled` is on (OSC-001-R15: persisted), already on the chooser (OSC-007-R2). | **Same: the listener reopens with no new consent.** | **Violates this row's acceptance.** |
| Scene | SCN-002 silently restores the last committed scene's values (bar count, orientation, spacing, glow, text, bindings) over the settings; the visual choice comes from the stored setting. | Same, silently. | The row asks for an *offer* after an abnormal exit. |
| External display | Shows the visualization only while the visualizer is shown (OUT-001); nothing is persisted, blackout starts live. | Same. | None. |
| Recording | Never starts by itself; leftover temporary files are deleted by REC-003-R13 / REC-012-R6. | Same. | None. |
| Memory, blackout, presets | No session state persisted beyond settings, favorites and the last preset. | Same. | None. |
| Diagnostics | Nothing records an abnormal exit. MetricKit is not used. | — | A diagnostics event without user data. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: After an abnormal exit, is the OSC toggle's stored value cleared, or is the listener only
  suspended for this launch while the stored value stays on? → A: Cleared: the stored
  `settings.osc.enabled` is set to off before the receiver is created. A one-shot suspension would
  leave the stored value on, so the next normal launch would reopen the listener without new consent.
  The port is kept. This overrides OSC-001-R15's persistence after an abnormal exit only; recorded in
  an ADR (PERF-010-R2).
- Q: Should the last scene be restored silently after an abnormal exit (with sensors and network
  off), or only after the user accepts an offer? → A: Only after an offer (the row's own wording,
  and the conservative reading: the scene may be what crashed). Until the user answers, the fresh
  scene (scene settings at defaults) is shown (PERF-010-R4, R5).
- Q: How is an abnormal exit detected? → A: A "session open" flag in the app's own preferences, set
  at launch and on return to the foreground, cleared on the background transition and on terminate.
  No timestamps (no required-reason file timestamp APIs), no MetricKit in the decision, no crash
  reporter, no private API. A crash in the background is not detected (accepted limitation)
  (PERF-010-R1).
- Q: What is the crash-loop window? → A: N = 2 sessions: an abnormal exit in the session where the
  user tapped Reopen or in the next one offers Start fresh only; after two sessions without an
  abnormal exit the counter is cleared (PERF-010-R9).
- Q: How do existing UI tests, which relaunch the app after `terminate()` without a background
  transition, avoid the offer? → A: In DEBUG builds a launch with any `-uitest…` or `-autostart`
  argument, a unit-test host, or a `PROJECTM_AUTORUN` automation run treats the launch as clean
  (the marker is still kept) unless `-uitestSessionRecovery` is passed; `-uitestResetNotice` also
  clears the recovery state. Release builds always decide (PERF-010-R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A crash never turns a sensor or the network back on by itself (Priority: P1)

A performer has the OSC receiver on (and perhaps the Camera visual showing) when the app crashes or
is killed. On the next launch nothing that listens to the network or uses a sensor is running: the
OSC listener is closed and the OSC toggle shows off, and the camera is off. The performer turns
each back on themselves when they want it.

**Why this priority**: This is the row's acceptance: "Simulated crash never reopens camera or network
listener without consent."

**Independent Test**: Turn OSC on and choose Camera, kill the app without sending it to the
background, relaunch: no OSC badge, the OSC status says Off, no "Camera on" badge and no camera
picture; turning OSC on in Settings listens again.

**Acceptance Scenarios**:

1. **Given** OSC was listening when the app was killed, **When** the app relaunches, **Then** no
   listener is opened, the badge is absent, Settings shows the toggle off, and the stored toggle
   stays off until the user turns it on.
2. **Given** the Camera visual was shown when the app was killed, **When** the app relaunches,
   **Then** the camera is not started, the "Camera on" badge is absent, and the visual is the one
   chosen before Camera.
3. **Given** the user accepts the recovery offer, **When** the scene reopens, **Then** OSC and the
   camera are still off until the user turns them on.

### User Story 2 - I am offered my last scene after a crash (Priority: P1)

After an abnormal exit the app does not silently bring back what was showing (which may be what
crashed it). A small, non-blocking card says the app closed unexpectedly and offers **Reopen last
scene** or **Start fresh**. Until the user answers, the app shows the fresh scene, and everything
else (choosing a source, Settings) works.

**Why this priority**: The row's observable behavior: "Offer reopening last locally saved scene after
abnormal exit."

**Independent Test**: Commit a scene (Circular Spectrum, 16 bars), kill the app, relaunch: the offer
is shown and the fresh scene (projectM) is shown; Reopen brings back Circular Spectrum with 16 bars;
in another run Start fresh keeps projectM and dismisses the offer.

**Acceptance Scenarios**:

1. **Given** a committed scene and an abnormal exit, **When** the app relaunches, **Then** the offer
   is shown with Reopen and Start fresh, and the shown scene is the fresh one.
2. **Given** the offer, **When** the user taps Reopen, **Then** the last committed non-sensor scene
   (its visual and values) is applied and the offer goes away.
3. **Given** the offer, **When** the user taps Start fresh, **Then** the fresh scene stays, the offer
   goes away, and the next edit replaces the old committed scene.
4. **Given** the app went to the background (or terminated normally) before it ended, **When** it
   relaunches, **Then** no offer is shown and SCN-002's silent restore runs as today.

### User Story 3 - A scene that keeps crashing is not offered again (Priority: P2)

If the app crashes again shortly after the user reopened a scene, it does not offer that scene again:
the card says the app closed unexpectedly again and offers Start fresh only.

**Why this priority**: Prevents a crash loop where the user keeps reopening a scene that crashes.

**Independent Test**: Reopen a scene, kill the app, relaunch: the offer has no Reopen.

**Acceptance Scenarios**:

1. **Given** the user reopened a scene, **When** the app exits abnormally in that session or the next
   one, **Then** the next launch offers Start fresh only.
2. **Given** a reopened scene survived two sessions, **When** a later abnormal exit happens, **Then**
   Reopen is offered again.

### Edge Cases

- No committed scene exists (fresh install, or SCN-002's folder unavailable): after an abnormal exit
  the card still says the app closed unexpectedly (with Start fresh only), and OSC is still off.
- The app is killed again while the offer is still unanswered: the next launch offers the same scene
  again (the held visual survives the kill).
- The system ends the app while it is in the background (memory, an update): this is not an abnormal
  exit; the background transition already ended the session.
- The app crashes while running in the background (System/App Capture keeps running there): not
  detected as abnormal (limitation, recorded in Assumptions).
- OSC was off at the crash: nothing about OSC is said.
- The user picks a source or opens Settings while the offer is shown: everything works; the offer
  stays until answered or until the user leaves it (it never blocks).
- UI tests and device automation relaunch the app constantly without a background transition: the
  DEBUG test harness suppresses the decision unless a test asks for it (it must not change existing
  suites).

## Requirements *(mandatory)*

### Functional Requirements

- **PERF-010-R1 Session marker**: The app records that a session is open when it launches or returns
  to the foreground and records that it ended cleanly when it goes to the background or terminates.
  A launch that finds the session still open is an abnormal exit. No timestamps, no private
  interfaces, no crash reporter, no network.
- **PERF-010-R2 No network listener without consent**: After an abnormal exit the OSC listener is not
  opened at launch, the stored OSC toggle is turned off, and only the user turning it on again opens
  it. After a normal exit OSC behaves as today (OSC-001-R15).
- **PERF-010-R3 No camera without consent**: After an abnormal exit (and after accepting the offer)
  the camera is never started; only choosing Camera starts it (CAM-001).
- **PERF-010-R4 Offer**: After an abnormal exit the app shows a non-blocking card on the chooser and
  the visualizer: "projectM closed unexpectedly." with **Reopen last scene** and **Start fresh** (and a
  line "OSC was turned off." when it had been on). It is announced to VoiceOver.
- **PERF-010-R5 Fresh scene while undecided**: While the offer is unanswered (and after Start fresh)
  the scene settings are at their defaults (projectM, 64 bars, vertical, Narrow spacing, glow off at
  default values); the committed scene is not applied. Photos, videos, text, presets, favorites and
  other settings are not touched.
- **PERF-010-R6 Reopen**: Reopen applies the last committed scene (SCN-002's restored values) and the
  visual that was stored at the abnormal exit (never Camera), then dismisses the card.
- **PERF-010-R7 Start fresh**: Start fresh dismisses the card and keeps the fresh scene; the next edit
  replaces the committed scene through SCN-002.
- **PERF-010-R8 Held scene survives another kill**: If the app is killed again before the user
  answers, the next launch offers the same scene.
- **PERF-010-R9 Crash-loop guard**: When the app exits abnormally in the session where the user
  reopened a scene or in the next session (N = 2 sessions), the next launch offers Start fresh only.
- **PERF-010-R10 Normal exit unchanged**: After a normal exit no card is shown and SCN-002's silent
  restore runs as today.
- **PERF-010-R11 Diagnostics event**: Each abnormal exit is logged once with only counts and flags
  (abnormal, crash loop, scene available, OSC turned off); no user data, scene content or ports.
- **PERF-010-R12 Test probe (DEBUG)**: A hidden DEBUG probe reports the recovery state and whether
  the OSC transport is listening; DEBUG UI-test launches suppress the decision unless the test asks
  for it, and the test reset clears the marker.
- **PERF-010-R13 Privacy**: The stored state is three small local values (session open, sessions since
  a reopen, the held visual's name), never leaves the device, and the privacy policy lists them.

### Key Entities

- **Session record**: whether a session is open; how many sessions ago the user reopened a scene
  (absent when not recent); the held visual while an offer is unanswered.
- **Launch decision**: clean, or abnormal with a crash-loop flag and whether a scene can be reopened.
- **Recovery offer**: the card's state: pending (with or without Reopen, with or without the OSC
  line), or answered.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PERF-010-S1**: In 100% of simulated crashes (kill without a background transition) the relaunched
  app has no OSC listener open and no camera running until the user turns them on.
- **PERF-010-S2**: After every abnormal exit the offer is shown on the first screen; after every
  normal exit it is not.
- **PERF-010-S3**: Reopen restores the last committed scene's visual and values in one tap.
- **PERF-010-S4**: A crash within 2 sessions of a reopen never offers Reopen.
- **PERF-010-S5**: Recovery adds no blocking step: the user can pick a source with the offer shown.

## Assumptions

- A crash while the app is in the background is not detected (the background transition already
  closed the session); being ended by the system in the background is normal on iOS.
- OSC's port and other settings are kept; only the on/off toggle is turned off.
- MetricKit is not used: the decision must be immediate at launch and MetricKit reports arrive later.
- Device evidence (a real crash on D1) is a `{device}` task; simulator results are never device
  evidence.
