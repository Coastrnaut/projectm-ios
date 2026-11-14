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

- Q: Which screens are "primary"? → A: Thirteen built screens in one manifest: visualizer controls, Settings top, preset browser, scene switcher, show editor, MIDI mappings, Storage, Licenses, parameter inspector, parameter shelf (in the controls), effect order, recording quality, recording frame rate. Macros (MOD-010) are noted in the manifest as "not built" and enter the manifest when their screen lands; the suite fails nothing for them.
- Q: What is a "required control"? → A: Each manifest entry names the controls a user must be able to reach on that screen to use it (by accessibility identifier and element type): the screen's actions and its main settings, not every decorative row.
- Q: Which layouts? → A: Portrait at the default text size (Large), AX3 and AX5. Landscape on iPad is not added now: it needs a second simulator and launch per screen (doubling run time), the app's layouts adapt by size class, and ACC-006 found no landscape-only defect; recorded as a later candidate.
- Q: What does "reachable" mean? → A: The control exists, and after at most one scroll gesture from where the previous required control left the screen (or from the screen's opening position for the first one) it lies wholly in the visible area and can be hit.
- Q: What does "labelled" mean? → A: The control's accessibility label is non-empty after trimming, and is not the identifier itself (no identifier or raw key leaking as the spoken name).
- Q: Which audit and which filters? → A: The system audit runs on every screen in every layout. At the default size: ACC-004's audit types and ACC-004's filter list; at AX3 and AX5: ACC-006's types (Dynamic Type, clipped text) plus element description and traits, with ACC-006's filter list. No new blanket filter is added; a per-element filter is added only for a system-drawn element with its reason, never for the app's own controls.
- Q: Runtime split? → A: The default run is default size plus AX5 for every screen (one test per screen and layout, each under 30 s). `QA009_FULL=1` (passed as `TEST_RUNNER_QA009_FULL=1`) adds AX3. Post-merge and CI-style checks run the default subset only.
- Q: What if a check finds a defect? → A: The view is fixed (label, identifier, layout); filters are never used to hide the app's own controls.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How large is "one scroll"? → A: One held drag (no momentum) of at most 70 % of the screen's visible area, in the control's direction, made in the right-hand margin like the shared `reveal` helper; a control not yet in the tree gets the full 70 % drag.
- Q: Do the overlapping ACC-004 and ACC-006 tests get removed? → A: No. They also test announcements, alerts, notices, field input and visual-specific rows that are not in the manifest; removing them would lose coverage. The new suite is the single list of primary screens and required controls; overlap is limited to the shared audit, recorded in the plan.
- Q: How are screens that need state (shelf pins, show cues, an inspected parameter) set up? → A: With existing launch arguments only (argument-domain settings such as `-settings.parameterShelf.pins`, `-uitestShowSeed`, `-uitestInspectParameter`); no new stored keys. New DEBUG-only Settings section anchors (`.id`) may be added for rows deep in Settings.
- Q: Does a screen opened inside Settings (recording quality, frame rate) count as its own screen? → A: Yes: each is a manifest entry opened at its own Settings section, because a user reaches it as a distinct group of controls.
- Q: Are VoiceOver custom actions (Move up/down, Pin) checked? → A: No; this suite checks reachability, labels and the audit. Custom actions stay covered by their features' tests (ACC-005, FX-020, UIX-004).

### Session 2026-11-14 (speckit-implement)

Decided by Claude during implementation (owner rules 4 and 9).

- Q: A control separated from the previous one by content that grows with the text (the preset browser's pack rows before Collections at AX5: four screens) cannot be one scroll away. Fail it? → A: No: the manifest may give such a control an explicit scroll allowance with its reason (`scrolls:`), never a blanket one. Every other control keeps one scroll.
- Q: A pinned control cut off at the side of a row that scrolls sideways (the parameter shelf's strip at standard size)? → A: The one scroll may be sideways, along the row: what a user does there.
- Q: Are the visualizer's controls walked over the moving picture? → A: No: over a blacked-out output, as ACC-004 audits them (over the moving picture every query waited for the app to idle, about 1 s per control). The emergency blackout, offered only while the output is live, is checked first (`live:`).
- Q: Disabled system toolbar items that fail contrast (MIDI Mappings' Undo before any change)? → A: A per-element filter with its reason (system glass item; inactive controls are exempt from contrast), like ACC-004's system Done.
- Q: System list section headers and footers on the newly audited screens (Effect order, MIDI Mappings, Licenses, the inspector) draw "contrast nearly passed" and "Dynamic Type partially unsupported" findings, a different one each run? → A: Per-element filters naming each header and footer text, for those two audit types only, with ACC-004's reason (Apple's secondary grey; a header pushed off the list at the audit's sizes). Never the app's own controls. The inspector's label-and-value rows get a Dynamic Type filter at the default size only, because they re-lay out while the audit changes the size and the AX5 audit of the same screen passes with Dynamic Type checked.
- Q: Settings sections opened by a jump (recording quality, frame rate): audit at the default size? → A: No (ACC-006's rule: no Settings audit at a jumped-to position; the default-size audit there reports the edge rows as pushed off). Settings is audited at its top by the `settings` entry, and these sections are audited at AX3 and AX5. Their required controls are checked at every layout.
- Q: How exact is "wholly visible"? → A: Within 4 pt of the visible area: the visualizer's controls end 2 pt past their scroll view's frame at AX5 (rounding of the scaled grid in its backing), and a touch there still lands on the control. Drags run in the right-hand lane of the scroll view that holds the control (the switcher's card is narrower than the window).
- Q: Where do the drags run? → A: At 88 % of the width of the scroll view that holds the control, not the shared `reveal`'s 96 %: on a long list the right margin catches the scroll indicator, which scrubbed the preset browser back to its top at AX5 (as LibraryEraseUITests had seen).
- Q: The scene switcher over the live picture? → A: Opened over a blacked-out output, as ACC-004 audits the controls; the card is now modal for VoiceOver (the dimmed controls behind it were reachable) and its placeholder uses the secondary label colour (the system placeholder grey on the dark card failed contrast). One or two contrast findings the audit attributes to a bare SwiftUI node with no element stay a bounded (two) open item.
- Q: What counts as "can be hit" for a control that wraps the system control (ACC-005's accessible slider: an element around the Slider) or a text field that already has the keyboard focus (the scene switcher's query, focused on open)? → A: Hit when the wrapper or its first child is hittable; a field holding the keyboard focus takes input without a touch.
- Q: The scene switcher's rows are reported not hittable by XCTest in most runs (entry 1 always, others now and then), yet a touch at entry 1's centre chooses it and closes the switcher (probe, 2026-11-14)? → A: The rows keep the presence, label and view checks; their hit test is waived per control (`hitTest: false`, the only use) and recorded as an open finding for UIX-002. The probe also found two real defects, now fixed: the rows exposed their thumbnail ("Stack Of Rectangles") and play mark ("Play") as separate elements (now hidden; the row's value already says "current"), and the tappable backdrop stayed in the accessibility tree as an unlabelled element across the screen despite `.accessibilityHidden(true)` (now a described "Close scenes" button).

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
- **QA-009-R11**: One scroll MUST be one held drag of at most 70 % of the visible area; screens needing state MUST be set up with existing launch arguments (no new stored keys).

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

## Analysis (speckit-analyze, 2026-11-14)

- I1 (medium, fixed): the screen count read "Fourteen entries" against S1's 13; now 13 built screens plus a not-built note for macros.
- C1 (medium, fixed): S3's 10-minute default-subset budget had no measuring task; QA-009-T05 now records per-test and total times.
- Coverage: 11/11 requirements have tasks; no constitution issues; 0 critical.
