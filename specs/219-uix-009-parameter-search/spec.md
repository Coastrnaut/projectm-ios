# Feature Specification: UIX-009 Parameter Search

**Feature Branch**: `feature/uix-009` (spec directory `219-uix-009-parameter-search`)

**Created**: 2026-11-14

**Status**: Clarified

**Input**: User description: "Implement UIX-009 (Parameter search) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Search editable parameters by name, group and unit." Acceptance, verbatim:
"Query finds matching IDs regardless of current layer selection." Verification: SwiftUI UI tests + simulator.
P1, size S, depends on MOD-001."

Identifiers in this feature carry the roadmap ID: requirements `UIX-009-R1…`, success criteria `UIX-009-S1…`,
research decisions `UIX-009-D1…`, tasks `UIX-009-T01…`. Other features are cited by their own IDs: MOD-001
(typed parameter registry), UIX-003 (parameter inspector), UIX-004 (parameter shelf), CMP-015 (layer
inspector), MOD-012 (modulation matrix), PRE-001/PRE-003 (preset search folding).

## Baseline: what exists today (audit of 2026-11-14, commit `0002a60f`)

| Question | Today |
|---|---|
| Parameters | MOD-001 `VisualParameterCatalog`: 15 descriptors (ID, display name, group, unit, kind with range and step, modulation policy) in four groups: Circular Spectrum, Linear Spectrum, Glow (`effect.bloom`), Particle Orbit. Units: none, normalized, fraction of output, seconds, per second, degrees, count. |
| Inspecting one | UIX-003 `ParameterInspectorView`, a sheet over Settings addressed by parameter ID (`InspectedParameter`); entry points are the "Inspect" context menu and VoiceOver action on 7 Settings controls, and `-uitestInspectParameter <id>` in DEBUG. Parameters without a Settings control open read-only. |
| Layers | CMP-015 Settings › Layers lists the current scene's layers; a layer's own values are the catalog parameters of its group. The visual chosen in Settings decides which layers (and so which parameter groups) are on screen. |
| Search | **None for parameters.** Presets have a case- and diacritic-insensitive substring search (PresetLibrary `fold`); scene folders and the scene switcher fold the same way. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which parameters are searched? → A: Every parameter in the MOD-001 visual catalog (the registry the UIX-003 inspector reads), in every group, whatever visual or layer is on screen. The result is a list of parameter IDs; the current visual never filters or reorders it.
- Q: What does a query match? → A: Each word of the query must match the parameter's display name, its group name, or its unit (the unit's name and its common symbols, e.g. "%", "s", "ms", "Hz", "°"). Matching ignores case and accents ("rádius" finds "Radius").
- Q: In what order are results listed? → A: Name starts with the word first, then name contains the word, then group, then unit; ties keep the catalog's order.
- Q: Where is the search? → A: A "Search Parameters" row in Settings next to Modulation, opening a searchable list. Choosing a result opens that parameter's UIX-003 inspector over Settings.
- Q: Does choosing a parameter of another layer change the visual? → A: No. The inspector is addressed by ID and works for every catalog parameter, so nothing on screen changes; a row says when its parameter belongs to the visual on screen.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does the group's internal name count as the group (e.g. "bloom" for Glow, whose ID is `effect.bloom`)? → A: Yes. The group match covers the group's display name and its stable ID, so a name someone saw in a scene file or the modulation matrix also finds it; it ranks as a group match.
- Q: Do a parameter's choices ("Vertical", "Horizontal") or values match? → A: No. Only name, group and unit are searched (the roadmap row); choices would make "vertical" find a parameter whose name does not say so, and values change while the visual plays.
- Q: How are matches inside a word treated? → A: A word matches the name or group when the folded text contains it anywhere; it is a name-prefix match when the name starts with it. Units match only when a unit term starts with the word, so "s" finds seconds but not every name containing "s".
- Q: Is the query kept between visits? → A: No. The search starts empty each time it opens; nothing is saved, so no setting, backup or erase category changes.
- Q: What does an empty query show? → A: Every parameter, grouped under its group's name in catalog order, so the screen doubles as an index; a non-empty query shows one ranked list.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find a parameter by what I remember (Priority: P1) — MVP

