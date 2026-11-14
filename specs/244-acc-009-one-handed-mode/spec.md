# Feature Specification: ACC-009 One-Handed Performance Mode

**Feature Branch**: `feature/acc-009` (spec directory `244-acc-009-one-handed-mode`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement ACC-009 (One-handed performance mode) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Relocate primary controls into reachable touch zones."
Acceptance, verbatim: "Layout switch preserves every critical action on phone sizes." P2, depends on UIX-005."

Identifiers in this feature carry the roadmap ID: requirements `ACC-009-R1…`, success criteria `ACC-009-S1…`,
research decisions `ACC-009-D1…`, tasks `ACC-009-T01…`. Other features are cited by their own IDs: FR-082/FR-087
(the controls and their compact rows), UIX-005 (performance pad), UIX-013 (scene HUD), SHOW-001 (cue row), SHOW-006
(rehearsal panel), SHOW-011 (tap tempo), OUT-010 (blackout), SHOW-014 (emergency blackout), ACC-006 (accessibility
text sizes), ACC-008 (overlay surface), QA-009 (primary-screen accessibility manifest), FILE-005 / FILE-011 (backup
and Settings erase).

## Baseline: what exists today (audit of 2026-11-14, commit `6fc4ef0a`)

| Question | Today |
|---|---|
| Critical actions | FR-082 main row (`controlsPrimary`: Stop, Pause/Resume, Previous, Next, Random, Presets, Settings), OUT-010 Black out (`controlsSecondary`), SHOW-011 Tap tempo (`TempoControls`), SHOW-001 Previous/Next cue (`ShowCueRow`, shown when the show has cues). Previous, Next, Random and Presets are left out while a native visual is shown (VIS-001-R13). |
| Where they sit on a phone | The controls card sits at the bottom of the safe area; the main row spans the card's full width, so Stop lies at the far left and Settings at the far right of a 440 pt Pro Max. Icon cells are at least 32 pt wide and 36 pt tall (below Apple's 44 pt). |
| Performance pad | UIX-005 `PerformanceLayout` (ShowControl, pure geometry): 60 pt targets (72 pt when both size classes are regular), portrait bottom bar or grid, landscape side columns; the pad reports reserved edges and the status stack is inset by them; the pad's Blackout carries the B key (SHOW-014's corner button hidden). Targets `perfPreviousCue`, `perfNextCue`, `perfTapTempo`, `perfBlackout`. Session only. |
| Top of the screen | UIX-013 HUD and SHOW-006 rehearsal panel sit at the top of the status stack, with or without the controls; the status stack is padded by the pad's reserved edges. |
| Safe area | `SplitEditorHost` keeps the safe area on iPhone (fix of 2026-11-14). |
| Accessibility checks | QA-009 `PrimaryScreensManifest` lists each screen's required controls; `PrimaryScreensAccessibilityUITests` checks presence, label, view and hittability at standard and AX5 sizes. |
| Handedness | None: no option moves controls toward one hand. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human interaction);
each answer is the conservative, local-first option.

- Q: What is the switch? → A: A Settings choice "One-handed layout" with Off, Left hand and Right hand (Off by default) in the Performance part of Settings, after Show HUD. It is a stored preference, not session state like UIX-005's pad (`ACC-009-R1`).
- Q: Which actions are critical? → A: Stop, Pause/Resume, Previous, Next, Random, Presets, Settings, Black out, Tap tempo, and Previous cue / Next cue when a show with cues is loaded or the performance pad is on. Previous, Next, Random and Presets are left out exactly when the standard layout leaves them out (native visuals). Secondary actions (Switch Source, Lock scene, Save Frame, Record, Performance layout, Duplicate, transport, shelf) stay in the controls card (`ACC-009-R2`).
- Q: What is the thumb zone? → A: A rectangle in the bottom corner of the safe area on the chosen side. Portrait-shaped area: the bottom 40 % of the height and 75 % of the width from the chosen edge. Landscape-shaped area (wider than tall): 40 % of the width from the chosen edge and the bottom 75 % of the height (one hand holds a landscape phone by its side). Every critical target lies wholly inside it (`ACC-009-R3`).
- Q: Target sizes? → A: Square targets of at least 44 pt that grow with Dynamic Type up to 56 pt; the four pad actions keep the UIX-005 size (60 pt, 72 pt when both size classes are regular) while the pad is on. If the larger size does not fit the zone, targets shrink in 4 pt steps, never below 44 pt or the pad size (`ACC-009-R4`).
- Q: Which devices? → A: iPhone only (every phone size, portrait and landscape). On iPad the choice is not offered and a stored value is ignored, so iPad layouts are unchanged (`ACC-009-R6`).

