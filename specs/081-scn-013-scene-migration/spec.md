# Feature Specification: SCN-013 Scene Migration

**Feature Branch**: `feature/scn-013` (spec directory `081-scn-013-scene-migration`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SCN-013 (Scene migration) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Migrate older scene schema
versions with backup and audit log." Acceptance, verbatim: "Every golden legacy fixture loads into
current schema without data loss." P0, size L, depends on SCN-001 (integrated). QA-004 (scene
migration matrix) depends on this row."

Identifiers carry the roadmap ID: requirements `SCN-013-R1…`, success criteria `SCN-013-S1…`, tasks
`SCN-013-T01…`. Other features are cited by their own IDs: SCN-001 (scene document, ADR-0028),
SCN-002 (scene autosave), SCN-012 (repair report), SHOW-001 (show list scenes, ADR-0033), FILE-001/002
(scene archives), PERF-010 (session recovery), QA-002 (golden render scenes), QA-004 (migration
matrix), FILE-009/010 (storage screen).

## Baseline: what exists today (audit of 2026-11-13, commit `01c0388`)

The row's gap status is "Gap candidate; re-audit at implementation". The audit finds a real gap in
the mechanism and **no older schema version to migrate from**:

| Question | Finding |
|---|---|
| Which scene format versions were ever written? | Only version 1. `SceneDocument.currentVersion = 1` since the package was created (`7b620b7`, SCN-001, 2026-11-13); `git log --all -- Packages/SceneFormat` has 12 commits, none changes the version. No prototype scene format exists in history. |
| Did the written shape of version 1 change? | No. Between `7b620b7` and `01c0388` the encoder changed only Swift type names (`SceneBinding.sourceID`, `SceneConnection`, `SceneNodeRef`); the bytes it writes have the same fields and spellings. The decoder became more tolerant (MOD-013 keeps unknown audio-feature IDs instead of refusing them), which reads more files, never a different shape. |
| Was any file written in a shape the current decoder reads only through tolerance? | No. Every writer (SCN-002 autosave capture, SHOW-001 `saveScene`, FILE-001 archive writer, SCN-003 duplicate and rename, QA-002 golden scenes) calls the one canonical encoder. |
| Where are scene documents stored? | SCN-002 `Application Support/Scenes/current.scene` and `.bak` (autosave; PERF-010 recovers from it, holding the scene in memory only); SHOW-001 `Application Support/Show/Scenes/<id>.scene`; FILE-001/002 `scene.json` inside a `.projectmscene` archive (imported, never rewritten in place); QA-002 `Packages/RenderGoldens/Scenes/*.scene.json` (7 committed files). User presets are `.milk` presets, not scene documents. |
| Released builds | The App Store builds (1.0, 1.1) contain no scene documents; scene files exist only on development devices and simulators of this run. |
| What happens to an older or newer version today? | `decode` refuses version < 1 (`invalidVersion`) and version > 1 (`newerVersion`; SCN-002 sets such a file aside as `<name>.newer`; SCN-012 shows "Cannot open"). There is no migration step, no backup of an original and no audit log. |

So the deliverable is the migration mechanism (chain, backup, audit log, report note), wired into
every place a scene is read, plus golden version-1 fixtures taken from the real writers. No fake
earlier version is invented as history: tests that exercise a step use synthetic chains that are
labelled as test-only and never registered in the app.

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative, local-first option.

