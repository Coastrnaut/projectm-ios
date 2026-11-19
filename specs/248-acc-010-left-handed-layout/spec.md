# Feature Specification: ACC-010 Left-Handed Layout

**Feature Branch**: `feature/acc-010` (spec directory `248-acc-010-left-handed-layout`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (ACC-010-T01–T12 verified on the Mac: ShowControl package tests on the host, app unit tests and UI tests on a private iOS 27.2 iPhone 17 simulator. Open: ACC-010-T13 `{device}` check on D1 and D2. Simulator results are UI evidence only.)

**Input**: User description: "Implement ACC-010 (Left-handed layout) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Mirror performance controls without mirroring rendered output."
Acceptance, verbatim: "Button positions swap and action identifiers remain unchanged." P2, effort S, depends on UIX-005."

Identifiers in this feature carry the roadmap ID: requirements `ACC-010-R1…`, success criteria `ACC-010-S1…`,
research decisions `ACC-010-D1…`, tasks `ACC-010-T01…`. Other features are cited by their own IDs: UIX-005
(performance pad), ACC-009 (one-handed layout), SHOW-014 (emergency Black out corner button), OUT-001/OUT-010 (external
output, blackout), FR-082/FR-087 (controls card rows), UIX-007 (split editor), UIX-013 (HUD isolation tests), FILE-005 /
FILE-011 (backup and Settings erase).

## Baseline: what exists today (audit of 2026-11-14, commit `372c75ed`)

| Question | Today |
|---|---|
| Performance pad (UIX-005) | `PerformanceLayout` (ShowControl) picks a bottom bar (Previous cue, Next cue, Tap tempo, Black out, left to right), a 2 × 2 grid (cue pair on top, Tap tempo and Black out below) or side columns in a landscape-shaped area (cue column leading, tempo and Black out trailing). Identifiers `perfPreviousCue`, `perfNextCue`, `perfTapTempo`, `perfBlackout`; readouts `perfCueReadout` (leading), `perfTempoReadout` (trailing). |
| Emergency Black out (SHOW-014) | A 44 pt `emergencyBlackout` button at the bottom trailing corner of the status stack while the output is live and the pad is off. |
| One-handed (ACC-009) | Settings → One-handed layout: Off / Left hand / Right hand, iPhone only, key `settings.controls.oneHanded`. While active, the critical actions and the pad's targets sit in the chosen bottom corner (`OneHandedLayout`). |
| Controls card (FR-082/FR-087) | A full-width card; the compact main row is Stop, Pause, Previous, Next, Random, Presets, Settings. Not edge-anchored: both ends are equally far from either hand. |
| Rendered output | The visual (device slot), the external display (OUT-001), recordings and Save Frame are drawn by their own views and never by the overlay layers. |
| Right-to-left handling | None needed so far; the app never forces a layout direction. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human interaction);
each answer is the conservative, local-first option.

- Q: What is the switch, and how does it relate to ACC-009's Left hand / Right hand? → A: One new switch "Left-handed controls" (Off by default) in Settings → Performance, shown on iPhone and iPad, directly above ACC-009's One-handed layout choice. It is a stored preference. It is not a second hand choice for the same thing: one-handed moves the critical actions into a thumb-zone corner (iPhone only); left-handed only swaps the sides of edge-anchored performance controls in the standard arrangement. While the one-handed layout is active, its chosen hand decides the side of everything the two features share (the pad and the emergency button), so the two can never disagree (`ACC-010-R1`, `ACC-010-R6`).
- Q: What is mirrored? → A: The horizontal placement of edge-anchored performance controls: UIX-005's pad (side columns swap sides; bar and grid slots are mirrored; the readouts follow their groups) and SHOW-014's emergency Black out button (bottom trailing corner → bottom leading corner). The controls card is not changed: it spans the full width and its order is FR-087's documented order (`ACC-010-R2`, `ACC-010-R3`).
- Q: Directional pairs? → A: Previous cue and Next cue take the mirrored pair of slots but keep their reading order (Previous left of Next), because their arrows point backward and forward. Every other target sits exactly at the mirror of its right-handed position (`ACC-010-R3`).
- Q: What is never mirrored? → A: The rendered visual, the external display, recordings, Save Frame, text direction, symbols and the layout direction of any text; no view is flipped and the app does not change the system layout direction (`ACC-010-R4`).
- Q: Do identifiers, labels or VoiceOver change? → A: No: every identifier, label, value, hint and keyboard shortcut is unchanged. VoiceOver's order follows the visual order (left to right, top to bottom), as it does today; no announcement on the switch (`ACC-010-R5`).

