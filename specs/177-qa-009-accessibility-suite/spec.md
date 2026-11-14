# Feature Specification: QA-009 Accessibility Snapshot Suite

**Feature Branch**: `feature/qa-009` (spec directory `177-qa-009-accessibility-suite`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row QA-009 (P1, size M, depends on ACC-004). Observable behavior, verbatim: "Test
primary screens at large type and VoiceOver labels." Acceptance, verbatim: "Required controls are
reachable and labelled in all tested layouts."

Identifiers carry the roadmap ID: requirements `QA-009-R1…`, success criteria `QA-009-S1…`, tasks
`QA-009-T01…`. Other features are cited by their own IDs: ACC-004 (VoiceOver labels, the system audit
with per-element filters), ACC-005 (accessible sliders), ACC-006 (Dynamic Type inspector at AX3 and AX5),
UIX-002 (scene switcher), UIX-003 (parameter inspector), UIX-004 (parameter shelf), FX-020 (effect order),
REC-005 (recording quality), REC-006 (recording frame rate), MIDI-003 (MIDI mappings), SHOW-001 (show
editor), FILE-009 (Storage), MOD-010 (parameter macros, not built yet).

## Baseline: what exists today (audit of 2026-11-14, commit `6721f9b6`)

| Area | Today |
|---|---|
| ACC-004 `AccessibilityScreensUITests` (7 tests) | Default text size. Full system audit (element description, hit region, contrast, Dynamic Type, traits) with documented per-element filters, plus "declared primary controls" (exists, label non-empty, hittable) for: visualizer controls, preset browser and a pack, Collections, My Presets, the show row, Settings top, the show editor. Announcements test. |
| ACC-006 `DynamicTypeInspectorUITests` (46 tests) | AX3 and AX5. Audit for Dynamic Type and clipped text with its own per-element filters, plus reachability (scroll, inside the window, hittable) of chosen controls on: notice and chooser, controls, Settings (OSC field), Storage, Licenses, three native visuals' rows, Text field, browser, Collections and My Presets, show editor, Scene Folders, scene switcher, Rename Scene alert, preset editor, repair sheet, Local Network and camera notices, guide. Survey mode `ACC006_SIZE`. |
| ACC-005 | `.accessibleParameter` sliders with spoken values; `VoiceOverParameterUITests` steps them through accessibility actions. |
| Newer screens | Parameter inspector (UIX-003), parameter shelf (UIX-004), effect order (FX-020), recording quality (REC-005), recording frame rate (REC-006), MIDI mappings (MIDI-003) each have a functional UI test; only the inspector's Reset/Done and the shelf at AX5 are checked for reachability. None is audited and none has its labels checked against a list. |
| Navigation aids | `-uitestSettingsSection <id>` opens Settings at a section (`color`, `reduceFlashing`, `osc`, `midi`, `show`, `recentPresets`, `storage`); `-uitestInspectParameter`, `-uitestShowSeed`, `-uitestKeepControls`. |
| Gap | No single list of the primary screens and the controls a user must reach on each; the checks are spread over two suites with different rules per layout; newer screens are not covered at large type; "labelled" means only "non-empty" (an identifier leaking as a label would pass); no fast subset for post-merge checks. Macros (MOD-010) have no screen yet. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative option that delivers the roadmap row without duplicating ACC-004 and ACC-006.

- Q: Which screens are "primary"? → A: Fourteen entries in one manifest: visualizer controls, Settings top, preset browser, scene switcher, show editor, MIDI mappings, Storage, Licenses, parameter inspector, parameter shelf (in the controls), effect order, recording quality, recording frame rate. Macros (MOD-010) are listed as "not built" and enter the manifest when their screen lands; the suite fails nothing for them.
- Q: What is a "required control"? → A: Each manifest entry names the controls a user must be able to reach on that screen to use it (by accessibility identifier and element type): the screen's actions and its main settings, not every decorative row.
- Q: Which layouts? → A: Portrait at the default text size (Large), AX3 and AX5. Landscape on iPad is not added now: it needs a second simulator and launch per screen (doubling run time), the app's layouts adapt by size class, and ACC-006 found no landscape-only defect; recorded as a later candidate.
- Q: What does "reachable" mean? → A: The control exists, and after at most one scroll gesture from where the previous required control left the screen (or from the screen's opening position for the first one) it lies wholly in the visible area and can be hit.
- Q: What does "labelled" mean? → A: The control's accessibility label is non-empty after trimming, and is not the identifier itself (no identifier or raw key leaking as the spoken name).
- Q: Which audit and which filters? → A: The system audit runs on every screen in every layout. At the default size: ACC-004's audit types and ACC-004's filter list; at AX3 and AX5: ACC-006's types (Dynamic Type, clipped text) plus element description and traits, with ACC-006's filter list. No new blanket filter is added; a per-element filter is added only for a system-drawn element with its reason, never for the app's own controls.
- Q: Runtime split? → A: The default run is default size plus AX5 for every screen (one test per screen and layout, each under 30 s). `QA009_FULL=1` (passed as `TEST_RUNNER_QA009_FULL=1`) adds AX3. Post-merge and CI-style checks run the default subset only.
- Q: What if a check finds a defect? → A: The view is fixed (label, identifier, layout); filters are never used to hide the app's own controls.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A VoiceOver user can find and name every control they need (Priority: P1) — MVP

A blind VJ moves through each primary screen with VoiceOver: every control they need to operate the
screen is announced with a meaningful name, never a code-like identifier.

**Why this priority**: It is the row's acceptance ("labelled").

**Independent Test**: For each manifest screen at the default size, every required control exists and
its label is non-empty and not its identifier.

**Acceptance Scenarios**:

1. **Given** a manifest screen opened at the default size, **When** the suite checks its required controls, **Then** each exists, has a meaningful label and passes the system audit with only the documented filters.
2. **Given** a control whose label is missing or equals its identifier, **When** the suite runs, **Then** it fails naming the screen, the layout and the control.

---

### User Story 2 - A low-vision user at the largest text size can still reach every control (Priority: P1)

A user with AX5 text opens each primary screen; text grows, rows wrap, and every required control can
still be scrolled to and tapped.

**Independent Test**: For each manifest screen at AX5 (and AX3 in the full run), every required control
is reachable within one scroll from the previous one and hittable; the audit passes.

**Acceptance Scenarios**:

1. **Given** a manifest screen at AX5, **When** the suite walks its required controls in order, **Then** each is wholly visible and hittable after at most one scroll.
2. **Given** a control pushed off screen or clipped, **When** the suite runs, **Then** it fails naming the screen, the layout and the control.

---

### User Story 3 - Maintainers keep the list honest and the run short (Priority: P2)

A developer renames an identifier; a fast check fails before any simulator run. A post-merge check runs
only the default subset in a few minutes; the full matrix runs on demand.

**Acceptance Scenarios**:

1. **Given** a manifest identifier that no longer appears in the app's source, **When** the script tests run, **Then** they fail naming the identifier.
2. **Given** no environment flag, **When** the suite runs, **Then** only the default and AX5 layouts run; **Given** `QA009_FULL=1`, **Then** AX3 runs too.

### Edge Cases

- Lazy lists build rows only near the screen: a required control not yet in the tree counts as reachable if one scroll brings it into the tree and into view.
- Settings rows deep in the list are opened at their section (`-uitestSettingsSection`) so the "one scroll" rule measures the screen, not the length of Settings above it.
- A disabled control (e.g. a recording profile the hardware cannot encode) still counts: it must be labelled and reachable; it need not be enabled.
- Navigation-bar items (Done, Edit) keep a fixed size by design (Large Content Viewer); their existing per-element filters apply.
- The visualizer's moving picture makes contrast sampling unstable: the controls are audited over a blacked-out output (ACC-004's practice).
- A manifest screen with no screen yet (macros) is listed with its status and skipped with a reason, not silently dropped.

## Requirements *(mandatory)*

### Functional Requirements

- **QA-009-R1**: There MUST be one manifest that lists every primary screen, how it is opened, and its required controls (identifier, element type), with the screen's feature ID.
- **QA-009-R2**: For each manifest screen and each tested layout, every required control MUST exist, be wholly visible in the screen's visible area and hittable after at most one scroll from the previous control's position.
- **QA-009-R3**: Every required control's label MUST be non-empty and MUST NOT equal its identifier.
- **QA-009-R4**: The system accessibility audit MUST pass on every manifest screen in every tested layout with only the existing documented per-element filters; no new type-wide or screen-wide filter.
- **QA-009-R5**: A failure MUST name the screen, the layout and the control (or the audit issue).
- **QA-009-R6**: The tested layouts MUST be portrait at the default size, AX3 and AX5; the default run MUST cover default and AX5; `QA009_FULL=1` MUST add AX3.
- **QA-009-R7**: Each test MUST run in 30 s or less on the Mac (owner rule 7); one test per screen and layout.
- **QA-009-R8**: A fast, simulator-free check MUST fail when a manifest identifier no longer appears in the app's source.
- **QA-009-R9**: Defects found MUST be fixed in the views (labels, identifiers, layout), not filtered.
- **QA-009-R10**: No app behavior change beyond accessibility fixes and DEBUG-only test aids; no new stored keys; no networking.

### Key Entities

- **Primary screen**: name, feature ID, how it is opened (launch arguments and navigation), required controls, audit filter key.
- **Required control**: accessibility identifier, element type.
- **Layout**: name and content size category (default Large, AX3, AX5), and whether it is in the default run.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **QA-009-S1**: Every manifest screen (13 built screens) passes the required-control and audit checks at the default size and AX5 (26 tests).
- **QA-009-S2**: The full run (`QA009_FULL=1`) also passes at AX3 (39 tests).
- **QA-009-S3**: Every test takes 30 s or less; the default subset finishes in under 10 minutes.
- **QA-009-S4**: Renaming any manifest identifier in the app's source makes the script tests fail.
- **QA-009-S5**: Each defect the suite finds is fixed in a view and listed in the feature report.

## Assumptions

- Simulator results are UI evidence only, never device evidence (Constitution X); a VoiceOver pass on a
  device stays with ACC-004-T12 and ACC-006-T12 {device}.
- iPhone 17 simulator, iOS 27.2, portrait; the feature's own simulator "QA9".
- ACC-004 and ACC-006 suites stay as they are (they also test announcements, alerts, notices and input);
  this suite reuses their audit filters rather than copying them.