- Q: Version 1 is the only version ever written. Should a "version 0" be created to have something to migrate? → A: No. The production chain is empty and version 1 is both the oldest and the current version; a version-0 file stays refused as "invalid version" exactly as today. The mechanism is proven with synthetic test-only steps (v0→v1 for the full decode path and app backup tests, v1→v2→v3 for the raw chain), and the golden fixtures are the real version-1 shapes. Rejected: a made-up legacy shape registered in the app (would accept files no app ever wrote and claim history that does not exist).
- Q: Where does migration run, and when is a migrated scene written back? → A: Migration runs in memory every time a scene is decoded (the one decode entry point), so autosave restore, show cues, Reopen and archive import all see the current schema. Opening never writes. A stored file is only replaced by the app's normal saves (the next autosave, a show scene edit), and the original bytes are backed up immediately before that first replacement. Rejected: rewriting the file on open (changes the user's file with no edit and would race a later app version that can read the original); a separate "upgrade all scenes" pass (writes many files at once, nothing asks for it).
- Q: What is the backup's name, and is it ever replaced or removed? → A: `<stored file name>.v<N>.backup` next to the original (for example `current.scene.v1.backup`), created exclusively once per source version and never overwritten. It stays until the scene it belongs to is removed (a show scene no cue refers to is removed with its backups); the autosave backups stay. Rejected: a backups folder (separates the original from its scene); overwriting on each migration (would replace the true original with an already-migrated copy).
- Q: What if the backup cannot be written? → A: The save that would replace the original is refused (an autosave write failure event with step "keep original"; a show save failure); the migrated scene stays live in memory and the original stays on disk. A failure to write a small backup next to the file almost always means the save itself would fail too (disk full, permissions). Rejected: saving anyway (loses the only original).
- Q: What goes to the diagnostics events, given scene paths can carry scene-local names? → A: Only versions, step identifiers and counts: "migrated scene from version N to M (S steps, C changes)" and "kept original as <fixed file name>". The full audit log (step, change kind, JSON path) stays in memory for tests, the SCN-012 report and QA-004, and is never logged. Rejected: logging paths (asset keys and value names can be user text; constitution privacy rules).
- Q: Does a migrated scene make the SCN-012 report appear before opening? → A: No. It adds one note entry "Updated from an older format" (item "Scene file", severity note), which shows when the report is shown for another reason and never stops a show. Rejected: a blocking prompt per migrated scene (stops a show for a harmless upgrade).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - An older scene opens in the current version (Priority: P1)

A performer updates the app. Their autosaved scene and their show's scenes were written by an
earlier format version. The scenes open exactly as they were, with every layer, value, binding,
modulation connection and media reference intact.

**Why this priority**: Losing a show's scenes after an update is the failure this row exists to prevent.

**Independent Test**: Decode each golden legacy fixture with the current app and compare the result
with the fixture's expected current-schema document.

**Acceptance Scenarios**:

1. **Given** a golden legacy fixture of any listed version, **When** it is opened, **Then** the scene
   decodes into the current version and its canonical form equals the fixture's expected document
   byte for byte.
2. **Given** any golden legacy fixture, **When** it is opened, **Then** every value in the input is
   present in the output at its (possibly renamed) location, or the audit log lists it as transformed.
3. **Given** a fixture with fields this version does not know, **When** it is migrated, **Then** the
   unknown fields are kept unchanged.

---

### User Story 2 - The original is kept before it is replaced (Priority: P1)

The first time the app saves over a migrated file (an autosave, a show scene edit), the original
bytes are kept next to it, so the user can return to the earlier version of the app with their
original scene.

**Why this priority**: A migration bug must never destroy the only copy of a scene.

**Independent Test**: Store an older-version file in a temporary folder, open it through the store,
save, and check that the backup holds the original bytes and is not changed by later saves.

**Acceptance Scenarios**:

1. **Given** an autosave main file of an older version, **When** the app saves the scene, **Then**
   `current.scene.v<N>.backup` holds the original bytes, and later saves leave it unchanged.
2. **Given** an existing backup of that version, **When** another migrated save happens, **Then** the
   backup is not overwritten.
3. **Given** the backup cannot be written, **When** the app saves, **Then** the save is refused and
   the original file is unchanged.
4. **Given** a current-version file, **When** the app saves, **Then** no backup is written.

---

### User Story 3 - What changed is recorded (Priority: P2)

Every migration produces an audit log (step, change, path) that tests, the repair report and the
QA-004 matrix can read; diagnostics record a privacy-safe summary.

**Why this priority**: Without a log, "no data loss" cannot be checked and a support question cannot
be answered.

**Independent Test**: Run a synthetic chain over a document and check the log entries and the
diagnostics event text.

**Acceptance Scenarios**:

1. **Given** a chain of steps, **When** a document is migrated, **Then** the log lists each step's
   changes in order with their JSON paths and a version change per step.
2. **Given** a migrated scene, **When** its repair report is built, **Then** it contains one note
   "Updated from an older format" and the report does not need review because of it.
3. **Given** a migrated autosave, **When** it loads, **Then** the diagnostics event names the versions
   and counts only.

---

### User Story 4 - Versions that cannot be migrated are refused as today (Priority: P2)

A scene from a newer app version, a version with no migration step, or a step that fails is refused
with a typed reason and shows "Cannot open"; nothing is written.

**Independent Test**: Decode files with version current+1, a version below the oldest step, a gap in
a synthetic chain and a failing step.

**Acceptance Scenarios**:

1. **Given** a newer version, **When** it is opened, **Then** it is refused as "newer version"
   (unchanged behaviour, SCN-002 still sets it aside).
2. **Given** a synthetic chain with a gap, **When** a document below the gap is migrated, **Then** it
   is refused naming the missing step.
