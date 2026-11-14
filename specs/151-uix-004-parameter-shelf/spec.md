# Feature Specification: UIX-004 Favorite Parameter Shelf

**Feature Branch**: `feature/uix-004` (spec directory `151-uix-004-parameter-shelf`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement UIX-004 (favorite parameter shelf) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Pin frequently used parameters to a
customizable strip." Acceptance, verbatim: "Pinned controls persist and missing IDs are reported safely."
P1, effort M, depends on MOD-001 (integrated)."

Identifiers carry the roadmap ID: requirements `UIX-004-R1…`, success criteria `UIX-004-S1…`, tasks
`UIX-004-T01…`, research decisions `UIX-004-D1…`.

## Baseline: what exists today (audit of 2026-11-14, commit `4bad23aa`)

| Area | Today |
|---|---|
| Registry | MOD-001: `VisualParameterCatalog` registers 14 visual parameters (ID, name, group, unit, kind, default, step hint). |
| Edit paths | UIX-003: `ParameterInspectorTargets.target(for:settings:)` gives get/set over the `AppSettings` property each of the seven Settings controls writes (Glow, Intensity, Radius, Threshold, Bars, Orientation, Spacing). The other seven registry parameters have no app control (read-only). |
| Entry points | UIX-003: an "Inspect" context menu item and VoiceOver action on those seven Settings controls; the inspector sheet over Settings; DEBUG `-uitestInspectParameter <id>`. |
| Visualizer controls | `ControlsOverlay` (shown and hidden with the controls; auto-hide; scrolls at accessibility text sizes, ACC-006-R2). Blackout (OUT-010) blacks out the output but never hides the controls; the performance overlay is a separate readout and hides nothing. |
| Accessibility | ACC-005 `.accessibleParameter` (slider label, spoken value, swipe steps); ACC-006 Dynamic Type rules; ACC-001 Reduce Motion policy. |
| Storage | Device settings in UserDefaults; every key is listed in `run_device_tests.py` `ALLOWED_KEYS`, in FILE-005 `LibrarySettingsPolicy` (included or excluded) and is cleared by `-uitestResetNotice`. |

No pinning, shelf or favorite-parameter concept exists: the gap is confirmed.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Which parameters can be pinned? → A: Only registry parameters that have an app control (the seven UIX-003 inspectable parameters), because a shelf control must write through the same path as Settings. Read-only parameters cannot be pinned.
- Q: Where is "Pin to Shelf" offered? → A: In the "Inspect" context menu of the seven Settings controls (also a VoiceOver action) and in the inspector sheet. A pinned parameter offers "Remove from Shelf" in the same places.
- Q: Where is the shelf? → A: A strip inside the visualizer's controls overlay, shown only while the controls are visible and only when it has pins (or a missing-pins note). It scrolls horizontally at standard text sizes and stacks vertically at accessibility sizes (the overlay already scrolls there).
- Q: What controls does the shelf hold? → A: A compact control built from the registry descriptor: a slider for continuous values (with `.accessibleParameter`), a toggle for booleans, a menu picker for enums and choice-only values. Each writes through the same setting as Settings.
- Q: How are pins ordered and managed? → A: A "Parameter Shelf" section in Settings lists the pins in shelf order with Edit (drag to reorder, delete) and VoiceOver actions "Move up", "Move down" and "Remove from Shelf". New pins are added at the end.
- Q: How many pins? → A: At most 8 available pins; at the limit the menu item is disabled and reads "Shelf Full (8)" (the reason, also read by VoiceOver).

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: How are pins stored? → A: An ordered list of parameter ID strings under one new UserDefaults key, `settings.parameterShelf.pins`, added to the allowed keys, to the library backup's included keys (a layout preference that travels with the library like the effect-chain order) and to the UI-test reset.
- Q: What happens to a stored ID this version does not know (removed later, a corrupt value, or a registered parameter without a control)? → A: It is skipped in the shelf, counted, and reported in one note: "1 pinned control is no longer available" / "N pinned controls are no longer available", with a Remove action that deletes only those entries. It is logged once per launch (count only; the values are private), never crashes, and is kept in storage until the user removes it, so a downgrade and upgrade round-trips.
- Q: What about stored values that are not strings, or a value that is not a list? → A: Each non-string element (and a non-list value) is turned into its text form and treated as one unavailable entry, so it is counted, reported and removable like any unknown ID. Duplicate IDs keep their first position; later copies are dropped silently on load.
- Q: Do unavailable entries count toward the limit of 8? → A: No. The limit counts available pins only, so an old unknown entry never blocks pinning.
- Q: Does the shelf hide with blackout or the performance overlay? → A: It follows the controls exactly: it hides when they hide (auto-hide, Settings, sheets) and stays while they stay. Blackout does not hide the controls (the restore button must stay reachable), so it does not hide the shelf either.
- Q: Are pin and unpin announced? → A: No extra announcement: the button's label changes ("Pin to Shelf" / "Remove from Shelf") and VoiceOver reads it. Value changes through a shelf slider use ACC-005's spoken values.
- Q: Does a shelf edit join the scene history? → A: Yes, as a Settings edit would: it writes the same setting, and a slider drag or each VoiceOver swipe ends one undo step.
- Q: Does touching the shelf keep the controls up? → A: Yes, every shelf change restarts the controls' auto-hide like any other control.
- Q: Are the pins part of a saved scene or cue? → A: No. The shelf is a device layout preference, not visual state: scenes, cues and the scene history never record or change it (no scene field is added).
- Q: What happens to the pins when the user erases Settings (FILE-011)? → A: They are erased with the Settings category, because the erase derives from the backup's included keys; the shelf is then empty.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pin and use favorite controls (Priority: P1)

A performer adjusts the glow intensity and the bar count many times a show. They long press each in
Settings, choose Pin to Shelf, and close Settings: the two controls sit in a strip with the visualizer's
controls, and changing them there changes the visual exactly as Settings does.

**Independent Test**: Pin a parameter from the inspector, close Settings, change it on the shelf, and read
the setting.

**Acceptance Scenarios**:

1. **Given** no pins, **When** the user pins Intensity, **Then** the shelf appears in the controls with an Intensity slider showing the current value.
2. **Given** a pinned slider, **When** the user moves it, **Then** the stored setting equals what the same value set through Settings stores.
3. **Given** 8 pins, **When** the user opens the menu of a ninth control, **Then** Pin to Shelf is disabled with the reason.

---

### User Story 2 - Pins persist in their order (Priority: P1)

**Independent Test**: Pin three parameters, relaunch, and read the shelf.

**Acceptance Scenarios**:

1. **Given** three pins in a chosen order, **When** the app relaunches, **Then** the same three controls appear in the same order.
2. **Given** pins, **When** the user reorders them in Settings (drag or VoiceOver Move up/down), **Then** the shelf shows the new order, also after relaunch.

---

### User Story 3 - Missing pins are reported safely (Priority: P1)

**Independent Test**: Store a list with valid IDs, an unknown ID and a garbage value, and launch.

**Acceptance Scenarios**:

1. **Given** a stored list with two valid IDs, one unknown ID and one garbage value, **When** the app launches, **Then** the shelf shows the two valid controls, a note says "2 pinned controls are no longer available", and nothing crashes.
2. **Given** that note, **When** the user taps Remove, **Then** only the two unavailable entries are deleted; the valid pins stay in order.
3. **Given** an unknown entry and no Remove, **When** the app relaunches, **Then** the entry is still stored (a downgrade and upgrade round-trips).

### Edge Cases

- The stored value is not a list, or holds non-string elements: each becomes one unavailable entry (reported, removable).
- Duplicate IDs: the first position wins.
- A pinned parameter whose control is hidden in Settings (for example Glow off hides the sliders): the shelf control still writes the setting (it controls the parameter, not the row).
- Pinning the same parameter twice: impossible; the menu offers Remove from Shelf instead.
- The shelf at the largest accessibility text size: controls stack and the overlay scrolls; nothing is clipped.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-004-R1**: The "Inspect" context menu of each of the seven Settings controls, and the inspector sheet, MUST offer "Pin to Shelf" for an unpinned parameter and "Remove from Shelf" for a pinned one; both are also VoiceOver actions on the control.
- **UIX-004-R2**: Only registry parameters with an app write path MUST be pinnable; at most 8 available pins, and at the limit Pin to Shelf is disabled with the reason.
- **UIX-004-R3**: The controls overlay MUST show the shelf (pins in order) only while the controls are visible and the shelf has pins or a missing-pins note.
- **UIX-004-R4**: Each shelf control MUST be built from the registry descriptor (slider, toggle or picker) and write through the same setting as Settings, ending one undo step per drag, swipe or choice.
- **UIX-004-R5**: The pins MUST be stored as an ordered list of parameter ID strings under `settings.parameterShelf.pins`, and restored in the same order on launch.
- **UIX-004-R6**: The Settings "Parameter Shelf" section MUST list pins in order and allow reordering (Edit mode drag; VoiceOver Move up / Move down) and removal.
- **UIX-004-R7**: Stored entries that are not available (unknown, corrupt, not a string, or without a control) MUST be skipped without a crash, reported as one note with the exact count, logged once per launch, and kept until removed.
- **UIX-004-R8**: The note's Remove action MUST delete exactly the unavailable entries and keep the available pins in order.
- **UIX-004-R9**: Every shelf control MUST be one VoiceOver element with its label and spoken value (sliders through `.accessibleParameter`); at accessibility text sizes the shelf stacks instead of scrolling sideways.
- **UIX-004-R10**: The new key MUST be in the allowed keys list, in the library backup's included keys (so the Settings erase clears it), and cleared by the UI-test reset; no scene field is added.

### Key Entities

- **Shelf entry**: one stored string; available when it names a registered parameter with an app control.
- **Shelf**: the ordered entries; available pins (in order, at most 8) and unavailable entries (count, kept).

## Success Criteria *(mandatory)*

- **UIX-004-S1**: After pinning three parameters and relaunching, the shelf shows the same three in the same order (100% of runs).
- **UIX-004-S2**: With a stored list containing unknown and garbage entries, the shelf shows only the valid pins, the note's count equals the number of unavailable entries exactly, and Remove leaves only the valid pins; no crash.
- **UIX-004-S3**: A value written through the shelf stores exactly what the same value written through Settings stores.
- **UIX-004-S4**: A user can pin a parameter, see it in the controls, change it and find it still pinned after relaunch in under 30 seconds (the UI test's budget).

## Assumptions

- The registry and UIX-003's write targets are unchanged; when a later row adds controls, its parameters become pinnable automatically.
- The library backup restores the key like other string-list settings; unknown IDs in a restored list follow R7.
