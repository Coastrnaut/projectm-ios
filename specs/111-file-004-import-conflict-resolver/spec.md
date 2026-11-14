# Feature Specification: FILE-004 Import Conflict Resolver

**Feature Branch**: `feature/file-004` (spec directory `111-file-004-import-conflict-resolver`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FILE-004 (Import conflict resolver) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Choose skip, rename or replace
for duplicate local scene IDs." Acceptance, verbatim: "Each choice yields deterministic IDs and no
partial overwrite." P1, M, depends on FILE-001 (integrated). Verification: schema and fixture tests
plus the simulator. Builds on FILE-003 (import dry run, integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-004-R1…`, success criteria `FILE-004-S1…`, tasks `FILE-004-T01…`.

## Baseline: where local IDs can collide (audit of 2026-11-14, commit `b4f2abf9`)

The row's gap status is "Gap candidate". The audit confirms a gap: FILE-003 offers only Keep both
and Skip for whole archives, and nothing installs an imported scene next to stored scenes.

| Item with a local ID | Where it lives | Can an import collide with it? | Today |
|---|---|---|---|
| User preset `id` (`user/…`, PRE-012) | `Application Support/UserPresets/index.json`, texts content-addressed in `files/` and `quarantine/` | **Yes**: a preset archive (PRE-014 format) carries each preset's identifier and name | FILE-003: ID and name conflicts are detected; Keep both (renamed copy, derived ID) or Skip for the whole archive. Replace deferred to this row |
| Preset references | Collections (PRE-007, `PresetCollections/`) list preset identifiers | Only through a preset whose identifier changes or disappears | Keep both never changes an existing identifier |
| Scene `id` (SCN-001, canonical uppercase UUID) | Show scenes: `Application Support/Show/Scenes/<ID>.scene.json` (SHOW-001, SCN-003); the file name is the ID | **Yes**: a scene archive (FILE-001) carries the scene document with its `id`; re-importing an exported scene, or a friend's scene exported from the same original, gives the same ID | No install path into the show exists: `SceneArchiveService.importArchive` adopts the media and returns the document; the scene import screen (SCN-014) that would store it is not built |
| Scene references | Show cues (`show.json`) refer to scenes by scene ID; the show removes scene files no cue refers to | Through a scene whose ID changes or whose content is replaced | — |
| Current scene (SCN-002 autosave, `Application Support/Scenes/current.scene`) | One document, not keyed by ID | No: opening any scene replaces it, whatever its ID | — |
| Layer instance IDs, asset keys, binding source IDs inside a scene | Inside one scene document | No: scoped to their document (SCN-001); a copy keeps them unchanged (SCN-003) | — |
| Photo and video store IDs (MED-001/MED-002) | Photo and video stores | No: an import stages the media and the stores mint new UUIDs; the scene is remapped (FILE-001) | — |

So "duplicate local IDs" are preset identifiers (and names) in My Presets and scene IDs in the show's
scene folder.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which imports get the resolver? → A: Both kinds that can collide (Baseline). The preset archive import gets per-conflict choices in FILE-003's preview sheet. Scene archives get the planner and the all-or-nothing installer into the show's scene folder, tested in the package, with no screen: the scene import screen is SCN-014 (not built); SCN-014 shows these choices when it is built.
- Q: Which choices exist? → A: Three, per conflicting item: **Skip** (leave it out; the existing item is not touched), **Rename** (keep both: install the incoming item under a derived ID and, when its name is taken, a "copy" name; FILE-003's "Keep both", shown as "Keep both" in the preview because it says what happens to the user's item), and **Replace** (the incoming content takes the existing item's place). The sheet offers a default choice that applies to every conflict ("Apply to all"), plus a choice per conflict row that overrides it.
- Q: Which is the default? → A: Keep both (Rename), as in FILE-003: it installs everything picked and destroys nothing. Replace is never the default.
- Q: What ID does Rename give? → A: A derived ID, the same for the same incoming item and content into the same library, whatever process or run: presets keep FILE-003's rule (`user/` + 32 hex digits of SHA-256 of "FILE-003|incoming id|text SHA-256|n", the smallest n ≥ 1 not taken); scenes get a canonical uppercase UUID made from SHA-256 of "FILE-004|scene|incoming id|scene content SHA-256|n" (version nibble 8, RFC 9562 variant), the smallest n ≥ 1 not taken by a stored or earlier planned scene. Content, not the archive's bytes, is hashed so a re-export of the same item (a new export date changes the archive's bytes) gets the same ID, and different content gives a different ID.
- Q: What name does Rename give? → A: The incoming name when it is free; otherwise "<name> copy", then "<name> copy 2", … (FILE-003's and PRE-015's copy naming), compared without regard to case against the library and names planned earlier in the same import.
- Q: What does Replace keep? → A: The existing item's identifier. A replaced preset keeps its `user/…` identifier, so every collection that lists it stays valid; its text, name and metadata become the incoming ones and it waits for its check again (PRE-012 trial). A replaced scene keeps its scene ID, so every cue that refers to it stays valid and now shows the imported scene; the preview says how many cues use it. Nothing referring to the old item ever dangles.
- Q: Is Replace offered for presets too? → A: Yes (FILE-003 deferred it to this row) for presets and scenes. For a preset it is offered for an ID conflict (target: the preset with that identifier) and a name conflict (target: the library preset with that name). When the clash is only with another item of the same import, or the target is already replaced by an earlier item, Replace falls back to Keep both (recorded in the plan; the row says so).
- Q: What does "no partial overwrite" mean? → A: An install is all or nothing. New content is staged and verified first; the old content of every replaced item is kept as a backup until a single commit point (the record write: the preset index, the scene import journal); a failure at any step before the commit restores the library byte for byte; after the commit only clean-up remains, and an unfinished clean-up is completed at the next load. Each item is either entirely the old one or entirely the new one, never a mix.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose what happens to each clashing preset (Priority: P1)

A user imports a preset archive. Two presets clash with presets they have. In the preview, each
clashing row has its own choice: they keep both for one and replace the other; the counts and the
Install button update; Install does exactly that.

**Why this priority**: It is the row's behaviour on the only import with a screen today.

**Independent Test**: A fixture archive with two conflicts and mixed choices installs exactly the plan's
identifiers and names; the replaced preset keeps its identifier with the new text.

**Acceptance Scenarios**:

1. **Given** a name conflict and the choice Keep both, **When** Install runs, **Then** the incoming preset is added as "<name> copy" under the derived identifier and the existing preset is byte-identical.
2. **Given** an ID conflict and the choice Replace, **When** Install runs, **Then** the preset keeps its identifier, its text and name are the incoming ones, it waits for its check, and its old text is gone.
3. **Given** a conflict and the choice Skip, **When** Install runs, **Then** the existing preset is byte-identical and nothing is added for that row.
4. **Given** "Apply to all: Skip" and one row set to Replace, **When** Install runs, **Then** only that row replaces; every other conflict is skipped.

### User Story 2 - No partial overwrite (Priority: P1)

An install that replaces presets fails part-way (a full disk). Afterwards every preset is exactly as
before: no new text, no old text lost, no half-written record.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Inject a fault at every file operation of a mixed install; after each, the library
snapshot equals the one before; after the successful run only the planned items changed.

**Acceptance Scenarios**:

1. **Given** a plan with Replace, Keep both and new presets, **When** any file operation fails before the commit, **Then** the library is byte-for-byte as before and the preview says "Nothing was installed."
2. **Given** the same plan, **When** a clean-up step after the commit fails, **Then** the install counts as done and the next load leaves the library exactly as a clean install would.

### User Story 3 - Deterministic IDs (Priority: P1)

The same archive previewed twice, or on another launch, shows the same identifiers and names for
every choice; a different archive's items get different identifiers.

**Independent Test**: A table of inputs → IDs computed in two separate runs and two processes.

### User Story 4 - Scene conflicts, no screen (Priority: P2)

The scene import service can plan the install of an imported scene into the show's scene folder:
a scene whose ID is already stored is a conflict; Skip, Rename (derived UUID, copy name) or Replace
(same ID, cues keep pointing at it) are installed all or nothing; a new scene gets a cue so the show
keeps it.

**Independent Test**: Package tests with fixture scenes and a stored show.

### User Story 5 - The library changed meanwhile (Priority: P2)

Between preview and Install a clashing preset or scene was removed or changed. Install plans again
with the same choices; a different plan is shown instead of being installed.

### Edge Cases

- A choice for an entry that is no longer a conflict (library changed) is ignored when planning again; the new plan is shown.
- Two incoming presets with the same name: the second is a conflict with the first (planned), so Replace falls back to Keep both for it.
- An incoming preset that clashes by ID with one preset and by name with another: Replace targets the ID match; the name becomes a copy name if still taken by the other.
- Replacing a quarantined preset: the record leaves quarantine and waits for its check with the new text; its quarantined copy is removed at the commit.
- Replacing a preset that is held (unplayable after an interrupted check) is refused with nothing written.
- A replaced preset that was being checked when Install ran: the check's result is discarded (its text changed).
- Identical content (same text, or same scene bytes under the same ID) is never a conflict: it is skipped as in FILE-003.
- Replacing a scene with an older format version: its SCN-013 original backups are left as they are.
- The show file or scene folder from a newer app version: the scene install is refused.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-004-R1**: Every conflict (preset ID or name conflict; scene ID conflict) has exactly one choice: Skip, Keep both (Rename) or Replace. A plan has a default choice ("Apply to all"), Keep both unless the user changes it, and per-item overrides keyed by the item's incoming identifier.
- **FILE-004-R2**: Keep both installs under a derived identifier (Clarifications rule) when the identifier is taken, and under the copy name when the name is taken; equal inputs give equal identifiers and names in every run and process; different content gives different identifiers.
- **FILE-004-R3**: Replace keeps the existing item's identifier and replaces its content, name and metadata with the incoming ones. A replaced preset is waiting (unchecked); a replaced scene keeps every cue that refers to it.
- **FILE-004-R4**: Replace targets only an item stored in the library before the import; a conflict only with an earlier item of the same import, or with a target already replaced, is installed as Keep both, and the plan records the fallback.
- **FILE-004-R5**: Skip leaves the existing item byte-identical and adds nothing for that entry.
- **FILE-004-R6**: An install is all or nothing: new content staged and verified, replaced content kept as a backup, one commit point, full restore on any failure before it; an unfinished clean-up after it is completed at the next load. No item is ever left partly overwritten.
- **FILE-004-R7**: Install plans again with the same archive, default and overrides; a different plan is returned with nothing written (FILE-003-R8).
- **FILE-004-R8**: The preset preview shows the "Apply to all" choice and, on each conflict row, that row's choice with what it will do ("Installed as …", "Replaces “…”", "Left out"); counts, size and the Install button follow the plan. Controls are reachable at the largest accessibility text sizes; nothing animates.
- **FILE-004-R9**: Announcements (preview, install with replaced count, failures) go through the shared announcer's `library` lane.
- **FILE-004-R10**: The scene side offers a pure planner (incoming scenes against the stored scenes and show) and an installer into the show's folder with the same choices and guarantees; a new or renamed scene gets one cue (deterministic cue ID) so the show keeps it; Replace keeps the existing cues. No screen (SCN-014).
- **FILE-004-R11**: No networking, nothing from an archive executed, no new permission; public APIs only.

### Key Entities

- **Conflict choice**: Skip, Keep both, Replace.
- **Preset import plan** (extends FILE-003): default choice, overrides, per entry its effective choice, the replaced preset (identifier, name) and whether Replace fell back.
- **Scene import plan**: per incoming scene its kind (new, identical, ID conflict with the stored scene's name and the number of cues using it), choice, final ID and name, the replaced scene, and the cue to add.
- **Library snapshot**: FILE-003's byte-level tree snapshot, used for every equality check.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-004-S1**: For every fixture and every choice, planning twice (and in two processes) gives identical plans; a different content gives different identifiers (the ID table passes 100%).
- **FILE-004-S2**: A mixed install (Replace, Keep both, Skip, new) with a fault at each file operation before its commit leaves the library snapshot identical every time; after success only the planned items differ.
- **FILE-004-S3**: Skip leaves every existing item byte-identical (snapshot of the item's files and record).
- **FILE-004-S4**: After Replace, every collection or cue that referred to the replaced item still resolves to it.
- **FILE-004-S5**: A library changed after the preview is detected at Install with nothing written.
- **FILE-004-S6**: A simulator UI test changes one conflict row's choice in the preview at the largest accessibility size, sees the plan follow, and cancels with the library unchanged, in under 30 seconds.

## Assumptions

- FILE-003's planner, preview sheet, staged install and snapshot are the base; its classification is unchanged.
- Preset archives contain each identifier at most once (the reader refuses duplicates), so overrides keyed by incoming identifier are unambiguous; scene inputs are deduplicated the same way.
- Simulator results prove behaviour only, never performance.

## Out of Scope

- The scene import screen and how it presents the scene plan (SCN-014).
- Folder import and progress (PRE-013).
- Merging two items' contents.
