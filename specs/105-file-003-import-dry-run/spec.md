# Feature Specification: FILE-003 Import Dry Run

**Feature Branch**: `feature/file-003` (spec directory `105-file-003-import-dry-run`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FILE-003 (Import dry run) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Preview counts, conflicts and
missing licenses before installing archive." Acceptance, verbatim: "Cancel leaves library
byte-for-byte unchanged." P1, M, depends on FILE-001 (integrated). Verification: schema and fixture
tests plus the simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-003-R1…`, success criteria `FILE-003-S1…`, tasks `FILE-003-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `63867693`)

The row's gap status is "Gap candidate". The audit confirms a full gap: no import shows anything
before it writes.

| Import | Entry point today | Writes immediately? | Preview today |
|---|---|---|---|
| One `.milk` preset (PRE-012) | My Presets → "Import Preset…" (Files picker) → `UserPresetsCoordinator.importPicked` → `UserPresetLibrary.importFile` | Yes: the copy and the index are written at once (a refusal writes nothing); the preset then waits for its off-screen trial | None; an alert reports the outcome afterwards |
| User preset archive, `org.projectmios.user-presets` v1 (PRE-014 format) | **None in the app.** `UserPresetArchiveReader` validates an archive (whole-archive refusals) but only tests call it; its header says PRE-013 (bulk import, not implemented) will reuse it. Choosing a `.zip` in "Import Preset…" is refused as the wrong type | n/a | None |
| Scene archive `.pmscene` (FILE-001, FILE-002, FILE-007, SCN-012, SCN-013) | **No screen** (FILE-001 Clarifications: the Files/Share entry points are SCN-014, not built). `SceneArchiveService.importArchive(at:)` exists and is tested | Yes, in one call: copy the picked file to a staging folder, verify (checksums, schema, scene decode and migration, content checks), stage the media through staging stores, remap, then adopt into the real photo/video stores and switch the current IDs (all or nothing; previous copies deleted). The result carries `replacedPhoto`/`replacedVideo` "for FILE-003" and SCN-012's `repairReport`, but only after the commit | None |
| Collections (PRE-007), storage screen (FILE-009/010), permission catalog (FILE-013) | Not import paths; unaffected | — | — |

