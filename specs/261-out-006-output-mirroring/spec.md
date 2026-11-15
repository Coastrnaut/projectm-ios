# Feature Specification: OUT-006 Output Mirroring Toggle

**Feature Branch**: `feature/out-006` (spec directory `261-out-006-output-mirroring`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement OUT-006 (Output mirroring toggle) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose same scene or a clean output
variant per display." Acceptance, verbatim: "Toggle changes output routing without duplicating audio
capture." P2, size L, depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-006-R1…`, success criteria
`OUT-006-S1…`, tasks `OUT-006-T01…`. Other features are cited by their own IDs: OUT-001 (external
display scene), OUT-002 (hot-plug, recording hold), OUT-003 (output resolution), OUT-004 (aspect
correction), OUT-005 (safe-area guides), OUT-010 (output blackout), OUT-012 (output rehearsal), UIX-013
(scene HUD), MED-009 (Text visual), MED-010 (logo overlay), FILE-005 (library backup), FILE-011 (erase).

## Baseline: what exists today (audit of 2026-11-14, commit `eeb96e2c`)

| Area | Today | Gap for this row |
|---|---|---|
| Routing (OUT-001) | One visual view (projectM's ANGLE view, a native spectrum, Camera, Photo, Video or Text host) is moved into the external display's slot; the device's slot is empty (black) and shows the note "Showing on external display". Nothing is drawn twice; no second context or engine exists (OUT-001-R3). | No choice of what the external display shows. |
| Device screen while external | Controls, badges, banners, the scene HUD (UIX-013), the cue rehearsal panel, the safe-area guides (OUT-005), the performance overlay and the status captions are SwiftUI views in the device window. | None: they never reach the external window. |
| Visual content | The compositor visuals (Photo, Video, Camera, Text) draw MED-010's logo as their top layer; the logo therefore shows on whatever display holds the visual, and in recordings and Save Frame. | A clean output without the logo is impossible today. |
| Output settings | Settings › External Display: Fit, Shape, Pixel aspect (OUT-004), Resolution (OUT-003), Rehearse output (OUT-012). Device-local keys `settings.externalDisplay.*`, left out of the library backup and erased with Settings. | A mode choice. |
| Audio pipeline | One `CaptureManager` owns the source; its analyzer feeds one normalized output (projectM's feed) with one analysis tap (native visuals, tempo) and one recording tap. Moving the visual never touches it (OUT-001-R4). | Must stay exactly one capture whatever the mode. |
| Output blackout, rehearsal | OUT-010 covers every slot; OUT-012 previews a test card, never the live visual. | Independent of the mode. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What do "same scene" and "clean output variant" mean in this app? → A: Two output modes for an
  external display. **Same scene** (the default, today's behaviour): the display shows the scene exactly
  as composed: the visual and its scene layers, including the MED-010 logo. **Clean output**: the display
  shows the visual content only; scene overlay layers (today the MED-010 logo, the only overlay layer)
  are left out while the visual is on that display. In both modes the app's own interface (controls,
  badges, HUD, guides, performance overlay, captions, notes) never reaches an external display.
  Rejected: "Mirror" as a second live picture on the device while the display also shows the visual.
  It would need a second presentation of every visual (two drawables, or a per-frame GPU copy in six
  visual hosts and in the ANGLE engine), contradicting OUT-001-R3's single render; public APIs give no
  way to show one layer in two windows. The row's "per display" and "routing" fit best as the choice of
  which layers are routed to the external output (OUT-006-R1, R2).
- Q: Is the mode stored per physical display? → A: No: one stored mode applies to the external output
  (OUT-001 shows the visual on one external display at a time, and a display's scene identifier is not
  a stable identity of the hardware). The device itself always shows the same scene (OUT-006-R3).
- Q: Does Clean output hide the Text visual's text? → A: No. The text is the content of the visual the
  user chose (MED-009), not an overlay; Clean never changes which visual is shown or its own layers
  (OUT-006-R2).

### Session 2026-11-14 (speckit-clarify)

- Q: Should a mode change wait while a recording holds the placement (OUT-002), as OUT-004 and OUT-003 do? → A: No, it applies live. Those deferrals protect the recording's picture size; the mode changes no size, only whether the logo is drawn, and the user expects the projector to change at once. A recording records the one rendered output, so it shows what the display shows (OUT-006-R5, edge cases).
- Q: Does the device note or an announcement change with the mode? → A: No announcement (a settings change is not a status event); the device note keeps OUT-001's wording, and Settings' footer explains both options. Keeps ACC-011's status catalogue unchanged (OUT-006-R1).
- Q: How is "left out" achieved without a second render? → A: The overlay layers stay attached and keep their stored placement; while routed away from the external output they draw nothing (the logo layer's effective opacity is 0). Nothing reloads, so switching back shows the logo from the next frame (OUT-006-R2, R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A clean picture on the projector (Priority: P1)

A performer keeps their logo on the scene for recordings on the phone, but the venue wants a clean
picture on the projector. They choose Clean output in Settings › External Display; when the display is
connected, the projector shows the visual without the logo.

**Why this priority**: It is the row's new behaviour.

**Independent Test**: With a logo set, a compositor visual and a fake external display, switch the mode
and check that the logo layer draws on the display in Same scene and draws nothing in Clean output.

**Acceptance Scenarios**:

1. **Given** Clean output and a logo, **When** the visual moves to the external display, **Then** the
   logo is left out of the picture from the next frame.
2. **Given** Clean output and the visual on the display, **When** the display disconnects, **Then** the
   visual returns to the device with its logo.
3. **Given** the visual on the display, **When** the user switches the mode, **Then** the change shows
   at once (live), and the visual stays on the display.

---

### User Story 2 - One audio capture whatever the mode (Priority: P1)

Switching the mode never starts, stops or duplicates the audio capture or its analysis.

**Why this priority**: The row's acceptance.

**Independent Test**: Toggle the mode with the fake display attached and compare the audio pipeline's
identity and session count before and after.

**Acceptance Scenarios**:

1. **Given** audio is playing and a display is attached, **When** the mode is toggled several times,
   **Then** the same capture, the same normalized output, the same analysis tap and the same number of
   capture sessions remain, and the source was started once.

---

### User Story 3 - The setting persists (Priority: P2)

**Acceptance Scenarios**:

1. **Given** Clean output was chosen, **When** the app relaunches, **Then** Clean output is still
   chosen; an unknown or missing stored value reads Same scene.

### Edge Cases

- No display connected: the mode changes nothing on the device (the device always shows the same scene).
- A recording is running (OUT-002 hold): the mode applies live; a recording records what the output
  shows, so a recording made while Clean output shows on the display has no logo.
- Blackout (OUT-010) covers the output in both modes; the rehearsal (OUT-012) shows a test card and is
  unaffected.
- Visuals without a logo layer (projectM, native spectra): both modes look the same.
- The logo's stored placement and opacity are never changed by the mode.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-006-R1**: Settings › External Display MUST offer an Output choice with two options, "Same
  scene" (default) and "Clean output", that applies to the external display output.
- **OUT-006-R2**: In Clean output, while the visual is shown on an external display, scene overlay
  layers (the MED-010 logo) MUST be left out of the picture; the visual and its own layers are unchanged.
  In Same scene, the external display shows everything the scene composes.
- **OUT-006-R3**: While the visual is on the device, overlay layers MUST always show, whatever the mode.
- **OUT-006-R4**: The app's interface (controls, badges, HUD, guides, performance overlay, captions,
  notes) MUST never appear on an external display in either mode; the external window holds only the
  visual.
- **OUT-006-R5**: A mode change MUST apply live (also while a recording holds the placement), inside the change, without moving the visual between
  displays, restarting it, or touching the audio source.
- **OUT-006-R6**: There MUST be exactly one audio capture and one analysis pipeline in both modes: no
  second capture, no second normalized output or analysis tap, no restart of the source.
- **OUT-006-R7**: The choice MUST persist on the device (one device-local value; absent or unknown
  reads Same scene). Like the other external display settings it describes the user's rig: it is left
  out of the library backup, erased with Settings, and removed by the UI-test reset.
- **OUT-006-R8**: A DEBUG probe MUST report the mode, where the visual is and whether overlays are
  routed to it (UI tests).

### Key Entities

- **External output mode**: Same scene or Clean output; stored device-locally.
- **Output layer class**: visual content, scene overlay, interface; which classes reach a target (device
  or external) under a mode.

## Success Criteria *(mandatory)*

- **OUT-006-S1**: In 100 % of toggles with a display attached, the logo is shown on the display in Same
  scene and absent in Clean output, from the next frame.
- **OUT-006-S2**: Toggling the mode any number of times leaves exactly one audio capture: the source is
  started once and its session count does not change.
- **OUT-006-S3**: The choice survives a relaunch in 100 % of runs.
- **OUT-006-S4**: No interface element appears on the external display in either mode.

## Assumptions

- OUT-001's single-render routing stays: the visual is shown on one display at a time.
- The MED-010 logo is the only scene overlay layer today; later overlay layers join the same class.
- Device evidence (a real display, a real logo, a projector) is a `{device}` task; simulator results
  are never device evidence.
