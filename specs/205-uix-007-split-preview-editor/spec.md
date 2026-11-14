# Feature Specification: UIX-007 Split Preview/Editor

**Feature Branch**: `feature/uix-007` (spec directory `205-uix-007-split-preview-editor`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-007 (split preview/editor) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Keep live output visible while
editing properties on iPad." Acceptance, verbatim: "Resizing editor never distorts output aspect
ratio." P1, effort L, depends on CMP-015 (integrated)."

Identifiers carry the roadmap ID: requirements `UIX-007-R1…`, success criteria `UIX-007-S1…`, tasks
`UIX-007-T01…`, research decisions `UIX-007-D1…`. Other features are cited by their own IDs: CMP-015
(layer inspector), UIX-003 (parameter inspector), UIX-004 (parameter shelf), UIX-005 (performance
layout), MOD-012 (modulation matrix), OUT-001/OUT-004/OUT-010 (external display, aspect correction,
blackout), REC-003 (video recording), SCN-010 (scene undo), FILE-005/FILE-011 (settings backup and
erase), ACC-004/ACC-006 (VoiceOver, Dynamic Type), FR-065 (what the app stores).

## Baseline: what exists today (audit of 2026-11-14, commit `3a052dc4`)

| Area | Today |
|---|---|
| Property editors | Settings (`SettingsView`, a `NavigationStack` list) opens as a sheet from the controls' Settings button on every device. On iPad that is a centred form sheet over the visual; the live output is dimmed and mostly covered. CMP-015 Layers (Settings › Layers, per-layer detail with undo), MOD-012 Modulation, the show editor, colour grade, effect chain, and all visual options are pushed inside that stack. UIX-003's parameter inspector is a sheet over Settings. |
| Output sizing | The visual is a UIKit view held by a `VisualSlotView` (OUT-001) and fills the window, ignoring the safe area. The device slot reports its size to `ExternalDisplayCoordinator`, which derives the device shape (OUT-004 "Device" shape) from it; the renderer's drawable, recordings (REC-003) and frame captures follow the view's bounds. |
| Aspect handling | OUT-004 `ExternalOutputPlacement` (pure, in `PresentationLifecycle`) letterboxes the visual on an external display; nothing letterboxes it on the device. |
| Geometry pattern | UIX-005 `PerformanceLayout` (pure value type in `ShowControl`, host- and Linux-tested) computes the performance pad's arrangement from the space; the view reports insets. |
| Shelf | UIX-004's parameter shelf sits inside the visualizer controls (not an editor sheet). |

Gap confirmed: no editor on iPad leaves the output visible; nothing keeps the output's shape when an
editor takes space.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Which editor becomes the split? → A: Settings, the app's property editor. Everything reached inside it (Layers and layer details from CMP-015, Modulation from MOD-012, visual options, colour grade, effects, show editor) is in the editor pane, because those screens are pushed inside Settings' navigation stack. Sheets presented from inside Settings (UIX-003's parameter inspector, permission explainers, file pickers, scene repair) stay sheets. Rejected: a new separate editor screen (duplicates Settings).
- Q: When is the split used instead of the sheet? → A: When the visualizer's horizontal size class is regular and the window is at least wide enough for the narrowest editor plus the narrowest output pane (UIX-007-R2 numbers). iPhone, iPad Slide Over and narrow iPad split views (compact width) keep today's sheet unchanged. The choice follows the current width: if the window becomes compact while Settings is open, Settings continues as a sheet, and the other way round.
- Q: Where is the editor? → A: On the trailing side, the live output on the leading side (reading order: what you see, then what you change; matches iPadOS inspectors).
- Q: How is the output shown in its pane? → A: The whole output (the full-window picture) is scaled uniformly to fit the output pane and centred, with black bars where the shapes differ (letterbox or pillarbox). The output's shape is the shape of the full window, so opening the editor never changes the picture's shape; only its on-screen size changes. Rejected: re-laying the visual out at the pane's shape (changes the rendered shape, the drawable, recordings and OUT-004's device shape).
- Q: How wide is the editor? → A: Bounded between 320 pt and 560 pt, and never wider than the window minus a 320 pt output pane. Snap points at 320 (Narrow), 400 (Standard, the first-time width) and 480 pt (Wide). A drag moves the divider freely within the bounds; on release it snaps to the nearest snap point within 24 pt, otherwise it stays where it was released.
- Q: Is the width remembered? → A: Yes, the last editor width is stored on this device (one new key, `settings.splitEditor.width`). It depends on this device's screen, so it is never backed up (FILE-005 excluded key) and is erased with the Settings category (FILE-011). Rejected: not stored (a performer would re-drag every time).
- Q: How is the divider accessible? → A: It is one VoiceOver element "Editor width" whose value is the width in points plus the snap name ("400 points, Standard"), adjustable: swipe up widens to the next snap point, swipe down narrows to the previous one. It is a 24 pt wide hit area with a visible grip; pointer hover shows the resize cursor shape where available. Keyboard: no new shortcut.
- Q: How does the split close? → A: Done in Settings' navigation bar closes it, as it closes the sheet today; closing ends the SCN-010 undo coalescing and commits the autosave exactly as before.
- Q: What happens to the controls and badges while the split is open? → A: They stay in the output pane, laid out to its width (not scaled), so badges, notices and the controls never sit under the editor. The tap target covers only the output pane.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does the output follow the divider live during a drag, or only when the drag ends? → A: Live: the output pane and the scaled output follow the finger on every drag change (the visual is only rescaled, not re-laid out, so this costs no rendering work); the snap on release animates over 0.2 s, instantly with Reduce Motion (ACC-001).
- Q: What fills the output pane outside the output rect? → A: Black (the visualizer's existing black background), never a blurred or stretched copy; the bars are not hit-testable beyond the pane's tap target.
- Q: Is there a minimum output scale? → A: No separate minimum: the 320 pt minimum output pane bounds it (at 320 pt in a 1366 × 1024 window the output is 320 × 240 pt).
- Q: Does the split change where the performance overlay (FR-048) and the debug probes sit? → A: They stay in the output pane with the rest of the status layers; nothing is added to the editor pane except Settings.
- Q: How do UI tests read the output's on-screen frame? → A: A DEBUG `-uitestDiagnostics` probe `splitOutputFrame` gives the device slot's frame in window coordinates ("x,y,w,h") and the window size, measured from the view hierarchy (not the computed layout), so a test checks what is actually shown.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Edit properties beside the live output on iPad (Priority: P1)

A VJ on an iPad opens Settings while a preset plays. The editor opens beside the output, which keeps
playing, uncovered, in its pane. They open Layers, change a layer's opacity, and watch the effect live.

**Why this priority**: It is the roadmap row's behavior.

**Independent Test**: On an iPad simulator in landscape, open Settings from the controls: the split
editor exists, no sheet is shown, the output frame lies inside the output pane and the visual keeps
running.

**Acceptance Scenarios**:

1. **Given** an iPad in regular width with the visual running, **When** Settings opens, **Then** the editor appears on the trailing side and the output stays visible and running on the leading side.
2. **Given** the split is open, **When** Done is tapped, **Then** the editor closes and the output fills the window again.
3. **Given** an iPhone (compact width), **When** Settings opens, **Then** it opens as a sheet as before.

---

### User Story 2 - Resize the editor without distorting the output (Priority: P1)

The VJ drags the divider to give the editor more room. The output shrinks or grows but its shape never
changes; black bars fill the rest of the pane.

**Why this priority**: It is the roadmap row's acceptance.

**Independent Test**: Drag the divider; the output frame's width ÷ height equals the full window's
width ÷ height (within rounding) before and after, and the frame lies inside the output pane.

**Acceptance Scenarios**:

1. **Given** the split is open, **When** the divider is dragged to any width, **Then** the output's aspect ratio is unchanged and it is centred in its pane.
2. **Given** a drag released within 24 pt of a snap point, **Then** the editor settles at that snap point.
3. **Given** the device rotates while the split is open, **Then** the output takes the new window's shape, still undistorted, and the editor width is clamped to the new bounds.

---

### User Story 3 - Resize the editor with VoiceOver (Priority: P2)

A VoiceOver user focuses the divider, hears "Editor width, 400 points, Standard, adjustable", and
swipes up to widen it to Wide.

**Independent Test**: The divider is one adjustable element with label and value; increment and
decrement step through the snap points within the bounds.

**Acceptance Scenarios**:

1. **Given** the divider at Standard, **When** incremented, **Then** the width becomes 480 pt (Wide) and the value says so.
2. **Given** the divider at its narrowest, **When** decremented, **Then** nothing changes.

### Edge Cases

- A window too narrow for 320 + 320 pt plus the divider: the sheet is used.
- A stored width larger than the current maximum (rotation to portrait, a smaller window): the width shown is clamped; the stored width is unchanged until the user moves the divider.
- A corrupt or missing stored width: Standard (400 pt).
- The visualization is on an external display (OUT-001): the output pane shows the device note on black as today; the external display is unaffected.
- A recording or a frame capture runs while the split opens or resizes: the recorded or captured frame's size is unchanged (the visual is not re-laid out).
- Blackout (OUT-010) while the split is open: the output pane shows black and the badge, as full screen.
- Performance layout (UIX-005) on while the split opens: the pad lays out in the output pane.
- The pane area outside the output rect is black.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-007-R1**: In regular horizontal width, opening Settings MUST show it as an editor pane beside the live output instead of a sheet; in compact width it MUST stay a sheet.
- **UIX-007-R2**: The editor width MUST stay within 320–560 pt and leave an output pane of at least 320 pt; if the window cannot fit both, the sheet MUST be used.
- **UIX-007-R3**: The output MUST be shown uniformly scaled to fit its pane and centred, so its aspect ratio equals the full window's aspect ratio (within 1e-6 in the geometry, within on-screen rounding in the app) for every editor width, and its frame MUST lie inside the output pane.
- **UIX-007-R4**: Resizing the editor MUST NOT change the visual's rendered size or shape (drawable, recordings, frame captures, OUT-004's device shape).
- **UIX-007-R5**: The divider MUST be draggable, the output following live; on release it MUST snap to the nearest of 320, 400, 480 pt within 24 pt.
- **UIX-007-R6**: The divider MUST be a single accessible, adjustable element ("Editor width", value in points and snap name) whose increment and decrement move to the next and previous snap point within the bounds.
- **UIX-007-R7**: The last editor width MUST be remembered on this device under `settings.splitEditor.width`, never backed up, erased with Settings, removed by the UI-test reset; missing or invalid → 400 pt.
- **UIX-007-R8**: Done MUST close the split with the same effects as closing the sheet (SCN-010 coalescing boundary, autosave commit).
- **UIX-007-R9**: While the split is open, the status stack, controls, badges and the tap target MUST lie in the output pane.
- **UIX-007-R10**: DEBUG builds MUST expose a probe (`splitOutputFrame`) of the output's on-screen frame, measured from the view hierarchy, and the window size for UI tests (no Release cost).

### Key Entities

- **Split editor layout**: from the window size, the requested editor width and the output aspect: the clamped editor width, the output pane, the divider, the output rect (exact aspect) and its scale.
- **Editor width preference**: one stored number (points) on this device.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-007-S1**: For representative editor widths (minimum, each snap point, maximum, odd values) in landscape and portrait window sizes, the output rect's aspect equals the output aspect within 1e-6 and the rect lies inside its pane.
- **UIX-007-S2**: On an iPad simulator, after dragging the divider, the output's on-screen aspect equals the window's aspect within 1% (point rounding) and its width changed.
- **UIX-007-S3**: On iPhone, Settings still opens as a sheet (existing Settings UI tests stay green).
- **UIX-007-S4**: On an iPad (D2), a person confirms the output stays visible and undistorted while resizing (device pass).

## Assumptions

- The full window is the output's shape on the device (the visual fills the window today).
- Sheets launched from inside Settings stay sheets (scope); they may cover part of the output while shown.
- Simulator results are never device evidence; S4 is the `{device}` pass on D2.