Licence metadata today: each user preset records the licence lines found in its text
(`PresetLicenseMetadata.linesFound`, at most 5) and never verified rights; a preset with no lines
shows "No license information was found in the file." (PRE-012). Copies of Included presets
(PRE-015) carry their pack's statement in `duplicateOf`. Scenes and their media carry no licence
data.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which archives get a dry run? → A: Both archive kinds the app reads. The user preset archive gets the full flow with a screen: "Import Preset…" now also accepts a preset archive (`.zip`), which opens the preview before anything is stored; a `.milk` keeps PRE-012's one-file flow unchanged. The scene archive gets the planner and the plan-checked install in the service, with no screen, because the scene import screen (SCN-014) does not exist yet; SCN-014 shows the plan when it is built.
- Q: What is "the library"? → A: For presets, everything the user preset library owns on disk: its folder (`UserPresets`: index, stored copies, quarantine, step records) and the collections folder (PRE-007), plus any UserDefaults key the preset screens own. For scenes, the photo and video store folders and their current-ID UserDefaults keys. "Byte-for-byte unchanged" means the same relative paths, the same SHA-256 of every file, the same directories, and the same values of those keys.
- Q: What does the preview count? → A: Every preset in the archive lands in exactly one row: **new** (will be added), **identical** (the same text is already in My Presets or Quarantine; skipped), **name conflict** (a different preset with the same name, compared without regard to case), **ID conflict** (a different preset with the same identifier), **refused** (with its reason: on the takedown list, the same as a built-in preset, fails the safety checks, or My Presets is full). Missing licences are counted across the presets that would be installed. The total size of what will be installed is shown.
- Q: Which conflict policies are offered, and which is the default? → A: **Keep both** (default) and **Skip**. Keep both installs the incoming preset under a new identifier and, for a name conflict, the name "<name> copy" (PRE-015's copy naming); it never touches the existing preset. Skip leaves conflicting presets out. **Replace is not offered in this row**: it deletes user data and is exactly FILE-004's row (import conflict resolver); FILE-003 records the conflict and leaves the destructive choice to FILE-004. Keep both is the default because it installs everything the user picked and destroys nothing.
- Q: Is a preset that fails the safety checks quarantined like a picked `.milk`? → A: No. In an archive it is refused in the preview with its reason and not installed; quarantine is for a single file the user explicitly chose. Installing a whole archive must not fill Quarantine.
- Q: Do installed presets play at once? → A: No. They are installed as waiting and go through PRE-012's off-screen trial like any import (archive records are never trusted as checked).
- Q: What does "missing licence" mean? → A: A preset to be installed with no licence lines found in its text, except a copy of an Included preset, which carries its pack's statement. It is a warning in the preview, not a refusal (PRE-012 imports such files with the same notice).
- Q: What if the library changes between the preview and Install? → A: Install plans again against the library as it is now; if the new plan differs from the one shown, nothing is installed and the preview is shown again with the new plan and the sentence "My Presets changed since this preview. Check the new counts and install again."
- Q: What does Cancel do? → A: Closes the preview, discards the in-memory plan and any temporary staging, and leaves the library byte-for-byte unchanged. Nothing is announced besides the preview's own announcement.
- Q: What does a scene archive's plan contain? → A: Either the typed refusal (FILE-001/FILE-002/FILE-007/SCN-013 reasons, including a newer scene version and an oversize archive), or: the scene's media to import (photo, video, sizes), which current photo or video it replaces (the conflict), SCN-012's repair entries as they will be after the install, the total size, and the steps (stage, adopt, make current). Scenes carry no licence data, so the plan's licence list is always empty (recorded, not guessed).

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Does an installed preset keep the identifier it has in the archive? → A: Yes, whenever that identifier is free in the library; a new identifier is made only for an ID conflict under Keep both. Keeping identifiers makes a re-import of the same export recognisable and keeps the record stable across devices (FILE-003-R6).
- Q: How is "identical" decided, and what about a text that sits in Quarantine? → A: By the SHA-256 of the preset's text, as PRE-012 detects duplicates. The same text as a playable, waiting or held preset is **identical** (skipped). The same text as a quarantined file is **refused** with "The same file is in Quarantine." (PRE-012 refuses that file too), so Quarantine is never bypassed (FILE-003-R4).
- Q: Are names compared only with the library, or also within the archive? → A: With the library and with the names already planned earlier in the same archive (archive order), without regard to case. So two incoming presets with one name give one new preset and one name conflict, and Keep both's copy names never collide (FILE-003-R4, R6).
- Q: How does "Import Preset…" tell an archive from a preset file? → A: By the picked file's extension: `.zip` (any case) opens the archive preview; everything else keeps PRE-012's path, which still refuses non-`.milk` files. The archive's content is then verified by the reader, so a renamed file is refused safely (FILE-003-R1).
- Q: What is announced, and on which lane? → A: When the preview opens: "Import preview: N new, N already in My Presets, N conflicts, N refused."; when Install finishes: "Installed N presets. They are checked before they can play." or "Nothing was installed. <reason>". They go through ACC-004's shared announcer on a new `library` lane, so they never swallow or are swallowed by preset, capture or status announcements (FILE-003-R13).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview a preset archive before installing it (Priority: P1)

A user received a preset archive from a friend (exported with PRE-014). In My Presets they tap
"Import Preset…" and choose the `.zip`. Before anything is stored, a sheet shows how many presets
are new, how many are already there, which clash by name or identifier, which are refused and
why, which have no licence information, and how much space it takes. They tap Install, and the
new presets appear as waiting to be checked.

**Why this priority**: It is the row's behaviour; without it an archive cannot be imported at all.

**Independent Test**: Fixture archives against a seeded library give exact counts; Install adds
exactly the planned presets.

**Acceptance Scenarios**:

1. **Given** an empty My Presets, **When** the user picks an archive of three valid presets, **Then** the preview shows 3 new, 0 identical, 0 conflicts, 0 refused, and Install adds three waiting presets.
2. **Given** My Presets already holds one of the archive's texts, **When** the preview opens, **Then** that preset is counted as identical and Install skips it.
3. **Given** a preset in the archive has no licence lines, **When** the preview opens, **Then** it is listed under missing licence information and still installed.

### User Story 2 - Cancel changes nothing (Priority: P1)

The user opens the preview and taps Cancel. My Presets, Quarantine and the collections are
exactly as before, down to every byte on disk.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Snapshot the library tree (paths and SHA-256 of every file) and the owned
UserDefaults keys, run the dry run, cancel, compare.

**Acceptance Scenarios**:

1. **Given** any fixture archive, **When** the user previews and cancels, **Then** the snapshot is identical.
2. **Given** an install fails part-way (injected fault), **When** the failure is reported, **Then** the snapshot is identical to before the install.

### User Story 3 - Choose what happens to conflicts (Priority: P2)

Two presets in the archive clash with presets the user has: one has the same name, one the same
identifier. The preview defaults to Keep both; the user can switch to Skip, and the counts and
size update before Install.

**Acceptance Scenarios**:

1. **Given** a name conflict and Keep both, **When** Install runs, **Then** the incoming preset is added as "<name> copy" with a new identifier and the existing one is untouched.
2. **Given** Skip, **When** Install runs, **Then** neither conflicting preset is added.

### User Story 4 - The library changed meanwhile (Priority: P2)

The preview is open; meanwhile a waiting preset is removed or a trial changes the library. Install
notices that the plan no longer matches and shows the new plan instead of installing a stale one.

### User Story 5 - Scene archive plan (Priority: P3, no screen)

The scene archive service can describe an import (media, replaced photo or video, repair entries,
size, refusal) without touching the stores, and installs only the plan it described.

### Edge Cases

- A malformed or tampered archive, a wrong format, a newer format version, too many presets: the whole archive is refused in the preview with the reader's reason; only Close is offered.
- An archive larger than the archive limit: refused before it is read.
- Every preset identical or refused: Install is disabled ("Nothing to install").
- My Presets from a newer app version (read-only): the preview is refused with PRE-012's newer-format words.
- More new presets than the 1,000-preset limit allows: the excess (in archive order) is refused as "My Presets is full".
- Two incoming presets whose renamed copies would collide: copy names are chosen against the library and the earlier planned names.
- Another import or export running: the archive import is not started (as today).

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-003-R1**: "Import Preset…" accepts a preset archive (`.zip`, any case) as well as a `.milk` file. Picking an archive opens the import preview; nothing is stored before Install. A `.milk` keeps PRE-012's flow.
- **FILE-003-R2**: The dry run writes nothing the library owns: no file or directory in the user preset folder or the collections folder, and no owned UserDefaults key. The picked file is read once into memory under its security scope, within the archive size limit.
- **FILE-003-R3**: An archive the reader refuses is shown as a refused preview with the reader's message; Install is not offered.
- **FILE-003-R4**: Every preset of an accepted archive is classified as exactly one of: new, identical (same text SHA-256 as a playable, waiting or held preset), name conflict (case-insensitive, against the library and names planned earlier in the archive), ID conflict, refused (same text as a quarantined file, takedown list, same as a built-in preset, fails the safety checks, My Presets full). Refusal and identical win over every conflict; a preset that is both a name and an ID conflict counts as an ID conflict.
- **FILE-003-R5**: The preview lists the presets to be installed that have no licence lines (copies of Included presets excepted) under "No license information", as a warning.
- **FILE-003-R6**: An installed preset keeps its archive identifier when it is free. Conflict policy: Keep both (default) installs a conflicting preset under a new identifier, renamed "<name> copy" ("<name> copy N") when its name is taken; Skip leaves it out. Replace is not offered (FILE-004).
- **FILE-003-R7**: The plan states the counts, the total bytes to install, and the ordered actions (each preset's final identifier and name), and the preview shows them.
- **FILE-003-R8**: Install first plans again against the current library with the same archive and policy. If the new plan differs, nothing is written and the preview shows the new plan with the changed-library sentence.
- **FILE-003-R9**: Install is all or nothing: the texts are staged and checked in a temporary folder, then moved into the library, and the index is written once at the end. A failure at any step removes everything it added, leaving the library byte-for-byte as before, and reports "Nothing was installed." with the reason.
- **FILE-003-R10**: Installed presets are waiting (not checked) and go through PRE-012's trial; the install result is announced.
- **FILE-003-R11**: Cancel (or closing the sheet) discards the plan and any staging folder; the library stays byte-for-byte unchanged.
- **FILE-003-R12**: The scene archive service offers a dry run returning a scene import plan (refusal, or media, replaced photo/video, SCN-012 repair entries after the install, total size, steps; an empty licence list) without staging into or touching the stores; its install re-checks that the archive's bytes and the current photo and video are those the plan saw, else refuses with "changed", and then runs FILE-001's all-or-nothing import.
- **FILE-003-R13**: The preview's and the install's announcements (Clarifications wording) go through the app's shared announcer on its `library` lane; the sheet works at the largest accessibility text sizes (Install and Cancel reachable); any animation follows the app's motion policy.
- **FILE-003-R14**: No networking, nothing from an archive executed, no new permission.

### Key Entities

- **Import plan (presets)**: the archive's identity (SHA-256 of its bytes), the policy, one entry per archive preset (incoming identifier and name, classification, final identifier and name when installed, size, licence present), the counts, the missing-licence list, the total bytes, or a whole-archive refusal.
- **Library snapshot**: relative path → SHA-256 for every file and the list of directories under the owned folders, plus owned UserDefaults values; used by the tests to prove byte-for-byte equality.
- **Scene import plan**: archive SHA-256, current photo/video IDs seen, media entries, replaced photo/video, repair entries, total bytes, steps, or a refusal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-003-S1**: For every fixture archive (clean, name conflict, identical content, missing licence, malformed entry, newer version, oversize), dry run then Cancel leaves the library snapshot identical (7 of 7).
- **FILE-003-S2**: An install with a fault injected at each write step leaves the snapshot identical (every step).
- **FILE-003-S3**: Each fixture gives its exact expected plan (counts, entries, licence list, size).
- **FILE-003-S4**: After Install the library holds exactly the plan's presets, with the plan's identifiers and names, as waiting.
- **FILE-003-S5**: A library changed after the preview is detected at Install with nothing written.
- **FILE-003-S6**: The simulator UI test previews an archive, cancels, and finds the library unchanged, in under 30 seconds.
- **FILE-003-S7**: A scene archive dry run and cancel leaves the photo and video stores and their keys identical; its install executes the plan; a changed store or archive is refused.

## Assumptions

- The archive format is PRE-014's `org.projectmios.user-presets` v1; its reader's whole-archive refusals are kept unchanged.
- The planner's inputs (archive, library records, import context) fit in memory: at most 1,000 presets of 512 KiB.
- Collections reference preset identifiers; Keep both never changes an existing identifier, so collections are unaffected.
- Simulator results prove behaviour only, never performance.

## Out of Scope

- Replace on conflict and per-preset choices (FILE-004).
- Folder import and progress (PRE-013).
- The scene import screen (SCN-014).
