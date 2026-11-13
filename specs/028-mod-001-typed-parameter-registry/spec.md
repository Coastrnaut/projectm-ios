# Feature Specification: MOD-001 Typed Parameter Registry

**Feature Branch**: `feature/mod-001` (spec directory `028-mod-001-typed-parameter-registry`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement MOD-001 (Typed parameter registry) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Give every editable visual
parameter a stable ID, range, units and default." Acceptance, verbatim: "Duplicate IDs fail
validation and defaults remain in range." Dependencies: ANL-016 (integrated). It is the base for
MOD-*, MIDI, OSC, SCN and parameter UI features. Honor the repository constitution and owner rule 7."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `MOD-001-R1…`, success criteria `MOD-001-S1…`, tasks `MOD-001-T01…`. Requirements
of other features are cited by their own IDs: FR-065 (what the app may store), FR-072 (Reduce
flashing); VIS-001-R2, R11 (bar counts, the visual choice); VIS-002-R3 to R6, R11 (linear spectrum
options); FX-001-R3, R4, R11 (bloom controls and ranges).

## Baseline: what exists today (audit of 2026-11-13, commit `c2b2f75`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Parameter identity | Each visual option lives in its own configuration type (`CircularSpectrumConfiguration`, `LinearSpectrumConfiguration`, `BloomParameters`) with its own range and default constants, and the app stores a subset under `settings.*` keys (`AppSettings`). | No stable, app-wide identifier per parameter; nothing a mapping, MIDI/OSC route or scene could reference. |
| Ranges and units | Ranges are Swift constants scattered across types; units appear only in comments ("fraction of the output's shorter side"). | No machine-readable range, unit, step or default per parameter. |
| Validation | Each type clamps its own values. | Nothing detects two parameters claiming the same identity or a default outside its range. |
| Current value | Values live in the configuration structs and `AppSettings`. | No uniform typed get/set with clamping and a change notification. |
| Analysis (ANL-016) | The analysis event bus publishes timestamped feature frames. | Analysis outputs are future modulation *sources* (MOD-002); they are not parameters and are not registered here. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Every editable visual parameter has one stable identity (Priority: P1)

Future features (modulation, MIDI learn, OSC routes, scene save and recall, parameter screens)
need to refer to "the circular spectrum's inner radius" or "the glow intensity" by a name that never
changes, and to know its range, units and default without reading code. A developer (or a later
feature) asks the app's parameter catalog for all parameters, or for one group (for example the
glow), and gets each parameter's stable ID, display name, group, unit, value kind, range, step and
default, always in the same order.

**Why this priority**: It is the row's observable behavior ("Give every editable visual parameter
a stable ID, range, units and default").

**Independent Test**: Build the app's catalog in a unit test: every native-visual and glow option
that has a documented range appears exactly once with an ID matching the documented syntax, its
range and default equal the existing configuration types' values, and enumerating twice gives the
same order.

**Acceptance Scenarios**:

1. **Given** the app's catalog, **When** it is enumerated, **Then** it lists the circular spectrum, linear spectrum and glow parameters with ID, display name, group, unit, kind, range and default, in registration order, identical on every enumeration.
2. **Given** a group ID such as the glow's, **When** the catalog is asked for that group, **Then** exactly that group's parameters are returned, in registration order.
3. **Given** the existing configuration types, **When** their ranges and defaults are compared with the catalog, **Then** every value matches (the catalog cannot drift from the types).

---

### User Story 2 - A malformed catalog fails validation with a readable reason (Priority: P1)

Whoever adds a parameter (a developer, a later feature) gets an immediate, readable failure if the
new parameter reuses an existing ID, has a malformed ID, or has a default outside its range, so a
broken catalog can never reach users or scenes.