### Session 2026-11-14 (speckit-clarify)

- Q: When does a change of the switch take effect? → A: At once, on the next layout pass, while Settings is open beside or over the visualizer; no extra animation (moves follow the existing Reduce Motion-aware transitions) and no relaunch (`ACC-010-R1`).
- Q: Do the pad's readouts change their text alignment? → A: Each readout moves with its group and aligns toward the screen edge on its side (the cue readout is trailing-aligned when its group is on the right); the characters, reading direction and wrapping rules are unchanged (`ACC-010-R3`, `ACC-010-R4`).
- Q: Where exactly is the switch, and what does its footer say? → A: Its own section in Settings → Performance, directly before One-handed layout, with the footer "Moves the performance pad's Black out and Tap tempo buttons and the emergency Black out button to the left side. The visualization is never mirrored. While the one-handed layout is on, its hand decides." (`ACC-010-R1`, `ACC-010-R6`).
- Q: Does the UIX-013 HUD, the status badges, the performance overlay or the controls card move? → A: No. They are full-width or top-anchored and keep their places; only the pad and the emergency button are edge-anchored performance controls (`ACC-010-R2`, `ACC-010-R3`).
- Q: How do tests turn the switch on? → A: Through the argument domain (`-settings.controls.leftHanded YES`), as other preferences do; `-uitestResetNotice` removes the stored value first, and a launch argument still overrides it (`ACC-010-R7`).

### Session 2026-11-19 (QA-011 device run)

- Q: ACC-010-T13 failed in landscape on D2 and D3 with Next cue at x 1332 of 1376 and 1136 of 1180 pt; is the pad not mirrored? → A: It is: User Story 1 scenario 1 puts the cue targets in the trailing column and Tap tempo and Black out in the leading one when left-handed. The device test expected the right-handed placement; it now checks Next cue trailing and Tap tempo leading.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pad and emergency button on the left (Priority: P1) — MVP

A left-handed VJ turns on Settings → Left-handed controls. With the performance layout on in landscape, Tap tempo and
Black out now sit in the left column and the cue arrows in the right one; in portrait the bar puts Black out at the
left end. With the pad off, the emergency Black out button sits in the bottom left corner. The visual itself looks
exactly as before.

**Why this priority**: it is the roadmap row and its acceptance clause.

**Independent Test**: the pure geometry gives, for each arrangement and size, each target's frame in left-handed mode
equal to the horizontal mirror of its right-handed frame (within 1 pt; the cue pair as a pair with reading order kept)
and the same identifier set; a UI test turns the setting on and finds the pad's targets and the emergency button at
swapped positions with identical identifiers.

**Acceptance Scenarios**:

1. **Given** the performance layout in a landscape-shaped area, **When** Left-handed controls is on, **Then** Tap tempo and Black out are in the leading column and the cue targets in the trailing column, each at the mirror of its right-handed frame.
2. **Given** the bottom bar, **When** left-handed, **Then** Black out is at the left end, Tap tempo next to it, and Previous cue / Next cue occupy the right pair of slots with Previous still left of Next.
3. **Given** the pad is off and the output is live, **When** left-handed, **Then** the emergency Black out button is in the bottom leading corner, mirrored from the trailing corner.
4. **Given** either setting, **Then** the set of identifiers on screen and each target's label, value and action are identical.

---

### User Story 2 - The output is never mirrored (Priority: P1)

The same performer sends the visual to a projector. Turning Left-handed controls on or off changes nothing on the
projector, in a recording or in a saved frame.

