# Feature Specification: SCN-012 Scene Validation

**Feature Branch**: `feature/scn-012` (spec directory `079-scn-012-scene-validation`)

**Created**: 2026-11-13

**Status**: Implemented 2026-11-13 (SCN-012-T01-T12 verified on the Mac: host, Linux shape, own iOS
27.2 simulator; no device claim). SceneFormat 67 tests (host 3.2 s, Linux shape 2.7 s; SceneRepairTests
8, fuzz 500 cases 0.76-0.88 s), projectM-iOSTests 352 (19.0 s; SceneRepairCoordinatorTests 6),
SceneRepairUITests 1 (9.9-12.1 s), ShowCueUITests 2, SessionRecoveryUITests 3. Compliance and docs
checks OK. PosterBoard reports 32 before and after. Not exercised by a test: the VoiceOver heading
trait of group titles (XCUITest exposes no traits) and the Reopen sheet in the UI (unit-tested
decision and repaired held scene).

**Input**: User description: "Implement SCN-012 (Scene validation) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Report missing assets, invalid
mappings and unsupported versions before opening." Acceptance, verbatim: "Malformed fixture shows
repair report instead of crash." P0, size M, depends on SCN-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SCN-012-R1…`, success criteria `SCN-012-S1…`, tasks `SCN-012-T01…`. Other features
are cited by their own IDs: SCN-001 (scene document and validation, ADR-0028), MOD-013 (per-edge
modulation restore), SCN-002 (scene autosave), SCN-003 (duplicate and rename), SHOW-001 (cue list),
PERF-010 (session recovery), FILE-001/FILE-002 (scene archive import and checksums), SCN-014 (scene
dependency pack screen), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-13, commit `7ec3fe5`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit confirms a partial gap:
detection exists, the user-facing report before opening does not.

| Needed | Today |
|---|---|
| Detect problems | SCN-001 `SceneDocument.validate` returns 33 stable issue codes (errors refuse the scene, warnings open it) with a path and a message; `decode` refuses empty, oversize, non-JSON, too-deep, duplicate-key, not-a-scene, newer-version, invalid-version, too-many and malformed input with a typed error. |
| Mapping problems | MOD-013 restores bindings and connections per edge (`modulationReport`: restored, rewritten, dropped, orphaned, rejected); every per-edge problem is a warning. |
| Missing media | `missingAsset` warning when the photo or video store no longer holds the referenced item. |
| Show cues (SHOW-001) | A step reads and validates the cue's scene. An unreadable scene or one with errors leaves the output unchanged with a 4 s notice "Cue N: the scene could not be shown."; a missing photo or video applies with a note. No list of what is wrong, no way to open anyway or repair. |
| Scene archive import (FILE-001/002) | The service refuses a bad archive with a typed error and refuses unresolved references; its result carries the scene's warnings. No import screen exists yet (SCN-014). |
| Reopen after a crash (PERF-010) | The held scene has already passed validation (errors make SCN-002 fall back to its backup or the fresh scene); warnings are not shown. |
| Autosave restore at launch (SCN-002) | Silent: errors fall back to the backup, then the fresh scene; each fallback is logged as a diagnostics event. |
| Repair | Nothing: no transformation turns a broken scene into an openable one. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Which problems make the report appear before opening, and which open silently as today? → A: The report appears for errors and for three user-relevant warnings: missing media (`missingAsset`), invalid mappings (every MOD-013 per-edge problem: `invalidBinding`, `duplicateBindingTarget`, `invalidExpression`, `orphanedBinding`, `orphanedConnection`, `rejectedConnection`, `retiredReference`) and unknown layer kinds (a layer is not shown). Notes open silently: values adjusted on read (`valueClamped`, `droppedField`, `parameterClamped`, `unsupportedBlendMode`, `migratedReference`) and content kept but unused (`unusedAsset`, `unknownAssetType`, `orphanedParameter`, `rejectedParameter`). Rejected: a report for every warning (a show would stop for harmless clamps); errors only (the row names missing assets and invalid mappings, which are warnings today).
- Q: Does "Open with repairs" write the repaired scene back to the stored file? → A: No. Repairs apply to the live output only and the stored file stays byte-identical (`SCN-012-R9`); stepping through a show is not an edit (SHOW-001-R6) and a later save of the look (Add Current Scene, autosave) records whatever is shown. Rejected: saving on open (silently rewrites a show's scene, loses the original for a later app version that could read it); a separate "Save repairs" button (a scene editor is a later row).
- Q: When a cue's scene needs the report, does the show's position still move? → A: Yes: the position moves as SHOW-001-R9 already rules for a broken scene, and the output stays unchanged until the performer opens the scene; Cancel leaves the output on the previous look. Rejected: holding the position until the report is answered (the show list and the keyboard steps would disagree with the visible cue).
- Q: Which errors have a repair, and which make the scene "Cannot open"? → A: Repairable (each repair touches only the named items): duplicate or out-of-range instance IDs → renumber the later layers with the next free IDs; a layer whose asset is undefined, of the wrong type, damaged (text or graph), has an invalid key or store ID, or uses an unknown material → remove that layer (and its asset); more layers of a kind than allowed → remove the extra layers; an invalid value name → drop that value; a malformed parameter ID → drop that value; an invalid name → rename to "Untitled scene"; invalid generator declarations → remove the modulation generators and the connections that use them. Not repairable: an invalid scene ID (the scene's identity; shows and archives refer to it) and every decode refusal (newer version, damaged bytes, limits). Rejected: guessing a new scene ID (would break the cue's reference); trying to salvage truncated JSON (could open a wrong look).
- Q: What does "Open with repairs" do with unknown content (layer kinds, fields, parameter values this version does not know)? → A: Keeps it: the default action "Keep unknown content" changes nothing, so a newer minor format's content survives (ADR-0028 forward compatibility); missing media and invalid mappings are removed. Rejected: removing unknown layers by default (destroys content a newer version made).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See what is wrong before a broken cue opens (Priority: P1)

A performer steps to the next cue. Its scene names a photo that was removed from the device and an
audio mapping whose target this version does not know. Instead of a silent wrong look or a short
notice, a report appears: under "Missing media" the photo, with "its layer draws nothing"; under
"Invalid mappings" the mapping, with "it is kept but has no effect". The performer taps "Open with
repairs": the cue opens without the photo layer and without the dead mapping, and the visual runs.

**Why this priority**: It is the row's behavior ("report … before opening") and acceptance ("repair
report instead of crash") on the path a performer meets most: a show cue.

**Independent Test**: Seed a show whose second cue's scene references a missing photo and a dangling
binding target; step to it; the report shows both sections; "Open with repairs" applies the cue.

**Acceptance Scenarios**:

1. **Given** a cue whose scene has a missing photo and a dangling mapping, **When** the performer
   steps to it, **Then** the output is unchanged and a report lists a "Missing media" entry and an
   "Invalid mappings" entry, each naming the item and what happens if opened anyway.
2. **Given** that report, **When** the performer chooses "Open with repairs", **Then** the repaired
   scene is applied (the photo layer and the dead mapping removed) and the stored scene file is
   unchanged.
3. **Given** that report, **When** the performer chooses "Open as is", **Then** the scene is applied
   exactly as stored (as SHOW-001 applied it before this feature).
4. **Given** that report, **When** the performer chooses "Cancel", **Then** nothing is applied and the
   show's position stays on the cue.

---

### User Story 2 - A scene that cannot open says why (Priority: P1)

A cue's scene was saved by a newer version of the app, or its file is damaged (truncated, oversize,
duplicate layer IDs that cannot be fixed safely). The report says "Cannot open", explains why
("Made by a newer version: update the app" or "The file is damaged") and offers only Close.

