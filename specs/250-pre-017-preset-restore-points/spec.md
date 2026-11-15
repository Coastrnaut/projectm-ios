# Feature Specification: PRE-017 Preset Restore Points

**Feature Branch**: `feature/pre-017` (spec directory `250-pre-017-preset-restore-points`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-017 (Preset restore points) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Keep bounded local versions of edited user presets."
Acceptance, verbatim: "Revert restores prior content and removes no unrelated files." P2, depends on PRE-015."

Identifiers in this feature carry the roadmap ID: requirements `PRE-017-R1…`, success criteria `PRE-017-S1…`,
research decisions `PRE-017-D1…`, tasks `PRE-017-T01…`. Other features are cited by their own IDs: PRE-010
(quick audition), PRE-011 (notes), PRE-012 (user presets), PRE-015 (duplication and editing), PRE-016
(overrides), PRE-018 (integrity scanner), FILE-003/004 (archive install and replace), FILE-005 (library backup),
FILE-009 (storage accounting), FILE-011 (erase).

## Baseline: what exists today (audit of 2026-11-14, commit `13d1be79`)

| Question | Today |
|---|---|
| User preset storage | PRE-012 `UserPresetStore` in `Application Support/UserPresets/`: `index.json` (versioned record), texts content-addressed as `files/<sha256>.milk`, `quarantine/<sha256>.milk`, crash records `trial.json`, `proving.json`, `edit.json`. Every file operation goes through one path guard that refuses anything outside the folder (PRE-015-R19). "Files no record names are left alone." |
| Editing | PRE-015 `UserPresetLibrary.edit(id, name:, text:, expectedSHA256:)`: a new text is checked statically, then tried on the off-screen engine with `edit.json` on disk, and only then replaces the stored one (`replaceContents`: new text, record, then the old text is **deleted**). A stale `expectedSHA256` is refused ("changed meanwhile"). |
| Earlier texts | **None.** Once an edit is saved the previous text is gone; there is no undo. |
| Per-preset data elsewhere | Notes (PRE-011), tags (PRE-003), overrides (PRE-016), collections, favorites and recents are keyed by the stable preset ID in `PresetCollections/`; thumbnails (PRE-001) are cached by content hash. An edit keeps the ID, so none of these change. |
| Integrity | PRE-018 checks records' stored files and dangling references; it never lists or deletes unnamed files. |
| Backup, storage, erase | FILE-005 backs up the records and their live texts (logical, not the folder); a restore stages a copy of the live `UserPresets` folder and edits it. FILE-009 sizes the whole `UserPresets` folder. FILE-011 removes the whole folder. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is a restore point (a "version")? → A: The text a user preset had just before a saved edit replaced it, with the time it was replaced, its size and the preset's name at that moment. Renames alone keep no version (the text did not change). A version is identified by its content hash; one preset never lists the same text twice (a repeated text moves to the newest place).
- Q: How many versions are kept? → A: Bounded twice: at most 10 per preset, and in total at most 500 versions and 50 MB of version texts across all presets. When a bound is exceeded the oldest versions are dropped first (per preset for the per-preset bound, globally by time for the totals).
- Q: Where are they stored? → A: Inside the preset folder: version texts content-addressed as `versions/<sha256>.milk` (a folder separate from `files/`, so live texts and earlier texts never mix), and their list in a sidecar `history.json` (schema version 1, the store's usual rules: newer version = versions unavailable and the file untouched, unreadable = set aside). A version text file is deleted only when no version of any preset names it any more (reference counting).
- Q: How is a version restored? → A: "Versions…" on an editable user preset lists its earlier versions, newest first, with date, time and size. Each offers Preview (shows the earlier text read-only) and Revert. Revert goes through the PRE-015 edit path unchanged: the same static checks, the same off-screen engine trial and `edit.json`, and the same "changed meanwhile" guard. The text being replaced becomes a version itself, so a revert can be undone.
- Q: Why not render the earlier version on the visualizer (PRE-010 audition) as Preview? → A: Only the stored text of a playable preset is ever handed to a renderer (PRE-012-R20), and an earlier text has not been tried again on this engine. Showing it read-only is the safe preview; it is tried by Revert before it plays.
- Q: Which files may a revert change? → A: Only the preset's own live text (`files/`), the record (`index.json`), `history.json`, and version texts in `versions/` that it adds or that no version names after pruning. No other preset's text, no other version that is still named, no collection, tag, note, override, favorite or thumbnail file is removed or changed.
- Q: What happens to versions when a preset is removed? → A: Its versions are removed with it (its list entries, then each version text no other version names).
- Q: Do versions travel in backups and exports? → A: No. They are local restore points: FILE-005 backs up the live text only (the library backup's format is unchanged) and PRE-014 exports only live texts. A restore keeps the device's existing versions (it copies the live folder). FILE-009 counts them inside "Presets"; FILE-011's presets erase removes them with the folder.
- Q: Do existing presets need a migration? → A: No. A preset with no list entry has no versions; the first edit after the update starts its list. No `index.json` schema change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Revert an edit (Priority: P1) — MVP

I edited my copy of a preset and the result looks worse. I touch and hold it in My Presets, choose Versions…,
see the earlier version saved a few minutes ago, preview its text, and tap Revert. After the check, my preset
plays its earlier text again; the version I reverted from is now listed, so I can go back.

**Why this priority**: It is the row's observable behavior and its acceptance.

**Independent Test**: Package test: edit a preset twice, revert to the first text: the stored bytes' SHA-256
equals the original's, and the set of files under the library folders before and after differs only in the
version bookkeeping. UI test: a seeded preset with one version is reverted from the Versions sheet.

**Acceptance Scenarios**:

1. **Given** a preset whose text was edited, **When** I revert to the earlier version, **Then** its stored text is byte for byte the earlier text and the text it replaced is listed as a version.
2. **Given** other presets, their versions, collections, tags, notes, overrides and thumbnails, **When** I revert, **Then** none of their files is removed or changed.
3. **Given** an earlier text that no longer passes the checks (for example a texture the app no longer has), **When** I revert, **Then** nothing changes and the reason is shown, as for an edit.
4. **Given** the preset was edited elsewhere after the sheet opened, **When** I revert, **Then** it is refused as "changed meanwhile".

### User Story 2 - Versions stay bounded (Priority: P1)

**Why this priority**: "Bounded" is part of the observable behavior; storage must not grow without limit.

**Independent Test**: Package tests with small injected limits: the 11th edit drops the oldest version; the
total bounds drop the globally oldest; a version text still named by another preset's version is never deleted.

**Acceptance Scenarios**:

1. **Given** 10 versions of a preset, **When** I save another edit, **Then** the oldest is dropped and its text file is deleted unless another version names it.
2. **Given** two presets whose versions name the same text, **When** one preset's version is dropped, **Then** the text file stays.

### User Story 3 - Versions are kept safely (Priority: P2)

**Independent Test**: Store tests: a newer `history.json` is untouched and versions are unavailable while edits
still save; an unreadable one is set aside; a failed save leaves every file as before; removing a preset removes
its versions; presets saved before this feature have none and edit normally; a library backup round trip keeps the
device's versions.

### Edge Cases

- The stored text of the preset is missing or damaged (PRE-018 "missing file"): the edit or revert keeps no version of it (there are no trustworthy bytes) and says nothing more than the edit does today.
- The earlier text is identical to another user preset's current text: refused as for an edit ("same as <name>").
- The earlier text now equals a built-in preset: refused as for an edit.
- A copy of a locked pack while the library is locked: Versions… is not offered (it is not editable).
- A quarantined preset keeps its versions; they are offered again when it is playable.
- An app ending during a revert's check: `edit.json` drops the unchecked revert at launch, as for an edit.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-017-R1**: Each saved text change of a user preset (PRE-015 edit or revert) MUST keep the replaced text as a version of that preset: content hash, size, the time it was replaced and the preset's name then. A rename alone keeps none. The same text MUST appear at most once per preset (the newest occurrence).
- **PRE-017-R2**: Versions MUST be bounded: at most 10 per preset, 500 in total and 50 MB of distinct version texts; the oldest are dropped first. Pruning MUST NOT delete a version text that any remaining version of any preset names.
- **PRE-017-R3**: Version texts MUST be stored content-addressed in `UserPresets/versions/` and listed in `UserPresets/history.json` (schema version 1; newer = unavailable and untouched, unreadable = set aside as `history.unreadable.json`, written atomically). Every file operation MUST go through the store's path guard.
- **PRE-017-R4**: Saving an edit with a version MUST be one transaction: the version text and list are written before the record; if the record cannot be saved, the list and every file this edit added are restored and nothing changed. If the version cannot be kept the edit MUST be refused (no text is lost silently). The version list being unavailable (newer format) MUST NOT block edits; they save without a version.
- **PRE-017-R5**: Revert MUST read the version text, check its size and SHA-256, and save it through the PRE-015 edit path (static checks, engine trial, `edit.json`, "changed meanwhile"). It MUST restore the exact bytes of the version.
- **PRE-017-R6**: A revert MUST NOT remove or change any file except the preset's live text, `index.json`, `history.json` and version texts it adds or leaves unnamed.
- **PRE-017-R7**: Removing a user preset MUST remove its versions and every version text no remaining version names. At load, version texts no version names MUST be deleted (left by an interrupted save) — only in `versions/`, only names of the form `<sha256>.milk`, and only when the list was read (never after it was set aside or is newer). List entries for preset IDs the record no longer has MUST be dropped.
- **PRE-017-R8**: The browser row of an editable user preset MUST offer "Versions…" (touch-and-hold menu and a VoiceOver action). The sheet lists versions newest first ("<date, time> · <size>", the name at that time when it differs), each with Preview (the text read-only) and Revert (confirmed: "Revert to this version? Your current text is kept as a version."), shows "No earlier versions." when empty, and shows the check's progress and any refusal as the editor does. A successful revert announces "Reverted <name>." on the library lane and closes the sheet.
- **PRE-017-R9**: Versions MUST stay local: not in the library backup, preset exports or diagnostics. A library restore MUST keep the device's versions.
- **PRE-017-R10**: The version model, list file and store logic MUST be Foundation-only Swift in `PresetLibrary` that builds on Linux.

### Key Entities

- **UserPresetVersion**: content hash, git blob hash, size, replaced-at time, name then.
- **UserPresetHistoryFile**: schema 1; per preset ID an ordered list of versions (oldest first).
- **UserPresetVersionLimits**: per preset 10, total 500, total bytes 50 MB.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-017-S1**: After edits A→B→C, reverting to A stores bytes whose SHA-256 equals A's, and the sorted list of every file (path, size, hash) under the library folders before and after differs only in `files/` (C added to versions, A live), `index.json`, `history.json` and `versions/` — every other file is identical (package test).
- **PRE-017-S2**: The per-preset and total bounds drop the oldest versions; a text named by another remaining version is never deleted (package test).
- **PRE-017-S3**: Presets with no history edit and revert normally; a newer list is untouched; an unreadable list is set aside; a failed record save restores everything (package tests).
- **PRE-017-S4**: A library backup and restore keeps the preset's versions and its reverted text (LibraryBackup test).
- **PRE-017-S5**: In the app on a simulator, reverting a seeded preset from the Versions sheet succeeds (UI test under 30 s).

## Assumptions

- No new UserDefaults key.
- 50 MB is about 100 maximum-size texts; typical presets are 5-20 KB, so 500 versions usually fit.
- Archive replacements (FILE-004) and library restores replace texts of presets that are waiting for their trial; they are not user edits and keep no version (the preset's earlier versions stay).