**Independent Test**: an external display window built like the app's shows an asymmetric stand-in visual; its
snapshot is byte-identical with the pad left-handed and right-handed on the device, and the device slot's visual is
not transformed.

**Acceptance Scenarios**:

1. **Given** an external display showing the visual, **When** the setting changes, **Then** its picture is byte-identical.
2. **Given** the device shows the visual, **When** the setting changes, **Then** the visual's view has no transform and its left half is still on the left.

---

### User Story 3 - The choice is kept and coexists with one-handed (Priority: P2)

The choice survives relaunch, is backed up and erased with Settings, and while ACC-009's one-handed layout is active
its hand decides.

**Independent Test**: unit tests of the preference (default off, stored on change, effective side with and without
one-handed), the backup and erase key lists.

**Acceptance Scenarios**:

1. **Given** a fresh install, **Then** the setting is off and nothing is stored.
2. **Given** One-handed layout → Right hand and Left-handed controls on, **Then** the effective side is right.
3. **Given** iPad, **Then** Left-handed controls is offered (one-handed is not).

### Edge Cases

- Left-handed on, performance layout off, output blacked out: the emergency button is hidden (as today); the badge's Restore is unchanged.
- Rotation between portrait and landscape: the arrangement changes and the mirror applies to whichever arrangement is shown.
- Accessibility text sizes: targets keep their size (UIX-005); readouts follow their groups.
- iPad split editor (UIX-007): the output panel is never mirrored; the pad and corner button inside the visualizer follow the setting.
- One-handed active: the one-handed hand decides; the Left-handed switch stays visible with a footer saying so.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-010-R1**: Settings → Performance MUST offer a "Left-handed controls" switch (identifier `leftHandedToggle`), off by default, on iPhone and iPad, stored as a preference that survives relaunch.
- **ACC-010-R2**: With the switch on, SHOW-014's emergency Black out button MUST sit at the bottom leading corner instead of the bottom trailing corner, at the horizontal mirror of its right-handed frame.
- **ACC-010-R3**: With the switch on, UIX-005's pad MUST place each target at the horizontal mirror of its right-handed slot (side columns swap; bar and grid slots mirror), except that Previous cue and Next cue keep their reading order within their mirrored pair of slots; each readout MUST stay with its group.
- **ACC-010-R4**: The setting MUST NOT mirror or otherwise change the rendered visual, the external display, recordings, Save Frame, text direction or symbols, and MUST NOT change the app's layout direction.
- **ACC-010-R5**: Every identifier, label, value, hint and keyboard shortcut of the moved controls MUST be unchanged; the set of identifiers shown MUST be identical in both modes.
- **ACC-010-R6**: While ACC-009's one-handed layout is active, its chosen hand MUST decide the side (left-handed for Left hand, right-handed for Right hand); otherwise the switch decides.
- **ACC-010-R7**: The preference MUST be backed up with the library settings (FILE-005), erased with the Settings category (FILE-011) and removed by the UI-test reset; it is never written into scenes, cues, MIDI or OSC.

### Key Entities

- **Left-handed controls preference**: one Boolean (absent = off).
- **Controls side**: left or right, derived from the one-handed hand (when active) or the preference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-010-S1**: For every arrangement (bar, grid, side columns) and a few representative sizes, every pad target's left-handed frame is the horizontal mirror of its right-handed frame within 1 pt (the cue pair's combined frame for the two cue targets), and the identifier sets are equal.
- **ACC-010-S2**: In the running app, switching the setting moves the pad's targets and the emergency button to mirrored positions (within 1 pt) with the same identifiers.
- **ACC-010-S3**: The external display's picture is byte-identical with the setting on and off, and the device visual is not transformed.
- **ACC-010-S4**: The new preference appears in every key list (device-test allow list, backup policy, UI-test reset, backup app test).

## Assumptions

- The controls card (FR-082/FR-087) is not edge-anchored and keeps its order; mirroring it would put Next before Previous.
- The UIX-013 HUD and the status badges stay at the top, full width, and are unchanged.
- Simulator results are UI evidence only; a `{device}` pass on D1 confirms the feel with a left hand.