**Why this priority**: The roadmap names "unsupported versions"; a refusal must be explained, never a
crash and never a wrong look.

**Independent Test**: Step to a cue whose scene file declares a newer format version; the report
shows "Cannot open" with the update hint and no open button.

**Acceptance Scenarios**:

1. **Given** a cue whose scene declares a newer format version, **When** the performer steps to it,
   **Then** the report shows an "Unsupported version" entry, "Cannot open", and no open action.
2. **Given** a truncated or oversize scene file, **When** it is opened, **Then** the report shows a
   "Damaged file" entry and no open action.
3. **Given** any refusal, **When** the report is closed, **Then** the output is unchanged.

---

### User Story 3 - Errors that can be repaired open after repair (Priority: P2)

A scene has errors that would refuse it today but have a safe repair: two layers share an instance
ID, a layer references an asset the scene does not define, a layer uses a material this version does
not know, a value has an invalid name, a modulation generator declaration is invalid. The report
lists each under its group with the repair; "Open as is" is not offered; "Open with repairs" opens the
repaired scene.

**Why this priority**: It turns today's dead ends into openable scenes without touching the stored
file.

**Independent Test**: Pure, on Linux: each fixture's report has the exact entries and actions, and
the repaired document validates without errors.

**Acceptance Scenarios**:

1. **Given** a scene with duplicate instance IDs, **When** it is reported, **Then** the entry offers
   "Renumber duplicate layers" and the repaired scene has unique IDs and no errors.
2. **Given** a scene whose only problems are repairable errors, **When** "Open with repairs" is
   chosen, **Then** the repaired scene validates with no errors and opens.

---

### User Story 4 - Other ways a scene opens follow the same rule (Priority: P2)

Reopen after a crash (PERF-010) shows the report before applying when the held scene has problems the
user should see. An imported scene archive's result carries its report for the import screen
(SCN-014). The launch restore stays silent, as today.

**Independent Test**: Unit tests on the decision rule per origin; the reopen path with a held scene
naming a missing photo presents the report.

**Acceptance Scenarios**:

1. **Given** the recovery offer whose held scene names a missing photo, **When** the user chooses
   Reopen, **Then** the report is shown before anything is applied; Cancel keeps the offer.
2. **Given** a launch with an autosaved scene that has only warnings, **When** the app starts,
   **Then** no report is shown and the scene opens as today.

### Edge Cases