3. **Given** a step that fails, **When** it runs, **Then** the document is refused naming the step and
   the path.

### Edge Cases

- Version 0, a negative, fractional or non-number version: refused as invalid (unchanged).
- A step that does not set the version itself: the migrator sets `version` after each step.
- A step that removes or renames a field must log it; the no-data-loss check fails otherwise.
- The backup name already exists (from an earlier run): it is kept, not replaced; the save proceeds.
- The autosave `.bak` is restored from and was older: it gets its own backup before it is removed.
- A show scene that no cue refers to is removed with its backups.
- Archives are read-only sources: an imported older scene is migrated in memory; the archive file is
  never changed, so no backup is written.

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-013-R1**: The scene format MUST provide a migration chain of steps, each from version N to
  N+1, registered in order, each declaring its identifier and a summary of what it changes.
- **SCN-013-R2**: A migrator MUST run the chain from a document's stored version to the current
  version on the raw document value and return the migrated value, the source and target versions
  and an audit log (step, change kind, path, detail).
- **SCN-013-R3**: Fields a step does not name MUST be kept unchanged (unknown fields included).
- **SCN-013-R4**: A version newer than the target MUST be refused as today; a version with no step
  to continue from MUST be refused naming the missing step; version < 1 with no step MUST stay an
  invalid version; a failing step MUST be refused naming the step and path.
- **SCN-013-R5**: Every scene decode MUST run the production chain first, so every reader (autosave,
  show scenes, archives, repair report, golden render scenes) gets the current schema; the decode
  result MUST carry the migration record.
- **SCN-013-R6**: The production chain MUST be empty while version 1 is the only version ever
  written; synthetic steps exist only in tests.
- **SCN-013-R7**: Opening a scene MUST NOT write any file.
- **SCN-013-R8**: Before the app first replaces a stored file whose content was migrated (autosave
  main or backup, show scene), it MUST write the original bytes to `<file name>.v<N>.backup` in the
  same folder, exclusively, never overwriting an existing backup.
- **SCN-013-R9**: If the backup cannot be written, the replacing save MUST be refused and the
  original kept.
- **SCN-013-R10**: Diagnostics MUST record a migration as versions, step and change counts, and a kept
  backup by its file name; no paths, names or other scene content.
- **SCN-013-R11**: A migrated document's SCN-012 report MUST contain one note entry "Updated from an
  older format" that does not make the report need review.
- **SCN-013-R12**: Golden legacy fixtures MUST cover every real historical shape and every current
  layer kind, asset type, parameter value, binding (mix, envelope, expression), modulation generator
  and connection, and unknown content, with a manifest giving each fixture's version, source and
  expected current-schema document; the layout MUST let QA-004 add a fixture by adding a manifest row.
- **SCN-013-R13**: Each fixture MUST migrate and encode to its expected document exactly, and every
  input value MUST be present in the output or listed as transformed by the audit log.
- **SCN-013-R14**: The migration code MUST stay plain Swift without Foundation, files, networking or
  execution of document content.
- **SCN-013-R15**: Show scenes removed because no cue refers to them MUST be removed with their
  backups.

### Key Entities

- **Migration step**: from-version, identifier, summary, a pure transformation of the raw document
  that records its changes.
- **Audit log entry**: step identifier, from and to version, change kind (renamed, added, removed,
  transformed, version), JSON path, detail.
- **Migration record**: source version, target version, log; "migrated" when they differ.
- **Original backup**: the stored file's original bytes, named by file and source version.
- **Golden legacy fixture**: input bytes, version, source (which writer and commit), expected
  current-schema document, coverage tags.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-013-S1**: 100% of golden legacy fixtures load into the current schema and match their
  expected documents exactly, with zero input values lost.
- **SCN-013-S2**: 100% of migrated stored files keep their original bytes in a backup before the first
  replacement; 0 backups are overwritten.
- **SCN-013-S3**: Every refusal case (newer, gap, below oldest, failing step) gives its typed reason
  and writes nothing.
- **SCN-013-S4**: Diagnostics events for migrations contain no scene content (checked by test).
- **SCN-013-S5**: The scene format test suite, fixtures included, still runs in under 1 minute; each
  test about 1-2 s at most.

## Assumptions

- Version 1 is current; the next format change (a later row) adds a v1→v2 step and fixtures by
  following the procedure recorded in ADR-0028's amendment.
- Backups are counted in the storage screen's "Scenes" category for the autosave folder (FILE-009);
  they are not listed one by one. Show scene backups are in the show folder, as the show's scenes are.
- No UI changes: the only user-visible text is the report note, which shows only with the existing
  report.
