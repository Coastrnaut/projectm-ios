# Feature Specification: PRE-003 Preset Tags

**Feature Branch**: `feature/pre-003` (spec directory `149-pre-003-preset-tags`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (PRE-003-T01-T18 verified on the Mac: host package tests and the
feature's own iOS 27.2 simulator "PRE3"; no device claim). PresetLibrary 275 tests (16 new), LibraryBackup
72 (4 new), projectM-iOSTests 699 (PresetTagAcceptanceTests 4), PresetTagsUITests 2 (each under 30 s
warm). Linux: not run here; CI's Linux job builds and tests PresetLibrary and LibraryBackup.

**Input**: Roadmap row PRE-003 (P1, size M, no dependencies). Observable behavior, verbatim: "Assign
local searchable tags to presets without editing bundled assets." Acceptance, verbatim: "Tag filter
returns correct IDs after app relaunch."

Identifiers carry the roadmap ID: requirements `PRE-003-R1…`, success criteria `PRE-003-S1…`, tasks
`PRE-003-T01…`. Other features are cited by their own IDs: feature 002 (the preset library, FR-111 to
FR-124), PRE-007 (collections), PRE-012/PRE-015 (user presets), PRE-001/PRE-002 (thumbnails), SCN-005
(scene tags), FILE-005 (library backup), FILE-009 (storage usage), FILE-011 (erase), ACC-004 and
ACC-011 (announcements).

## Baseline: what exists today (audit of 2026-11-14, commit `4bad23aa`)

The audit confirms the gap: presets have no tags or labels.

| Area | Today |
|---|---|
| Library | `PresetLibrary` (Foundation only, Linux-tested): 12,847 bundled presets from `PresetIndex.json` plus the user's presets; home tree, scopes (`PresetScope`), search over name and author (case- and accent-folded substring, grouped by pack, capped at 200). Bundled files are read-only resources. |
| Favorites | `FavoritesStore`: UserDefaults key `favorites` (preset IDs). The browser's All/Favorites picker lists favorites across packs, locked ones marked. |
| Collections (PRE-007) | `PresetCollectionStore`: one versioned file `Application Support/PresetCollections/collections.json`, atomic writes, bounded schema check (FILE-007), newer format read-only, unreadable file set aside; IDs it cannot resolve are kept. |
| User presets (PRE-012/015) | `Application Support/UserPresets/`; source `user`; removal through `UserPresetsCoordinator.remove`. |
| Thumbnails (PRE-001/002) | A cache keyed by preset ID and hash; not affected by this row. |
| Scene tags (SCN-005) | `SceneTagMap` in ShowControl: tags 1–40 characters, folded on case, accents and width, ≤ 16 per scene, ≤ 256 distinct, derived vocabulary, AND chips in the switcher, search matches tags, Tags sheet with suggestions, library-lane announcements. |
| Backup and erase | FILE-005 backs up `collections.json` as a record (`collections/collections.json`); restore stages a copy of the whole `PresetCollections` folder. FILE-011's "Collections and favorites" category deletes the whole `PresetCollections` folder and the `favorites` key. FILE-009 measures that folder under Presets. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the
conservative, local-first option.

- Q: Where are preset tags kept? → A: In one versioned file, `Application Support/PresetCollections/tags.json`, beside PRE-007's collections, mapping a preset ID to its tags. Bundled assets (`PresetIndex.json`, `PresetPacks.json`, the preset archive and Included files) are never written. The same folder means FILE-009 measures tags with collections, FILE-010 never cleans them, the UI-test reset clears them, and FILE-011 erases them with collections. No UserDefaults key is added.
- Q: Which tag rules apply? → A: SCN-005's exactly: trimmed text of 1 to 40 characters on one line; equal when equal ignoring case, accents and width; a preset carries each tag once; at most 16 tags per preset and 256 distinct tags; the display case is kept and adding a tag that already exists uses the existing spelling; tags sorted by folded text, then display text.
- Q: How many presets can carry tags? → A: At most 20,000 tagged presets (the bundled library plus the 1,000 user presets fits), and the file at most 4 MiB. Over the limit an addition is refused with a message.
- Q: What happens to damaged stored data? → A: Lenient: entries that break a rule (an invalid tag, a duplicate, a 17th tag, a 257th distinct tag, an empty ID, a non-list value) are dropped and counted as a warning; the rest load. A file that is not readable at all (not JSON or over the bounds) is renamed aside (`tags.unreadable.json`, one copy) and the user is told once; a file from a newer app version is never interpreted or overwritten and tagging is unavailable until the app is updated (as PRE-007).
- Q: Which presets carry tags that are shown? → A: Tags are kept by preset ID. Presets of locked packs are still in the library (listed with a lock) and keep, show and filter by their tags. IDs the library does not list now (a user preset waiting for its check, a preset dropped by a future index) are kept but hidden: they do not appear in results or chip counts, and the vocabulary is derived from listed presets only. When the user removes one of their own presets (PRE-012 Remove), its tags are pruned.
- Q: Where does the user filter? → A: In the preset browser: a row of tag chips under the All/Favorites picker when any listed preset has tags. Selecting chips (AND) replaces the home with "Tagged" results: every listed preset carrying all selected tags, alphabetical across packs, locked ones marked; with Favorites selected, only favorites among them. Chips are kept in memory while the app runs (as SCN-005); no settings key.
- Q: Does search match tags? → A: Yes: the search text matches name, author or any tag of the preset (folded substring), with feature 002's grouping and cap; selected chips narrow search results too.
- Q: What does choosing a preset from tag results do? → A: The tag results become the scope (FR-116), titled "Tagged: Calm, Slow"; Next, Previous and Random walk the playable presets carrying every selected tag, alphabetical. Like a search scope it is stored as All (FR-119), so after a relaunch the scope is All (or Included before purchase).
- Q: Where are tags edited? → A: A "Tags…" action on every preset row (context menu and the VoiceOver action "Tags") opens a Tags sheet for that preset: its tags with Remove, a field with Add (Return adds) and suggestions from the other presets' tags. Changes save at once, never load a preset and announce on the library lane.
- Q: Do backups carry tags? → A: Yes. FILE-005 backups hold the tags as their own record (`collections/tags.json`); restore merges them per preset by the restore choice (Keep both = union up to 16, Replace = the backup's tags, Skip = the device's); tags of a user preset restored as a copy follow the copy's new ID. FILE-011's erase of "Collections, tags and favorites" removes them.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Is the chip row also shown while searching and in Favorites? → A: Yes: the chip row stays at the top of the list in the home, in Favorites and in search results, so the filter that narrows the list is always visible and can be cleared where it applies.
- Q: Does a preset row show its tags visually, not only to VoiceOver? → A: Yes: a row with tags adds a caption line listing them ("Calm · Slow") under the author line; rows without tags are unchanged, so existing layouts and tests are untouched.
- Q: Do tag edits have undo, or a show-wide rename? → A: No (as SCN-005): a tag is removed in the preset's Tags sheet and disappears when no listed preset carries it. Rename and bulk tagging can come later.
- Q: How are the browser's chips cleared? → A: Tapping a selected chip deselects it; a "Clear" chip at the end of the row (shown while any chip is selected) deselects all. Selection survives closing the browser while the app runs.
- Q: Is the tag scope's member list alphabetical or by tag order? → A: Alphabetical across packs (feature 002 FR-115's order for cross-pack lists such as Favorites), playable only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I tag presets and filter by tag, and it survives a relaunch (Priority: P1) — MVP

A VJ tags three presets "Calm" and one of them also "Slow". In the browser they tap the "Calm" chip:
exactly those three presets are listed. They add "Slow": only the one. After closing and reopening the
app, the same chips give exactly the same presets, with no network.

**Why this priority**: It is the row's behaviour and acceptance.

**Independent Test**: Tag presets through the tag store, filter by tags (the expected preset ID set),
recreate the store from disk and filter again: the same IDs. The same flow as a UI test with a relaunch.

**Acceptance Scenarios**:

1. **Given** presets A, B, C tagged "Calm" and C tagged "Slow", **When** the "Calm" chip is selected, **Then** exactly A, B and C are listed.
2. **Given** that, **When** "Slow" is also selected, **Then** exactly C is listed.
3. **Given** those tags, **When** the app is relaunched (store read again from disk), **Then** the same chips give the same IDs.
4. **Given** a preset tagged "Ambient", **When** the user searches "amb", **Then** that preset is in the results.

---

### User Story 2 - I tag a preset from its row (Priority: P1)

**Independent Test**: The Tags sheet adds and removes tags, suggests existing tags and refuses invalid ones.

**Acceptance Scenarios**:

1. **Given** a preset row, **When** the user chooses "Tags…", types "Calm" and Return, **Then** the preset carries "Calm", the chip row shows "Calm" and VoiceOver announces "Tagged <name> Calm."
2. **Given** another preset carries "Calm", **When** the sheet opens, **Then** "Calm" is a suggestion; tapping it adds it.
3. **Given** a preset tagged "Calm", **When** "  CALM " is added, **Then** it is refused as already present and nothing changes.

---

### User Story 3 - Tags are safe: bundled files untouched, backups, erase, damage (Priority: P2)

**Independent Test**: Hash bundled index files before and after tagging; back up and restore tags; erase
removes them; damaged files load leniently.

**Acceptance Scenarios**:

1. **Given** tags are added and removed, **When** the bundled index and pack files are hashed, **Then** the hashes are unchanged.
2. **Given** tags, **When** the library is backed up and restored onto an empty library, **Then** the tags are the same.
3. **Given** tags, **When** the Collections category is erased, **Then** no tags remain.
4. **Given** a tag file with invalid entries, **When** it is read, **Then** valid entries load and the dropped ones are counted.

### Edge Cases

- A selected chip whose tag no listed preset carries any more is dropped from the selection.
- With chips selected and nothing matching (e.g. Favorites with no tagged favorite), the list says "No presets have all these tags".
- A tag change that cannot be saved changes nothing and shows "Your tags could not be saved." (as PRE-007-R8).
- A 17th tag, a 41-character tag or a 257th distinct tag is refused with a message and nothing changes.
- Locked presets listed in tag results open the purchase sheet when chosen (FR-106) and never play from the tag scope.
- A preset that failed to load this session is listed but skipped by Next, Previous and Random (FR-118).

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-003-R1**: Any preset in the library (bundled, locked or the user's) can carry tags, kept by preset ID in the app's local data. Bundled assets are never written.
- **PRE-003-R2**: A tag is trimmed, 1 to 40 characters on one line (no control characters); two tags are the same when equal ignoring case, accents and width; a preset carries each tag at most once; at most 16 tags per preset, 256 distinct tags and 20,000 tagged presets; the display case is kept and adding an existing tag (folded) uses the existing spelling.
- **PRE-003-R3**: The vocabulary is derived from the tags of listed presets and sorted by folded text, then display text.
- **PRE-003-R4**: The user can add and remove a preset's tags; refused changes (invalid, already present, not present, over a limit, newer format, failed save) change nothing and say why.
- **PRE-003-R5**: Tags are saved in one versioned, bounded file, replaced atomically on every change; every change is saved before it is shown.
- **PRE-003-R6**: Reading is lenient: entries breaking a rule are dropped and counted; an unreadable file is set aside (one copy) with a one-time notice; a newer-format file is kept untouched and tagging is unavailable with a message.
- **PRE-003-R7**: Tags of IDs the library does not list are kept and hidden; removing a user preset prunes its tags.
- **PRE-003-R8**: The browser shows a chip row of the vocabulary under the All/Favorites picker; selected chips combine with AND and replace the home with the tagged presets (alphabetical across packs, locked marked), narrowed to favorites when Favorites is selected; selection is in memory only. The chip row is shown in the home, in Favorites and in search results; tapping a selected chip deselects it and a "Clear" chip deselects all. A row with tags shows them in a caption line.
- **PRE-003-R9**: Search matches name, author or any tag (folded substring); selected chips narrow the search results.
- **PRE-003-R10**: Choosing a preset from tag results makes "Tagged: <tags>" the scope; Next, Previous and Random walk its playable presets alphabetically; the scope is stored as All.
- **PRE-003-R11**: Every preset row offers "Tags…" (context menu) and the VoiceOver action "Tags", opening a Tags sheet with the preset's tags (Remove button and VoiceOver action), a field with Add and suggestions from the vocabulary narrowed by the field's text.
- **PRE-003-R12**: Tag additions, removals and refusals are announced through the shared announcer's library lane; a chip change announces the result count on the search lane. Each chip has a label, the Selected trait when selected and a value with its preset count; a row's VoiceOver label adds ", tags Calm, Slow" when it has tags.
- **PRE-003-R13**: FILE-005 backups carry the tags as their own record; restore merges per preset by the restore choice; tags of a user preset restored as a copy follow its new ID. FILE-011 erases them with collections and favorites (the category is named "Collections, tags and favorites").
- **PRE-003-R14**: Filtering by tags over the full library uses a precomputed index (tag → preset IDs), so the cost does not grow with the library's size for each chip change beyond the matching set.
- **PRE-003-R15**: No networking, no new settings keys; the PresetLibrary package keeps building and testing on Linux.

### Key Entities

- **Preset tag**: a short display string; identity is its folded form.
- **Preset tag map**: preset ID → sorted tags (stored).
- **Tag index**: folded tag → set of preset IDs, built from the map for the listed presets (in memory).
- **Tag filter**: the browser's selected tags (in memory), combined with AND.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-003-S1**: The tag filter returns exactly the expected preset IDs before and after the store is recreated from disk (acceptance test) and after an app relaunch (UI test under 30 s).
- **PRE-003-S2**: Bundled index and pack files have identical hashes before and after tagging.
- **PRE-003-S3**: 100% of invalid, duplicate and over-limit tags in the tests are refused (editing) or dropped and counted (reading).
- **PRE-003-S4**: A backup round trip preserves every tag; an erase leaves none.
- **PRE-003-S5**: Filtering the full 12,847-preset library by two tags touches only the matching presets' entries (measured by an operation count in a test, no wall-clock assertion) and feels instant.

## Assumptions

- Tag results include locked presets (marked), like the Favorites listing (FR-114).
- Simulator and Mac results are not device evidence; this row needs no device-only check.
- Show-wide tag rename and bulk tagging are out of scope (as SCN-005).