**Why this priority**: It is the roadmap acceptance ("Duplicate IDs fail validation and defaults
remain in range").

**Independent Test**: Build catalogs that each contain one defect and check that validation fails
with a message naming the defect (for a duplicate, naming both registrations).

**Acceptance Scenarios**:

1. **Given** two parameters with the same ID, **When** the catalog is validated, **Then** validation fails and the message names the ID and both registrations (their display names and where they were registered).
2. **Given** a parameter whose default lies outside its range (or is not finite, or an enum default that is not one of its cases), **When** validated, **Then** validation fails naming the parameter and the reason.
3. **Given** an empty or ill-formed ID, a range whose minimum is not below its maximum, a non-finite bound or step, an enum with no cases or duplicate case IDs, or a modulation policy that contradicts the value kind, **When** validated, **Then** validation fails naming the parameter and the reason.
4. **Given** the app's real catalog, **When** validated, **Then** it passes, and every default is finite and inside its range.

---

### User Story 3 - Current values are typed, clamped and observable (Priority: P2)

A later feature (a parameter screen, a MIDI route, a scene recall) sets a parameter's current
manual value by ID and reads it back in its own type; out-of-range values are clamped, wrong types
and unknown IDs are rejected, and observers learn about each change.

**Why this priority**: The roadmap's parameter boundary includes the "current manual value"; every
consumer needs the same clamping and change semantics.

**Independent Test**: Create a value store over a test catalog; set values below, inside and above
range, of the wrong type, NaN, an unknown enum case and an unknown ID; check stored values, errors
and the notifications received.

**Acceptance Scenarios**:

1. **Given** a continuous parameter with range 0…1, **When** 1.5 is set, **Then** the stored value is 1 and one change notification reports old and new values.
2. **Given** a parameter, **When** a value of another kind, NaN, or an unknown enum case is set, **Then** the set is rejected with a readable error and the value and notifications are unchanged.
3. **Given** values of every kind (continuous, integer, boolean, enum, color), **When** set and read back through their typed accessors, and saved to and restored from a snapshot, **Then** the values round-trip exactly; a snapshot entry for an unknown ID is reported as orphaned, not applied.
4. **Given** a changed value, **When** it is reset, **Then** it returns to the parameter's default.

### Edge Cases

- Setting a value equal to the current one: stored, no change notification.
- Integer parameters with a step: the value snaps to the nearest step from the minimum, then clamps.
- Continuous step is a presentation hint only; the store keeps the clamped value unsnapped (modulation needs continuous values).
- ±infinity and NaN for continuous parameters and color components: rejected (no "clamp" of a non-number).
- A parameter whose valid range depends on another parameter (the spectra's length scale): not registered in this row; recorded as a follow-up.
- Parameters without a documented range (rotation and start angles): not registered in this row.
- Safety settings (Reduce flashing) and non-visual settings (performance overlay, preset scope): never registered as visual parameters.
- Color components outside 0…1: clamped per component.

## Requirements *(mandatory)*

### Functional Requirements

- **MOD-001-R1**: Every registered parameter MUST have a stable ID: two or more dot-separated segments, each starting with a lowercase ASCII letter followed by ASCII letters and digits, at most 128 characters in all (for example `visual.circularSpectrum.innerRadius`). The first segment is the domain (`visual`, `effect`, …). Once an ID has shipped it MUST NOT be renamed, reused for another meaning or change value kind; a changed meaning gets a new ID and the old one is retired (kept in a retired list, never registered again).
- **MOD-001-R2**: Every parameter MUST carry a descriptor: ID, display name, group (group ID with the same syntax plus display name), unit, value kind with its constraints and default, and a modulation policy. Value kinds: continuous (finite min < max, optional positive step, curve hint linear/logarithmic/exponential), integer (min < max, step ≥ 1), boolean, enum (one or more cases, each with a stable case ID and display name), color (linear RGBA, components 0…1).
- **MOD-001-R3**: Units MUST come from a fixed list with stable stored names: none, normalized (0…1), fraction of the output, seconds, per second, degrees, count.
- **MOD-001-R4**: The modulation policy MUST state whether the parameter may be modulated and which mix modes are allowed (replace, add, multiply; MOD-011), and whether external control (MIDI, OSC) may set its manual value. Add and multiply are allowed only for continuous and integer kinds; a parameter that is not modulatable lists no mix modes.
- **MOD-001-R5**: A catalog MUST be validated as a whole when it is built, collecting every issue, and MUST be rejected if any exists: duplicate parameter IDs (naming both registrations), ill-formed or empty IDs, empty display names, ill-formed group IDs or one group ID with two display names, non-finite bounds/steps/defaults, min ≥ max, non-positive steps, defaults out of range, enum with no cases, duplicate or ill-formed case IDs or a default that is not a case, color defaults outside 0…1, a policy that contradicts the kind, and a retired ID being registered.
- **MOD-001-R6**: Catalog contents and order MUST be static per build and deterministic: enumeration (all, or by group) returns registration order, and lookup by ID returns the one descriptor.
- **MOD-001-R7**: A value store over a validated catalog MUST hold one current manual value per parameter, starting at the default; typed get and set by ID; set clamps continuous and integer values to range (integers snap to step), clamps color components to 0…1, and rejects unknown IDs, wrong kinds, non-finite numbers and unknown enum cases without changing state; reset to default per parameter and for all.
- **MOD-001-R8**: The store MUST notify observers synchronously after each effective change (ID, old value, new value), never while holding its lock, and expose a monotonically increasing change counter so a render loop can poll without callbacks. It MUST be safe to use from any thread.
- **MOD-001-R9**: The store MUST produce and restore a versioned snapshot of values keyed by parameter ID; restore applies valid entries with the same clamping as set, and reports unknown IDs (orphaned), wrong kinds and invalid values without applying them. Rollback is restoring an earlier snapshot. Nothing is written to disk in this row (persistence belongs to SCN-001/SCN-002).
- **MOD-001-R10**: The app's catalog MUST register the native visuals' and the glow's editable parameters whose ranges are documented constants: circular spectrum bar count, inner radius, gap; linear spectrum bar count, orientation, spacing, cap thickness, peak hold, peak fall rate; glow enabled, intensity, radius, threshold, knee. Ranges and defaults MUST be read from the existing configuration types (single source of truth), not repeated as literals.
- **MOD-001-R11**: Reduce flashing (FR-072) is a safety setting, not a visual parameter: it MUST NOT be registered, so no mapping, MIDI/OSC route or scene can modulate it. Non-visual settings (performance overlay, preset scope) and the visual choice are not registered either.
- **MOD-001-R12**: The parameter model MUST be a separate module with no dependency on UI, rendering, capture, projectM or the app, building and testing on every CI host including Linux; it MUST NOT add network access, private APIs or third-party dependencies, and MUST NOT store any new data (FR-065 unchanged).
- **MOD-001-R13**: This row MUST NOT change the app's visible behavior: existing settings keep their keys, choices and defaults.

### Key Entities

- **Parameter ID**: the stable dotted name of one parameter.
- **Parameter descriptor**: ID, display name, group, unit, value kind and constraints, default, modulation policy, registration site.
- **Parameter catalog (registry)**: the validated, ordered set of descriptors; lookup and enumeration.
- **Parameter value**: a typed value (continuous, integer, boolean, enum case ID, color).
- **Value store**: current manual values, change notifications, change counter.
- **Value snapshot**: version plus values keyed by parameter ID.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MOD-001-S1**: A catalog with a duplicate ID fails validation 100 % of the time, with a message naming the ID and both registrations.
- **MOD-001-S2**: Each malformed-descriptor kind listed in MOD-001-R5 has at least one representative fixture, and each fails validation with a message naming the parameter and the defect.
- **MOD-001-S3**: 100 % of the app's registered parameters have a finite default inside their range, and their ranges and defaults equal the existing configuration types' values (checked by a test, so drift fails CI).
- **MOD-001-S4**: Enumerating the app catalog twice, and building it twice, yields identical ID sequences.
- **MOD-001-S5**: Out-of-range manual values are clamped, invalid ones rejected without side effects, and all five value kinds round-trip through typed access and snapshots, in short unit tests (each about 1-2 s or less on the host; the package suite under 1 minute, owner rule 7).
- **MOD-001-S6**: The app's existing settings behavior is unchanged: its existing unit and Settings UI tests pass unchanged.

## Assumptions

- The registry lives in the roadmap's proposed `Packages/ParameterGraph`; graph edges, mappings, LFOs and evaluation are later MOD rows.
- Scenes (SCN-001) will persist values by these IDs; MOD-013 adds edge serialization with migration rules.
- The app's settings keep their own storage in this row; routing them through the store is a follow-up (recorded in Clarifications).
- No user-visible UI in this row; parameter screens are UIX-003/004/009.