### Session 2026-11-14 (speckit-clarify)

- Q: Is there a quick switch in the controls card as well as Settings? → A: No. The choice lives in Settings only: switching hands mid-show is rare, and a fourteenth icon would crowd FR-087's rows again (`ACC-009-R1`).
- Q: In what order are the targets placed? → A: Rows fill from the bottom of the zone upward, each row aligned to the chosen edge and in reading order: the pad group (Previous cue, Next cue, Tap tempo, Black out) first, nearest the thumb, then Previous, Next, Random, Pause/Resume, Presets, Settings and Stop, so Stop (it leaves the visualizer) is farthest from the thumb (`ACC-009-R3`).
- Q: What happens when the targets do not fit the zone? → A: Main targets shrink in 4 pt steps to 44 pt; if they still do not fit, every action is still placed (rows continue upward) and the layout reports that it does not fit. No action is ever dropped; the tests require a fit for every phone size in the table (`ACC-009-R4`).
- Q: Does SHOW-014's emergency Black out corner button change? → A: No. It stays in the status stack (inset clear of the cluster) while the output is live and the pad is off; the cluster's Black out is OUT-010's toggle, as in the standard layout (`ACC-009-R5`).
- Q: Is the switch announced to VoiceOver? → A: No status event: the Settings choice is a labelled control whose value VoiceOver reads; the cluster's targets keep the standard labels (`ACC-009-R8`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every critical action under the thumb (Priority: P1) — MVP

A VJ holds an iPhone in the right hand and a drink or a cable in the left. They choose Settings → One-handed layout
→ Right hand. With the controls shown, Stop, Pause, Previous, Next, Random, Presets, Settings, Black out, Tap tempo
and the cue arrows sit as large buttons in the bottom right corner, all reachable with the right thumb.

**Why this priority**: it is the roadmap row and its acceptance clause.

**Independent Test**: the pure geometry over a table of phone sizes, orientations, text sizes and contexts places
exactly the standard layout's critical actions, each inside the safe area, inside the zone, at least 44 pt, without
overlap; a UI test switches the layout and finds every critical action hittable inside the zone.

**Acceptance Scenarios**:

1. **Given** the standard layout with a show loaded, **When** the user switches to Right hand, **Then** every critical action of the standard layout is present, hittable, at least 44 pt and inside the bottom-right thumb zone.
2. **Given** Left hand, **Then** the same actions sit in the bottom-left zone.
3. **Given** a native visual, **Then** both layouts offer the same reduced set (no Previous, Next, Random, Presets).
4. **Given** the One-handed layout, **When** the user taps Pause, **Then** the visual pauses as with the standard button.

---

### User Story 2 - One-handed with the performance pad (Priority: P2)

A performer with the UIX-005 pad on also chooses One-handed: the pad's four large targets move into the thumb zone
at their full size and stay on screen without the controls; the other critical actions join them when the controls
show.

**Independent Test**: geometry cases with the pad on: the pad actions are 60 pt and do not move when the controls
appear.

**Acceptance Scenarios**:

1. **Given** the pad and One-handed (Right), **When** the controls are hidden, **Then** Previous cue, Next cue, Tap tempo and Black out are drawn at 60 pt in the zone, with the cue and tempo readouts above them.
2. **Given** the same, **When** the controls show, **Then** the seven FR-082 actions appear above the pad actions in the zone and the pad actions keep their places.
3. **Given** the pad's Black out while live, **Then** it keeps the B key.

---

### User Story 3 - Nothing hides anything (Priority: P2)

With the HUD or the rehearsal panel on, nothing in the one-handed cluster covers them, and the controls card sits
clear of the cluster.

**Independent Test**: geometry: every target lies inside the edge band the layout reserves (bottom in portrait,
the chosen side in landscape); the status stack, which holds the HUD and the panel, is inset by that band. A UI test
with the HUD on checks that no target intersects it.

**Acceptance Scenarios**:

