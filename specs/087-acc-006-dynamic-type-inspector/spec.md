# Feature Specification: ACC-006 Dynamic Type Inspector

**Feature Branch**: `feature/acc-006` (spec directory `087-acc-006-dynamic-type-inspector`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ACC-006 (Dynamic Type inspector) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md (line 454). Observable behavior, verbatim: "Support large text
sizes without clipping core controls." Acceptance, verbatim: "Accessibility text sizes preserve scroll
and edit affordances." P0, size M, depends on UIX-001 (integrated). Verification: accessibility
unit/UI tests, then the device last (D1 at the largest accessibility size, plus an iPad)."

Identifiers in this feature carry the roadmap ID: requirements `ACC-006-R1…`, success criteria
`ACC-006-S1…`, tasks `ACC-006-T01…`, research decisions `ACC-006-D1…`. Other features are cited by
their own IDs: FR-070 (feature 001 accessibility), ACC-004 (VoiceOver scene browser and its
per-screen audit suite, contracts/accessibility-tree.md in spec 082), ACC-001 (Reduce Motion and
`MotionPolicy`), UIX-001 (guided first scene), SCN-012 (scene repair sheet), FILE-013 (permission
notices), PRE-015 (user preset editor), SHOW-001 / SCN-003 (show editor and rename alerts), QA-009
(accessibility snapshot suite, later; builds on this feature).

## What "inspector" means here

The app has no screen called an inspector. In this feature the inspector is **a way to check every
core screen at every accessibility text size**: a UI test suite that walks the core screens at a
chosen text size, runs the system's Dynamic Type and clipped-text audit on each one, and checks that
scrolling, text entry and buttons still work. A survey switch runs the same walk at any size
(AX1-AX5, or the largest standard size). The fixes the walk finds are part of the feature.

Core screens: the visualizer controls (compact and regular width), Settings (each visual's rows,
OSC, Storage, Licenses), the preset browser with a pack, Collections and My Presets, the show editor
and its rename alerts, the user preset editor, the scene repair sheet, the permission notices, the
guided first scene, the photosensitivity notice and the source chooser.

## Baseline: audit at AX5 (2026-11-13, commit `08d7747`, own iOS 27.2 iPhone 17 simulator)

First walk of the inspector suite at the largest accessibility size, before any fix:

| # | Screen | Finding | Kind |
|---|---|---|---|
| B1 | Controls | The source indicator ("In-Ap…"), the tempo readout ("12…", "Dete…") and the tap button shared one row: indicator and readout truncated, readout reported "Text clipped" | clipping |
| B2 | Controls | Audio route ("Outp…eaker"), current preset, scope line and track title held to one line with the middle cut | truncation without alternative |
| B3 | Controls | With the transport, route, a notice and the button grid, the controls fill the whole screen; with anything more (show row, a notice) the top would go off screen with no way to scroll | lost scroll affordance |
| B4 | Camera / Local Network notice | Symbol, text and Open Settings side by side: "Came…" and "Ope…", both reported "Text clipped" | clipping |
| B5 | User preset editor | The one-line Name field shows a clipped slice of a long name ("Text clipped") | clipping |
| B6 | Scene repair sheet | Three full-width buttons pinned under the list leave the report little room; the last group could not be scrolled into full view | lost scroll affordance |
| B7 | Settings | Very long at AX5 (the Visual footer alone is several screens); every row is reachable by scrolling, nothing clipped | none (recorded) |
| B8 | Navigation-bar Done / Cancel / Save, system alerts, large titles ("Choose sou…") | System bar items and alert text do not scale or truncate by design; iOS offers the Large Content Viewer on long press | system (filtered with reason) |
| B9 | Notice, chooser, browser, pack, Collections, My Presets, show editor, guide | No clipping; ACC-004's "rows pushed off screen" entries do not appear when the screen starts at AX5 | none |

## Clarifications

### Session 2026-11-13

(Answered under the owner's standing delegation, rule 4: recommended option chosen.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use every core control at the largest text size (Priority: P1)

A person who reads with the largest accessibility text size opens the app, starts a source and uses
the visualizer controls, Settings, the browser and the editors. Text wraps instead of being cut, and
every control can still be seen and tapped.

**Why this priority**: it is the roadmap's observable behavior; clipped controls lock these users out.

**Independent Test**: launch at AX5, open each core screen, check that no text is clipped and every
listed control lies inside the window and can be hit.

**Acceptance Scenarios**:

1. **Given** AX5 and In-App Playback running, **When** the controls are shown, **Then** the status,
   tempo, route and preset name are readable without truncation and every button can be tapped.
2. **Given** AX5 and a denied or restricted permission, **When** its notice is shown, **Then** the
   whole text and Open Settings are readable and Open Settings can be tapped.
3. **Given** AX5, **When** the user preset editor opens on a long name, **Then** the whole name is
   visible.

---

### User Story 2 - Scroll and edit still work at large sizes (Priority: P1)

At accessibility sizes, content taller than the screen scrolls, the last control of every long screen
can be reached, and text fields accept typing.

**Why this priority**: the roadmap's acceptance: "accessibility text sizes preserve scroll and edit
affordances".

**Independent Test**: at AX5 and AX3, scroll each long screen to its last control and tap it; type
into the rename fields, the preset editor, the OSC port and the Text visual's message.

**Acceptance Scenarios**:

1. **Given** AX5 and controls taller than the space above them, **When** the user drags inside the
   controls, **Then** they scroll and every control can be reached; the controls do not auto-hide
   while being scrolled.
2. **Given** AX5, **When** the scene repair sheet is open, **Then** the report and its buttons scroll
   together and every group and button can be reached.
3. **Given** AX5, **When** a Rename Scene alert or the preset editor is open, **Then** typed text
   appears in the field.

---

### User Story 3 - A repeatable inspector catches regressions (Priority: P1)

A developer runs one suite that walks every core screen at AX5 and AX3 and fails on any new clipped
text, unreachable control or field that refuses input; with a survey switch it walks at any other size.

**Why this priority**: without it the fixes regress as screens grow (Settings grows every feature).

**Independent Test**: run the suite; it passes with only the documented system filters; adding a
one-line `Text` with a long string to a screen makes it fail.

**Acceptance Scenarios**:

1. **Given** the suite, **When** it runs at AX5 and AX3, **Then** each test finishes in under 30 s and
   every unfiltered audit issue is listed in one failure with a screenshot.
2. **Given** the survey switch set to AX1, AX2, AX4 or the largest standard size, **When** the suite
   runs, **Then** it walks the same screens at that size.

### Edge Cases

- Regular width (iPad) at accessibility sizes: the controls already switch to the compact grid
  (FR-070, ACC-004), so the AX layout is the same on iPhone and iPad; the iPad is checked on the device.
- Landscape iPhone at AX5: less height, so the controls scroll sooner (same mechanism).
- Standard sizes: layouts unchanged (no visual change below AX1).
- Reduce Motion: the change between stacked and side-by-side layouts happens only when the text size
  changes, with no animation (nothing new goes through `MotionPolicy`).
- VoiceOver: the controls already stay up while VoiceOver runs; scrolling them restarts the
  auto-hide for everyone else.
- System-owned elements (bar buttons, alerts, large titles) are not the app's to resize: filtered with
  a reason, never a whole screen or audit type.

## Requirements *(mandatory)*

### Functional Requirements

- **ACC-006-R1**: At accessibility text sizes no core control's text may be clipped or truncated
  without an alternative: rows that put text beside text or a button stack vertically; one-line
  names (preset, visual, scope, track, route) wrap up to three lines; numerals may shrink only where
  decorative.
- **ACC-006-R2**: Content that can exceed the screen at accessibility sizes MUST scroll: the
  visualizer controls scroll inside their backing when taller than the space above them, and the scene
  repair sheet's buttons scroll with the report. Scrolling the controls restarts their auto-hide.
- **ACC-006-R3**: Text fields on core screens (rename alerts, user preset editor name and text, OSC
  port, the Text visual's message, the guide's message) MUST accept typed input at AX5; the preset
  editor's name wraps at accessibility sizes and stays one line of text (Return becomes a space).
- **ACC-006-R4**: Every core screen's primary buttons MUST be reachable without a hidden gesture at
  AX5, or have a visible or VoiceOver alternative (ACC-004 actions) when the action lives in a swipe or
  context menu; the inspector checks the visible ones.
- **ACC-006-R5**: Standard text sizes keep today's layouts.
- **ACC-006-R6**: An inspector UI suite walks every core screen at AX5 and AX3 and runs the system
  Dynamic Type and clipped-text audit with per-element documented filters; a survey switch
  (`TEST_RUNNER_ACC006_SIZE`) runs it at any size and (`TEST_RUNNER_ACC006_SURVEY`) lists every issue
  instead of stopping at the first.
- **ACC-006-R7**: ACC-004's Dynamic Type filters are removed where the fixes or the AX5 start make them
  unnecessary, and its contract records which remain and why.
- **ACC-006-R8**: Nothing of the inspector ships: no in-app inspector code in Release builds.

### Key Entities

- **Audit filter**: screen, audit type, element (identifier or label), reason. Never a whole type or
  screen.
- **Screen group**: the screens one test walks (one launch, under 30 s).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ACC-006-S1**: At AX5 and AX3, zero unfiltered Dynamic Type or clipped-text audit issues on every
  core screen (simulator), in two consecutive runs.
- **ACC-006-S2**: At AX5 and AX3, the last control of every long screen is reached by scrolling and
  can be hit; every listed field shows typed text.
- **ACC-006-S3**: Each inspector test finishes in under 30 s on the Mac.
- **ACC-006-S4**: The existing suites of every changed screen still pass.
- **ACC-006-S5**: On D1 at the largest accessibility size, and on an iPad, a person can use every core
  screen without clipped controls (device pass, last).

## Assumptions

- The system audit (`performAccessibilityAudit`, types Dynamic Type and text clipped) is the
  measurement of record on the simulator; it inspects only what is on screen, so the suite scrolls
  long screens' late rows into view before auditing.
- "Largest non-AX size" (`UICTContentSizeCategoryXXXL`) and AX1/AX2/AX4 are covered by the survey
  switch, not by fixed tests (owner rule 7: short tests).
- Simulator results are never device evidence; the device pass is a `{device}` task.
