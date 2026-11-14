# Feature Specification: UIX-013 Scene Performance HUD

**Feature Branch**: `feature/uix-013` (spec directory `233-uix-013-performance-hud`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-013 (Scene performance HUD) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Show current cue, next cue, tempo and audio source without covering output."
Acceptance, verbatim: "HUD is excluded from external output and recording." P1, depends on SHOW-001."

Identifiers in this feature carry the roadmap ID: requirements `UIX-013-R1…`, success criteria `UIX-013-S1…`,
research decisions `UIX-013-D1…`, tasks `UIX-013-T01…`. Other features are cited by their own IDs: SHOW-001
(cue list), SHOW-002 (timed cue advance), SHOW-003 (beat-quantized cues), SHOW-011 (tap tempo), ANL-006 (tempo
confidence), FR-042 (source-and-state indicator), UIX-005 (performance pad), UIX-007 (split editor), ACC-008
(overlay surface), OUT-001/OUT-004/OUT-010 (external display output, aspect correction, blackout), REC-001
(Save Frame), REC-003 (recording), REC-009 (recording status overlay), PERF-001 (performance overlay), FILE-005
(library backup), FILE-011 (local data erase).

## Baseline: what exists today (audit of 2026-11-14, commit `6bfaf2c4`)

| Question | Today |
|---|---|
| Cue state | SHOW-001 `ShowCoordinator.list` (`ShowCueList`): `activeCue`, `positionText` ("Cue 2 of 5"), cue labels, Standby. No "next cue" text anywhere. SHOW-002 `ShowAutoAdvanceCoordinator.countdownText` ("Next in 0:42"); SHOW-003 `cueQuantizer.queuedText`. |
| Tempo | SHOW-011 `TempoCoordinator.readout` (ANL-006 `TempoReadout`: manual, stable, uncertain, searching) with static texts ("120 BPM", "Manual"…). |
| Audio source | FR-042 `AppCoordinator.sourceStatusText` ("In-App Playback · Active audio"), the truthful indicator text (Constitution IV). |
| Where these show | UIX-005's performance pad readouts (cue, tempo) only while the performance layout is on, with big targets; the source indicator at the bottom when the controls are hidden. No single compact readout. |
| Overlays | `VisualizerView.statusStack` (top badges, banners, bottom status), padded by the safe area and UIX-005's reserved insets; inside UIX-007's `SplitEditorHost` output pane on iPad. ACC-008 `overlaySurface` gives badges a contrast-safe surface. |
| External output | OUT-001: the visual's own view moves into a `VisualSlotView` in the external window; that window holds the slot and nothing else (no SwiftUI overlay). |
| Recording / Save Frame | REC-003/REC-001 read the shown visual's Metal output (compositor `encodeOutput`, drawable blit, ANGLE capture); SwiftUI layers are never drawn into it (REC-009-R6 proves it for its overlay). |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: How is the HUD turned on? → A: A Settings switch "Show HUD" in the Performance section, off by default. It is a stored preference (one Bool, key `settings.visualizer.sceneHUD`): a performer sets it once per device. Backed up with the library settings (FILE-005), erased with the Settings category (FILE-011), removed by the UI-test reset.
- Q: What does it show? → A: Four lines: the current cue ("Cue 2 of 5 · Build", "Standby · 5 cues" or "No cues"), the next cue ("Next: Drop", "Next: end of show", with SHOW-002's countdown or SHOW-003's queued step when present), the tempo with its source ("120 BPM · Tap", "≈118 BPM · Estimated", "— BPM · None"), and the audio source (the FR-042 indicator text verbatim, so labeling stays truthful).
- Q: Where does it sit? → A: At the top of the visualizer's status stack, inside the safe area, the performance pad's reserved edges and (iPad) the split editor's output pane; width at most 360 pt; never in the output's centre. It stays with or without the controls while the switch is on.
- Q: Is it on the external display, in recordings or in saved frames? → A: Never. It is device UI only; there is no option to include it.
- Q: How is the tempo source named? → A: Tap for a tapped (manual) tempo, Estimated for the analysis estimate (stable or uncertain; uncertain shows "≈"), None while searching.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See where the show is at a glance (Priority: P1) — MVP

During a show I turn on "Show HUD". A small panel at the top of the screen tells me the current cue, the next
cue, the tempo and where it comes from, and the audio source. It updates as I step cues or tap tempo, and it
never covers the middle of the picture.

**Why this priority**: it is the whole roadmap row.

**Independent Test**: with the five-cue test show on cue 1, turn the HUD on: it reads "Cue 1 of 5 · Opening",
"Next: Build", a tempo line and the source; step to cue 2: it reads "Cue 2 of 5 · Build", "Next: Drop".

**Acceptance Scenarios**:

1. **Given** the HUD is on and the show stands on cue 1 of 5, **When** I look at the visualizer, **Then** the HUD shows the current cue, the next cue, the tempo with its source and the audio source.
2. **Given** the HUD is on, **When** I step to the next cue or tap a tempo, **Then** the HUD shows the new state from the next screen update.
3. **Given** the HUD is on, **When** the controls hide, the performance layout is on or the split editor is open, **Then** the HUD stays inside the safe area, clear of the pad's targets and the editor, and away from the output's centre.

### User Story 2 - The audience never sees it (Priority: P1)

**Acceptance Scenarios**:

1. **Given** the visualization shows on an external display and the HUD is on, **When** I look at the external display, **Then** it shows exactly the same picture as with the HUD off.
2. **Given** the HUD is on, **When** I record or save a frame, **Then** the file is identical to one made with the HUD off.

### User Story 3 - Readable for everyone (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the largest accessibility text size, **When** the HUD is on, **Then** its lines wrap (at most two lines each) and stay on screen.
2. **Given** VoiceOver, **When** I move through the HUD, **Then** each line is read with its meaning ("Current cue, Cue 2 of 5, Build").

### Edge Cases

- No cues: the cue line reads "No cues" and the next line is absent.
- Standby: current "Standby · 5 cues", next is cue 1.
- Last cue: next reads "End of show".
- A timed advance is running: the next line adds "in 0:12" (or "in 0:12, held").
- A quantized step waits: the next line shows the queued text instead of the next cue.
- No tempo yet: "— BPM · None".
- Output blacked out: the HUD stays on the device (it never reached the output anyway).
- Settings opened as a sheet on iPhone: the HUD is under the sheet like every other overlay.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-013-R1**: Settings → Performance MUST offer a switch "Show HUD", off by default, stored on the device and kept across launches.
- **UIX-013-R2**: While on, the visualizer MUST show the HUD with or without the controls, in every visual (projectM and the alternate visuals).
- **UIX-013-R3**: The HUD MUST show the current cue (position and label, Standby, or No cues).
- **UIX-013-R4**: The HUD MUST show the next cue's label, "End of show" on the last cue, the SHOW-002 countdown when one runs, and the SHOW-003 queued step instead of the next cue while one waits; no next line without cues.
- **UIX-013-R5**: The HUD MUST show the tempo and its source: Tap, Estimated or None (contract texts).
- **UIX-013-R6**: The HUD MUST show the audio source exactly as the FR-042 indicator states it.
- **UIX-013-R7**: The HUD MUST sit at the top of the status stack inside the safe area, the performance pad's reserved edges and the split editor's output pane, at most 360 pt wide, and MUST NOT cover the output's centre.
- **UIX-013-R8**: The HUD MUST NOT appear on an external display; that display's picture MUST be identical with the HUD on or off.
- **UIX-013-R9**: Recordings and saved frames MUST NOT contain the HUD; a file made with the HUD on MUST be pixel-identical to one made with it off.
- **UIX-013-R10**: The HUD MUST use the ACC-008 overlay surface, scale with Dynamic Type (each line at most two lines), and expose each line to VoiceOver with a label and value; it posts no announcements.
- **UIX-013-R11**: The preference MUST be in FILE-005's included settings, erased with FILE-011's Settings category, and removed by the UI-test reset.

### Key Entities

- **HUD content**: four optional texts (current, next, tempo, source) plus their spoken forms, computed from the cue list, the advance countdown, the queued step, the tempo readout and the source text.
- **HUD preference**: one Bool.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-013-S1**: With the HUD on, the external display's picture is byte-identical to the picture with the HUD off (0 differing pixels).
- **UIX-013-S2**: A saved frame and every recorded frame made with the HUD on match the HUD-off result exactly (0 differing pixels) and contain no HUD probe pixel.
- **UIX-013-S3**: With the test show, the HUD shows the four lines with the expected texts within one second of turning it on, and the cue lines follow a cue step.
- **UIX-013-S4**: The HUD's frame lies inside the safe area and does not contain the screen's centre point.

## Assumptions

- The HUD reads existing state only; nothing about cues, tempo or audio changes.
- Simulator results are never device evidence; a device check of the HUD on D1 is a `{device}` task.
- No new network, permission or storage use beyond one preference Bool.