- A report with only information-level entries (values adjusted on read, an unused asset, a value for
  a parameter this version does not know) opens without a report, as today.
- Repairs are idempotent: repairing a repaired scene changes nothing.
- A repair never removes content that has no problem; unknown layer kinds, unknown fields and
  unknown parameter values are kept (forward compatibility, ADR-0028).
- A scene whose errors cannot all be repaired (an invalid scene ID) shows "Cannot open"; an invalid
  name is repaired to "Untitled scene".
- Report generation never crashes, whatever the bytes: a seeded fuzz of mutated scenes proves it.
- A step from the show editor (Settings → Show → Go to Cue): the report appears over Settings; the
  show's position has already moved.
- Blackout: the report does not lift a blackout; an opened cue stays black until Restore.
- The cue's scene file is absent (not damaged): SHOW-001's notice stays, there is nothing to report.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-012-R1**: The system MUST turn every decode refusal, validation issue and per-edge
  modulation problem of a scene into a repair report: entries grouped as Missing media, Invalid
  mappings, Unsupported version, Unknown content kept, Values adjusted, Damaged file.
- **SCN-012-R2**: Each entry MUST state its severity (cannot open, needs repair, opens with a
  problem, note), the affected item in plain words, what happens if the scene is opened anyway, and
  the repair actions available for it.
- **SCN-012-R3**: Repair actions MUST be pure, deterministic transformations that return a new
  document; the same input and actions always give the same output.
- **SCN-012-R4**: Repairs MUST be idempotent and MUST produce a document with no errors, except
  problems the report marks as not repairable.
- **SCN-012-R5**: Repairs MUST remove or change only the items their entries name, and MUST keep
  unknown content (layer kinds, fields, parameter values) by default.
- **SCN-012-R6**: A refusal (newer version, damaged bytes, limits exceeded) MUST produce a report
  that says "Cannot open" with its reason; a newer version MUST tell the user to update the app.
- **SCN-012-R7**: Report generation MUST never crash or trap for any input bytes or document.
- **SCN-012-R8**: Stepping to a show cue whose scene has errors or user-relevant warnings (missing
  media, invalid mappings, unknown layers) MUST show the report before applying anything, with Open
  with repairs (when repairs exist), Open as is (only when there are no errors) and Cancel. The
  show's position moves as SHOW-001-R9 rules; the output stays unchanged until the user opens it.
  Scenes with only notes (values adjusted, content kept but unused) open without a report.
- **SCN-012-R9**: Opening with repairs MUST apply the repaired scene to the live output only; the
  stored scene file MUST stay unchanged.
- **SCN-012-R10**: Reopen after a crash (PERF-010) MUST show the report before applying when the held
  scene has user-relevant warnings; Cancel keeps the recovery offer.
- **SCN-012-R11**: The scene archive import result (FILE-001) MUST carry the scene's repair report;
  archive refusals stay typed errors.
- **SCN-012-R12**: The launch autosave restore (SCN-002), which the user did not initiate, MUST stay
  silent: it logs and falls back as today.
- **SCN-012-R13**: The report MUST be readable with VoiceOver (group headings, each entry one
  element) and Dynamic Type (FR-070).
- **SCN-012-R15**: The default repair set ("Open with repairs") MUST keep unknown layer kinds,
  fields and parameter values, and remove only missing media, invalid mappings and repairable errors.
- **SCN-012-R14**: Report generation and repairs MUST read no files, use no network and execute
  nothing from the document (Constitution, ADR-0028).

### Key Entities

- **Repair report**: the grouped entries of one scene, whether it can open as is, open after repairs,
  or cannot open, and the actions "Open with repairs" applies.
- **Report entry**: group, severity, affected item, problem, outcome if opened anyway, actions, and
  the issue code and document path it came from.
- **Repair action**: a named, deterministic transformation of a document (for example "Open without
  the missing photo", "Drop invalid mappings", "Renumber duplicate layers").

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-012-S1**: Every malformed fixture in the fixture table (truncated JSON, newer version,
  duplicate instance IDs, missing photo, dangling binding target, modulation cycle, unknown layer
  kind, oversize) produces its expected report or refusal; zero crashes.
- **SCN-012-S2**: 100% of repaired fixture documents validate with no errors (except entries marked
  not repairable) and repairing twice equals repairing once.
- **SCN-012-S3**: A seeded fuzz of at least 500 mutated scenes produces a report for each with zero
  crashes, and every repaired document encodes and decodes again, in under 1 second.
- **SCN-012-S4**: On the simulator, stepping to the broken cue shows the report with both sections
  and "Open with repairs" applies the cue; stepping to the newer-version cue shows "Cannot open"; the
  UI test finishes in under 30 seconds.
- **SCN-012-S5**: Cues without problems open exactly as before (SHOW-001 UI tests unchanged and
  passing).

## Assumptions

- The app has no scene browser yet; show cues are the main user path that opens a stored scene.
- The import screen for scene archives is SCN-014; this feature supplies the report it will show.
- Reports and repairs are computed in memory from the scene; scenes are at most 1 MiB.
- Simulator results are not device evidence; no device run is needed for this row.
