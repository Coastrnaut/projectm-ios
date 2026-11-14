# Feature Specification: PRE-018 Preset integrity scanner

**Feature Branch**: `feature/pre-018` (spec directory `194-pre-018-integrity-scanner`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row PRE-018 (`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table), verbatim: "Scan user
library for missing textures and invalid references." Acceptance, verbatim: "Broken fixture is reported
with actionable relink suggestion." Priority P1, effort M, depends on PRE-012 (integrated).

**ID convention**: requirements `PRE-018-R1…`, success criteria `PRE-018-S1…`, tasks `PRE-018-T01…`,
research decisions `PRE-018-D1…`. Other features are cited by their own IDs: PRE-012 (user preset import,
`specs/008-pre-012-preset-import-validation/`), PRE-013 (bulk import), PRE-014 (export), PRE-015
(duplicates), PRE-016 (overrides), PRE-003 (tags), PRE-006 (recently played), PRE-007 (collections),
MED-013 (media relinking, `specs/146-med-013-media-relinking/`), ACC-004 (announcer).

## What already exists (audit of HEAD `4157fa8f`, 2026-11-14)

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| User presets (PRE-012/013/015) | `UserPresetLibrary` (actor) over `UserPresetStore`: `index.json` records (`user/<uuid>` IDs, SHA-256, git blob hash, byte count, state pending/playable/quarantined, warnings) plus `files/<sha256>.milk` and `quarantine/<sha256>.milk`. `data(for:)` returns nil when a playable preset's file is missing or has the wrong size, so the preset silently fails to load. | `UserPresetLibrary.swift`, `UserPresetStore.swift` | Nothing tells the user a stored file is gone, and nothing restores it. |
| Static checks | `MilkdropPresetValidator.validate(bytes, knownTextures:)` gives a quarantine reason or warnings, including `missingTexture` (a `sampler_<name>` that is neither an engine texture nor one of the app's bundled textures). Run once at import, duplicate and edit. | `MilkdropPresetValidator.swift` | Never re-run on stored presets, so a preset stored before a limit was tightened (or a texture list that changed) is never re-judged. |
| Textures | The app bundles the packs' texture images (`PresetTextures/`, built by `scripts/build_preset_index.py`) and gives the engine that one search path. Users cannot import textures: PRE-012 and PRE-013 import `.milk` text only. A missing texture draws as a blank texture. | `AppCoordinator.swift` (`setTextureSearchPaths`), `UserPresetsCoordinator.textureNames` | No list of user presets whose look depends on a texture the app does not have. |
| References by preset ID | Favorites (`favorites` key, `FavoritesStore`), tags (`PresetCollections/tags.json`, PRE-003), overrides (`overrides.json`, PRE-016), collections (`collections.json`, PRE-007), recently played (`recentPresets` key, PRE-006). Removing a user preset prunes its tags and overrides only; favorites are pruned at launch (`PresetCoordinator.attach`) except for user presets that are waiting; collections and recents keep any ID. | `UserPresetsCoordinator.remove`, `PresetCoordinator.attach` | Dangling IDs in collections and recents (and in tags, overrides or favorites after a restore, a crash between two saves, or an older version) are never found or cleaned. |
| Relinking | MED-013 relinks missing media by checksum (content-addressed payloads) or by a user-picked replacement, and reports on the library lane. | `MediaRelinkService`, `MissingMediaView` | The pattern to follow for missing user preset files: the record keeps the SHA-256, so a picked file (or a bundled original) with the same checksum restores it exactly. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing delegation (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: What does "the user library" cover? → A: Everything the user made: imported and duplicated presets
  (all states) and the five per-preset-ID stores (favorites, tags, overrides, collections, recently
  played). The bundled library is not scanned for textures: it ships checked (load sweep, feature 002)
  and its textures ship with it. Applied in R1, R2.
- Q: Which issue kinds are reported? → A: Four: **missing texture** (preset, texture name), **dangling
  reference** (store, preset ID, and the collection for a collection entry), **missing file** (a waiting
  or playable preset whose stored file is absent, or present with another size or checksum), and
  **unparsable** (a waiting or playable preset whose stored text now fails the static checks and is not
  quarantined). Applied in R3.
- Q: Can the user import a texture? → A: No. The app has no user textures, and this feature does not add
  them (it would need a texture store, a search path per preset and licence handling). The suggestion
  says so plainly: the preset draws a blank texture instead; the user may keep it as it is, move it to
  Quarantine, or remove it. Applied in R6.
- Q: What is "relink" for a missing file? → A: MED-013's checksum pattern. "Re-import…" opens the Files
  picker; the picked file is accepted only when its SHA-256 and size equal the record's, and then the
  stored copy is written back exactly; the preset keeps its ID, name, state, favorites, tags,
  collections and overrides. When the preset is an unedited copy of a bundled preset (its SHA-256 equals
  the copy-time checksum) and that bundled preset still exists, "Restore from Library" does the same
  with the bundled bytes, with no picker. A file with another checksum is refused with a sentence. Applied
  in R7.
- Q: What does "Fix All Safe" do? → A: It removes dangling references only (every store), and nothing
  else. Missing textures, missing files and unparsable presets need the user's own choice and stay
  reported. Applied in R9.
- Q: Which actions need a confirmation? → A: Remove Preset (deletes the record and any stored copy) and
  Move to Quarantine (the preset stops playing, and Quarantine can only delete). Removing a dangling
  reference needs none: the ID names nothing. Re-import and Restore write only bytes whose checksum
  the record already names. Applied in R8, R10.
- Q: Where is the check in the app? → A: My Presets → "Check Library" (a row below Quarantine), which
  opens the Library Check screen: a "Check Library" button, the issues grouped by kind, a fix button on
  each issue, and "Fix All Safe". Results and each fix are announced on the announcer's library lane
  (ACC-004). Applied in R11, R12.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Does the check run by itself? → A: No. It runs only when the user taps Check Library (and again
  after each fix, R13); opening the screen shows "Not checked yet." Nothing runs at launch or in the
  background. Applied in R11.
- Q: How is a damaged stored file told apart from a missing one? → A: It is not a separate kind. The
  missing-file check compares the stored file's size and SHA-256 with the record; absent, unreadable or
  different is one "missing or damaged file" issue with the same fixes. Applied in R3, R7.
- Q: What reason does a preset moved to Quarantine by this screen carry? → A: A new quarantine reason
  "movedByUser" ("You moved this preset to Quarantine.") whose detail is the issue (the unparsable
  reason, or "uses missing texture X"). A record with this code read by an older app version shows the
  generic "This preset could not be used." Applied in R6, R8.
- Q: Does Move to Quarantine also prune the preset's references? → A: No. The record still exists, so
  its favorites, tags, overrides and collection entries are not dangling, and Remove Preset in
  Quarantine later prunes tags and overrides as today. Remove Preset from this screen prunes tags and
  overrides like My Presets' Remove (PRE-003-R7, PRE-016-R16). Applied in R8, R10.
- Q: How do issues read for VoiceOver? → A: Each issue is one accessibility element ("<kind>: <preset or
  ID>. <suggestion>") whose fixes are also named accessibility actions; the screen's result line is
  announced on the library lane. Applied in R11, R12.

### Session 2026-11-14 (speckit-analyze)

- Finding (coverage, Edge Cases): the newer-format user preset list had no test; added to PRE-018-T07.
- Finding (coverage, Edge Cases): "button disabled until loaded / while running" had no task; added to
  PRE-018-T10.
- No constitution conflict, no duplicate requirement; every R and S maps to at least one task.
 *(mandatory)*

### User Story 1 - I find out what is broken in my library and how to fix it (Priority: P1) — MVP

A user with imported presets opens My Presets → Check Library and taps Check Library. The scan runs
without blocking the screen and lists each problem once, grouped by kind, each with a plain sentence
and a fix: "Remove from Favorites" for a favorite that names a deleted preset, "Re-import…" for a preset
whose file was lost, "Move to Quarantine" for one that no longer passes the checks, and an explanation
for one that uses a texture the app does not have.

**Why this priority**: it is the roadmap row's acceptance: a broken library is reported with an
actionable relink suggestion.

**Independent Test**: seed a library with one issue of each kind; one scan reports each exactly once
with the right kind and suggestion; a clean library reports none.

**Acceptance Scenarios**:

1. **Given** a library with a preset that uses a texture the app lacks, a dangling favorite, tag,
   override, collection entry and recent entry, a preset whose file is missing, and a stored preset that
   fails the static checks, **When** the user checks the library, **Then** exactly those 8 issues are
   listed, each with its kind and suggestion.
2. **Given** a library with no problems, **When** the user checks it, **Then** "No problems found." is
   shown and announced.

### User Story 2 - I fix the safe problems in one tap (Priority: P1)

The user taps Fix All Safe. Every dangling reference is removed from its store; the user's presets,
files and the other issues are untouched. A new scan finds no dangling references; the missing texture,
missing file and unparsable preset are still listed.

**Acceptance Scenarios**:

1. **Given** the broken library above, **When** the user taps Fix All Safe, **Then** the 5 dangling
   references are removed, the result is announced ("Removed 5 broken references."), and a rescan lists
   only the 3 issues that need the user's choice.
2. **Given** one dangling collection entry, **When** the user taps its "Remove from Collection" button,
   **Then** only that entry is removed.

### User Story 3 - I relink a lost preset file by checksum (Priority: P2)

The user picks the original `.milk` file for a preset whose file is missing; the app checks that its
checksum matches and restores it; the preset plays again with its favorites, tags and adjustments. A
file with other content is refused. A lost copy of a bundled preset is restored from the library
without a picker.

**Acceptance Scenarios**:

1. **Given** a playable preset whose stored file is missing, **When** the user re-imports a file with the
   same checksum, **Then** the stored copy is restored byte for byte and the issue is gone on rescan.
2. **Given** the same, **When** the user picks a different file, **Then** nothing is written and the
   sentence says the file is not the same preset.

### Edge Cases

- The saved user preset list is from a newer app version: the scan reports nothing about user presets
  and says that My Presets is unavailable; references are still checked against the bundled library only
  when user presets can be read (otherwise user preset IDs are not judged dangling).
- A preset is waiting for the full-library unlock (PRE-015-R8): its references are not dangling; its file
  is checked like any other.
- A quarantined preset: its references are not dangling (the record exists); its file and text are not
  checked (it never plays).
- A preset ID that names a bundled preset in a locked pack: not dangling.
- The library is not loaded yet: the button is disabled until it is.
- Very large stores: the scan stops at its bounds and says the check was incomplete.
- A store refuses the change (newer format, save failed): the fix reports the store's message and the
  issue stays.
- A scan or fix is already running: the buttons are disabled; a second scan never overlaps.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-018-R1**: The app MUST offer a check of the user library that reads the user preset records and
  their stored files, and the favorites, tags, overrides, collections and recently played lists.
- **PRE-018-R2**: The check MUST run off the main thread and MUST NOT change anything it reads.
- **PRE-018-R3**: The check MUST report four issue kinds: missing texture (preset ID, texture name),
  dangling reference (store, preset ID, collection when the store is collections), missing file (preset
  ID), unparsable (preset ID, the reason the static checks give).
- **PRE-018-R4**: A reference MUST be judged dangling only when its preset ID names neither a bundled
  preset nor any stored user preset record (any state).
- **PRE-018-R5**: Each issue MUST be reported exactly once per scan, in a stable order (kind, then
  preset name or ID, then detail).
- **PRE-018-R6**: A missing texture issue MUST say that the app cannot import textures and draws a blank
  texture instead, and offer Move to Quarantine and Remove Preset; it stays reported until the user acts.
- **PRE-018-R7**: A missing file issue MUST offer Re-import… (a picked file accepted only when its
  SHA-256 and size equal the record's; the stored copy is then written back and nothing else changes),
  Restore from Library when the preset is an unedited copy of a bundled preset that still exists, and
  Remove Preset; it stays reported until one succeeds.
- **PRE-018-R8**: An unparsable issue MUST offer Move to Quarantine and Remove Preset. Move to Quarantine
  records the reason "movedByUser" with the issue as its detail and prunes no reference; Remove Preset
  prunes the preset's tags and overrides as My Presets' Remove does.
- **PRE-018-R9**: A dangling reference issue MUST offer the removal from its store ("Remove from
  Favorites", "Remove Tag Entries", "Remove Adjustments", "Remove from Collection", "Remove from Recently
  Played"). "Fix All Safe" MUST apply exactly these removals and nothing else.
- **PRE-018-R10**: Remove Preset and Move to Quarantine MUST ask for confirmation first; no user preset
  file is ever deleted without it.
- **PRE-018-R11**: My Presets MUST offer "Check Library", opening a screen ("Not checked yet." until the
  first scan; no scan runs by itself) with a Check Library button,
  the issues grouped by kind with a fix button on each, Fix All Safe (shown when a dangling reference is
  listed), and the result of the last scan or fix. Each issue is one accessibility element whose fixes
  are also named accessibility actions.
- **PRE-018-R12**: The result of every scan and fix MUST be announced on the announcer's library lane.
- **PRE-018-R13**: After a fix the app MUST rescan, so the list shows what remains.
- **PRE-018-R14**: The scan MUST be bounded: at most 1,200 user preset records and 128 MiB of preset text
  read, 60,000 references read, 500 issues listed, 8 missing textures per preset; past a bound it stops
  that part and says the check was incomplete.
- **PRE-018-R15**: No new UserDefaults key, file or network use; nothing about the scan is stored.

### Key Entities

- **Integrity issue**: kind, preset ID, preset name (when a record exists), detail (texture name, store,
  collection name, reason), suggestion sentence, offered actions.
- **Reference snapshot**: favorites IDs, tagged preset IDs, preset IDs with overrides, collections (ID,
  name, preset IDs), recent IDs — copied at scan time.
- **Integrity report**: issues, counts of presets and references read, incomplete flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-018-S1**: For the broken fixture library (one issue of each kind and each reference store), the
  scan reports each issue exactly once with the right kind and suggestion (acceptance test).
- **PRE-018-S2**: After Fix All Safe, a rescan reports 0 dangling references, and the missing texture,
  missing file and unparsable issues are still reported (acceptance test).
- **PRE-018-S3**: A clean library gives 0 issues (unit test).
- **PRE-018-S4**: Bounds hold: a library beyond each bound stops at it and marks the report incomplete
  (unit test).
- **PRE-018-S5**: Re-import with the matching file restores the file byte for byte; a different file
  changes nothing (unit test).
- **PRE-018-S6**: On a DEBUG broken seed, a user runs the check and sees the issues in under 30 s of
  UI-test time.

## Assumptions

- Textures: only the engine's own names and the bundled `PresetTextures` names exist; user textures are
  out of scope.
- Simulator results are not device evidence; the feature changes no capture, render or performance path.
- Favorites, tags, overrides, collections and recents keep their current file formats.