1. **Given** One-handed with the HUD on, **Then** no critical target intersects the HUD.
2. **Given** One-handed at the largest accessibility text size, **Then** every critical action is still present, hittable and in the zone.

### Edge Cases

- The smallest supported iPhone (375 × 667 pt) in landscape at an accessibility text size with the pad and a show: the zone holds all 11 targets (pad targets wrap to two rows of three and one).
- SHOW-014's emergency Black out button stays where it is, above (portrait) or beside (landscape) the cluster.
- Rotation: the zone and arrangement follow the area's shape, not the device orientation (as UIX-005).
- Controls hidden, pad off: nothing is drawn (as the standard layout); a tap shows the controls and the cluster.
- iPad or a stored value restored from a backup onto an iPad: ignored; iPad layouts unchanged.
- An action disabled in its state (Previous cue at the first cue) stays present and disabled, as in the standard layout.
- Accessibility text sizes: target icons do not scale beyond the target; each target offers the Large Content Viewer (as UIX-005).

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-009-R1**: Settings MUST offer "One-handed layout" (Off, Left hand, Right hand; Off by default) with a short footer, on iPhone only.
- **ACC-009-R2**: With a hand chosen, the critical actions (listed in Clarifications) MUST leave the controls card and appear as square targets in the one-handed cluster; the set MUST equal the standard layout's set for the same state (show, pad, visual). Secondary actions stay in the card.
- **ACC-009-R3**: Every critical target MUST lie wholly inside the safe area and inside the thumb zone of the chosen side (Clarifications), with no two targets overlapping.
- **ACC-009-R4**: Targets MUST be at least 44 pt, scale with Dynamic Type up to 56 pt, and keep the UIX-005 size for the pad actions while the pad is on; shrinking to fit never goes below those minimums and never drops an action.
- **ACC-009-R5**: The cluster MUST reserve an edge band (bottom in portrait-shaped areas, the chosen side in landscape-shaped ones) that the status stack, the controls card, the HUD and the rehearsal panel keep clear of; every target lies inside the band.
- **ACC-009-R6**: On iPad the choice MUST NOT be offered and MUST be ignored.
- **ACC-009-R7**: With the pad on, the pad's four actions MUST be drawn in the zone at the pad size with or without the controls, keep their identifiers and the B key behaviour, and not move when the controls show or hide; the readouts sit above the cluster.
- **ACC-009-R8**: Targets MUST keep the standard controls' identifiers, VoiceOver labels, values and hints, and offer the Large Content Viewer.
- **ACC-009-R9**: The choice MUST be stored locally only (`settings.controls.oneHanded`), included in the FILE-005 backup, erased with Settings, allowed by `scripts/run_device_tests.py` and removed by the UI-test reset; never in scenes, cues, MIDI or OSC.
- **ACC-009-R10**: QA-009's manifest MUST list the one-handed controls screen with every critical action.

### Key Entities

- **Hand**: left or right (absent = Off).
- **Critical action**: one of the eleven actions; belongs to the pad group (cues, tap tempo, black out) or the main group.
- **One-handed layout**: the pure geometry: zone, target sides, one frame per displayed action, reserved edge band.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-009-S1**: Over 5 phone sizes (smallest supported iPhone to Pro Max) × portrait and landscape × 3 text sizes × 4 states × 2 hands, the layout places exactly the standard set, each target ≥ 44 pt (pad actions ≥ 60 pt with the pad), inside the safe area and the zone, without overlap, inside the reserved band.
- **ACC-009-S2**: With the pad on, the pad actions' frames are identical with the controls shown and hidden.
- **ACC-009-S3**: On two simulated phone sizes, a UI test switches Standard → Right hand in Settings and finds every critical action of the standard layout present, hittable and inside the zone, each test under 30 s; Pause works from the cluster.
- **ACC-009-S4**: With Left hand and the HUD on, every critical action is in the bottom-left zone and none intersects the HUD.
- **ACC-009-S5**: QA-009's one-handed controls screen passes at standard and AX5 sizes.

## Assumptions

- Simulator results are UI evidence only; the feel of thumb reach is checked on D1 with a person (`{device}` task).
- The zone's percentages follow common thumb-reach guidance for phones; they are a rule tested by geometry, not a measurement of hands.
- The smallest supported iPhone is the 375 × 667 pt iPhone SE (iOS 26 deployment target).