I remember a setting's name, its section or its unit ("radius", "glow", "seconds") but not where it is. In
Settings I open Search Parameters, type the word, and see every parameter that matches, from every visual,
with its group and current value. Choosing one opens its inspector.

**Why this priority**: it is the whole feature.

**Independent Test**: with the circular spectrum on screen, search "orientation" (a Linear Spectrum
parameter), choose the result, and the inspector for `visual.linearSpectrum.orientation` opens.

**Acceptance Scenarios**:

1. **Given** any visual on screen, **When** I search "radius", **Then** the results are the three radius
   parameters (circular inner radius, glow radius, particle orbit radius) and nothing else, in the same order
   whatever the visual.
2. **Given** results, **When** I choose one, **Then** its inspector opens over Settings and the visual is
   unchanged.
3. **Given** I search "%" or "Hz" or "ms", **Then** the parameters with that unit are listed.

### User Story 2 - Empty and no-result states (Priority: P2)

**Acceptance Scenarios**:

1. **Given** an empty query, **Then** every parameter is listed by group, so the list also works as an index.
2. **Given** a query nothing matches, **Then** the list says "No parameters match" and suggests searching a
   name, a group or a unit.

### Edge Cases

- Leading, trailing or repeated spaces are ignored; a query of only spaces is empty.
- A word matching several fields counts at its best (lowest) rank.
- A parameter whose name has a parenthetical ("Gap (of the bar pitch)") matches words inside it.
- VoiceOver reads each row as name, group and current value, and the row's action opens the inspector.

## Requirements *(mandatory)*

### Functional Requirements

- **UIX-009-R1**: The search MUST consider every parameter of the MOD-001 visual catalog and MUST NOT depend on the visual, layer or group currently selected.
- **UIX-009-R2**: A query is split into words; a parameter matches when every word matches its display name (substring), group display name or group ID (substring), or a unit term (prefix), ignoring case and diacritics. Enum choices and values are not searched.
- **UIX-009-R3**: Units MUST be searchable by name and symbol: percent ("%", "percent"), seconds ("s", "sec", "seconds", "ms"), per second ("/s", "per second", "Hz", "rate"), degrees ("°", "deg", "degrees"), count ("count", "number").
- **UIX-009-R4**: Results MUST be ranked name-prefix > name-substring > group > unit, ties in catalog order, and returned as parameter IDs.
- **UIX-009-R5**: Settings MUST offer "Search Parameters", a searchable list whose rows show name, group and current value (or "Read only" without a Settings control) and mark parameters of the visual on screen.
- **UIX-009-R6**: Choosing a row MUST open the UIX-003 inspector for that ID without changing the visual.
- **UIX-009-R7**: An empty query lists every parameter; a query with no match shows a no-results message.
- **UIX-009-R8**: Rows MUST be VoiceOver-friendly (one element: label = name, value = group and current value; button trait) and keep stable accessibility identifiers (`parameterSearchResult.<id>`).

### Key Entities

- **Parameter search hit**: a parameter ID with its rank (which field matched).
- **Search row**: ID, name, group, value text and whether it belongs to the visual on screen.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UIX-009-S1**: For every tested query, the returned IDs are identical with no current layer, with the circular spectrum and with the linear spectrum selected.
- **UIX-009-S2**: Unit queries "%", "ms" and "Hz" each return exactly the catalog parameters of that unit.
- **UIX-009-S3**: A user reaches a parameter of another visual's layer in at most three steps from Settings (open search, type, choose).
- **UIX-009-S4**: Searching the whole catalog takes well under one frame (no visible delay while typing).

## Assumptions

- The catalog has 15 parameters today; new descriptors become searchable with no extra work.
- Recent searches are not stored (no new saved settings, nothing to back up or erase).
- The colour-grade and effect-chain parameters are not in the MOD-001 visual catalog and are out of scope until they are.
