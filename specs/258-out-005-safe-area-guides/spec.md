# Feature Specification: OUT-005 Safe-Area Guides

**Feature Branch**: `feature/out-005` (spec directory `258-out-005-safe-area-guides`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (OUT-005-T01-T11 verified on the Mac, iOS 27.2 simulator; T12 `{device}` open)

**Input**: User description: "Implement OUT-005 (Safe-area guides) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Overlay configurable stage-safe and title-safe guides in editor only."
Acceptance, verbatim: "Guides are absent from recorded and external output by default." P2, size S,
depends on OUT-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `OUT-005-R1…`, success criteria
`OUT-005-S1…`, tasks `OUT-005-T01…`. Other features are cited by their own IDs: OUT-001 (external
display scene), OUT-002 (hot-plug, recording hold), OUT-003 (output resolution), OUT-004 (aspect
correction), OUT-012 (output rehearsal), UIX-007 (split editor), UIX-013 (scene HUD), SHOW-006 (cue
rehearsal panel), REC-001 and later (recording), CMP-002 (layer transform editor).

## Baseline: what exists today (audit of 2026-11-14, commit `a6c2cf3c`)

| Area | Today | Gap for this row |
|---|---|---|
| Guides | No guide, grid, safe-area or centre-cross overlay exists anywhere in the app or its packages. | The whole row. |
| Device-only overlays | UIX-013's HUD and SHOW-006's rehearsal panel are SwiftUI views on the device's visualizer screen. `SceneHUDAppTests` proves the external display's snapshot and a recording and Save Frame are pixel-identical with the HUD on and off. | Reuse the same isolation proof for the guides. |
| External output | OUT-001 moves the one visual's view into the external slot; the device shows a note. OUT-004 places it by Fit/Fill/Stretch, shape and pixel aspect; OUT-003 sets its pixel count. | The guides must show the output display's shape (OUT-004's pixel aspect included) when one is connected. |
| Recording | Recordings and Save Frame read the visual's own drawable (the frame-capture tap of each visual), never the window. | None: an overlay outside the visual's view cannot reach them. |
| Split editor | UIX-007 draws the visual scaled into the output pane while Settings is open on iPad. | Guides must scale with the visual. |
| Settings | The HUD toggle lives in Settings › Performance (`SceneHUDSection`). | A guides section. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: Which safe-area values are the defaults? → A: The current convention (SMPTE ST 2046-1): action-safe ("stage-safe") 93 % and title-safe 90 % of the output's width and height, centred. Rejected as defaults: the legacy 90 % / 80 % analogue values; a user who wants them sets them. Each percentage is configurable in whole percent: action-safe 80…100 %, title-safe 70…100 %; title-safe is never drawn outside action-safe (it is drawn at the smaller of the two) (OUT-005-R2, R3).
- Q: Where do the guides appear, and how are they kept out of output? → A: Only as an overlay on the device's visualizer screen (the "editor": the screen where scenes, layers and transforms are edited, including UIX-007's split output pane, where they scale with the visual). They are never part of the visual's own view, its drawable, the compositor or the external display's window, so recordings, Save Frame, offline export and the external display cannot contain them. There is no option to burn them into output (OUT-005-R1, R5).
- Q: What frame do the guides use? → A: The output's shape. With no external display showing the visual, the output is the device picture: the guides inset from the whole visual area. When an external display shows the visual, the guides draw an outline of the display's physical shape (its points × OUT-004's resolved pixel aspect ÷ its height), fitted and centred in the device's visual area, with the safe areas inside that outline (OUT-005-R4).
- Q: Is a centre cross included? → A: Yes, optional and off by default: two short centred strokes (each arm 4 % of the output frame's shorter side) (OUT-005-R3).
- Q: How is the choice stored and offered? → A: Settings › Performance, "Safe-area guides" section: a "Show guides" toggle (off by default), "Action safe" and "Title safe" sliders (whole percent, ACC-005 accessible parameters) and a "Centre cross" toggle. Four UserDefaults keys under `settings.visualizer.guides…` (absent reads the default; written on change only). They are a preference like UIX-013's HUD, so they travel with the library backup (included keys), are erased with Settings, are listed in the device test allow-list and are removed by `-uitestResetNotice`. VoiceOver: the guides are hidden from accessibility; the controls are labelled (OUT-005-R6, R7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compose inside the safe areas (Priority: P1)

A VJ building a scene for a projector turns on the guides and places a title layer and a logo so
that they stay inside title-safe and action-safe, knowing the projector or TV may crop the edges.

**Why this priority**: It is the row's observable behaviour.

**Independent Test**: The pure guide geometry is computed for portrait, landscape, 16:9, 4:3 and
square output frames, and the device screen shows the guides when they are on.

**Acceptance Scenarios**:

1. **Given** the guides on with the defaults, **When** the visualizer shows, **Then** an action-safe outline at 93 % and a title-safe outline at 90 % of the output frame are drawn, centred.
2. **Given** the user sets action-safe 90 % and title-safe 80 %, **When** the visualizer shows, **Then** the outlines move to those sizes at once.
3. **Given** the centre cross on, **When** the visualizer shows, **Then** a small cross marks the output's centre.

### User Story 2 - Guides never reach the audience (Priority: P1)

The guides are for the performer only. The projector, a recording, a saved frame and an offline
export never show them.

**Why this priority**: It is the row's acceptance: "Guides are absent from recorded and external
output by default."

**Independent Test**: With a stand-in visual on an external display window, its snapshot is
byte-identical with the guides on and off; a recording and a saved frame of a real visual are
pixel-identical with the guides on and off.

**Acceptance Scenarios**:

1. **Given** an external display shows the visual, **When** the guides are on, **Then** the external picture is identical to the picture with the guides off.
2. **Given** a recording runs, **When** the guides are on, **Then** every recorded frame and a saved frame equal the guides-off frames.

### User Story 3 - Output shape on an external display (Priority: P2)

With a 16:9 projector attached to an iPhone in portrait, the guides outline the projector's shape
on the phone, so the performer sees the safe areas of what the audience sees.

**Acceptance Scenarios**:

1. **Given** an external display of 1920 × 1080 points with square pixels, **When** the guides are on, **Then** the outline on the device has a 16:9 shape, fitted and centred.
2. **Given** OUT-004's pixel aspect set to 1.2, **When** the guides are on, **Then** the outline's shape follows the display's physical shape (width × 1.2 ÷ height).

### User Story 4 - Settings (Priority: P2)

The guides are off by default. The performer turns them on and sets the percentages in Settings;
the choice is restored after relaunch.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the visualizer shows, **Then** no guides are drawn.
2. **Given** the guides turned on and the percentages changed, **When** the app relaunches, **Then** they are restored.

### Edge Cases

- A zero or non-finite view size or output aspect: no guides drawn (nothing to inset), no crash.
- Stored percentages outside the bounds (a bad value): clamped into range.
- Title-safe set larger than action-safe: drawn at the action-safe size.
- 100 %: the outline lies on the output frame's edge.
- Output blackout (OUT-010): the guides stay on the device, the external display stays black.
- Split editor (UIX-007): the guides scale with the visual into the output pane.
- VoiceOver: the guides are never announced; the toggle and sliders are labelled.

## Requirements *(mandatory)*

### Functional Requirements

- **OUT-005-R1**: The app MUST be able to overlay safe-area guides on the device's visualizer screen only; the guides MUST NOT appear on an external display, in a recording, in a saved frame or in an offline export, and there MUST be no option to include them in output.
- **OUT-005-R2**: The guides MUST show an action-safe ("stage-safe") outline and a title-safe outline, centred in the output frame, at configurable percentages of its width and height (defaults 93 % and 90 %).
- **OUT-005-R3**: The percentages MUST be bounded (action-safe 80…100 %, title-safe 70…100 %), title-safe MUST never be drawn outside action-safe, and an optional centre cross (default off) MUST be available.
- **OUT-005-R4**: The output frame MUST be the device's visual area when the device shows the visual, and the external display's physical shape (with OUT-004's resolved pixel aspect), fitted and centred, when an external display shows it.
- **OUT-005-R5**: The guides MUST be off by default and MUST NOT change the visual, its layout, its drawable or any scene data.
- **OUT-005-R6**: The choices MUST persist in UserDefaults keys listed in the device test allow-list, the library backup policy and the UI-test reset.
- **OUT-005-R7**: Settings MUST offer the controls with VoiceOver labels and Dynamic Type; the guides themselves MUST be hidden from accessibility and MUST NOT take touches.
- **OUT-005-R8**: Public APIs only (Constitution I); builds for iOS 26 and 27; the guide geometry is pure Swift tested on the host and Linux.

### Key Entities

- **Guide choice**: shown or not, action-safe percent, title-safe percent, centre cross.
- **Guide geometry**: the output frame, the action-safe and title-safe rectangles and the centre cross, in the device view's points.

## Success Criteria *(mandatory)*

- **OUT-005-S1**: With the guides on, the external display's picture and a recorded and a saved frame are pixel-identical to those with the guides off.
- **OUT-005-S2**: For at least four output shapes (portrait, 16:9, 4:3, square) and two percentage pairs, each guide rectangle is centred in the output frame within a hundredth of a point and has the configured fraction of its width and height.
- **OUT-005-S3**: The choices persist across relaunch; nothing is stored until changed.
- **OUT-005-S4**: A UI test turns the guides on in Settings and finds them on the visualizer in under 30 s.
- **OUT-005-S5**: The existing UIX-013, OUT-001, OUT-003 and OUT-004 tests still pass.

## Assumptions

- The device's visualizer screen (with its split-editor output pane) is the "editor" of the roadmap row; Settings, the layer inspector and the CMP-002 transform editor open over or beside it.
- Simulator results are never device evidence; checking the guides with a real external display is a `{device}` task.
