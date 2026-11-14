# Feature Specification: PRE-008 Smart Collections

**Feature Branch**: `feature/pre-008` (spec directory `228-pre-008-smart-collections`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement PRE-008 (Smart collections) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Filter presets by local tags, pack and motion traits."
Acceptance, verbatim: "Rule changes update membership without duplicate entries." P2, depends on PRE-003."

Identifiers in this feature carry the roadmap ID: requirements `PRE-008-R1…`, success criteria `PRE-008-S1…`,
research decisions `PRE-008-D1…`, tasks `PRE-008-T01…`. Other features are cited by their own IDs: PRE-003
(tags), PRE-004 (colour facets), PRE-005 (motion facets), PRE-007 (collections), PRE-012 (user presets), PRE-018
(integrity scanner), FILE-005 (library backup), FILE-011 (erase), SCN-015 (scene lock), ACC-004 (contrast).

## Baseline: what exists today (audit of 2026-11-14, commit `95142688`)

| Question | Today |
|---|---|
| Manual collections | PRE-007 `PresetCollectionStore`: `PresetCollections/collections.json` (schema 1, migration table, newer = unavailable, unreadable = set aside), preset IDs in the user's order; browser home → Collections → one collection; `.collection(id)` scope walks it. |
| Tags | PRE-003 `PresetTagStore` (`PresetCollections/tags.json`) and `PresetTagIndex` (folded tag → listed preset IDs); tag chips filter the browser with AND. |
| Colour and motion | PRE-004 `PresetColorFilter` (families from thumbnails) and PRE-005 `PresetEnergyFilter` (Calm / Moderate / Energetic); chips in memory only, ANDed with tags and Favorites. |
| Pack | Every `IndexedPreset` has `source`: `included`, a pack ID from the build-time index, or `user`. |
| Favorites | `FavoritesStore` (UserDefaults). |
| Rule-based lists | **None.** Chip selections are in memory only and vanish when the browser closes; nothing saves a filter as a named list. |
| Backup | FILE-005 backs up `collections.json`, `tags.json` and `overrides.json` as separate records; FILE-011 erase removes the whole `PresetCollections` folder. |
| Integrity | PRE-018 scans manual collections for dangling preset IDs. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: What is a smart collection? → A: A named rule set: a match mode (All or Any) and a list of conditions. Condition kinds: tag included, tag excluded, pack, motion class, colour family, Favorites. Within one condition the values are alternatives (a preset with any listed value matches); the conditions then combine by the match mode. A collection with no applicable condition lists nothing (never the whole library by accident).
- Q: Where is it stored? → A: In its own versioned file `PresetCollections/smart-collections.json`, beside `collections.json`, `tags.json` and `overrides.json` (the PRE-003 and PRE-016 pattern). The manual collections file keeps its format and version, so no older build can misread or drop a rule set, and PRE-007's golden fixtures and PRE-018's scanner are unchanged.
- Q: Is membership stored? → A: No. It is computed from the current library, tags, favorites, colours and motion classes whenever it is shown or walked, so a rule edit, a new tag or a new favorite updates it at once.
- Q: What does "without duplicate entries" mean? → A: The members are a list of preset IDs with each ID at most once however many conditions it matches, and with at most one preset per content hash (the same preset text present in several packs, or a user copy that is unchanged, appears once: the first in the stable order). Tag values are compared folded (case, accents, width), so "Calm" and "calm" are one condition value.
- Q: In what order? → A: Alphabetical by name across packs, ties broken by preset ID (the library's existing alphabetical order), so the same inputs always give the same list.
- Q: How does it appear in the browser? → A: In the Collections screen, in its own "Smart Collections" section after the manual ones, each row with a "Smart" marker (sparkles symbol, and "smart collection" in the VoiceOver label) and its live count; opening it lists the members and offers Edit Rules. Choosing a member plays it and makes the smart collection the scope (the existing `.collection(id)` scope; smart IDs start with `smart-` so they never collide with manual ones).
- Q: Rules from a newer app version? → A: An unknown condition kind is kept, saved back unchanged, shown as "1 rule from a newer version is not applied", and skipped when matching. A file with a newer schema version makes smart collections unavailable (never interpreted or written), as PRE-007.
- Q: Backup? → A: Yes: FILE-005 carries the file as the record `collections/smart-collections.json`; restore merges per smart collection by ID (a new one is added; a clash follows the restore choice: Replace takes the backup's, Keep both and Skip keep the device's). FILE-011's "Collections, tags, favorites and history" erase removes it with the folder and counts it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save a filter as a smart collection (Priority: P1) — MVP

I create "Calm favourites" with the rules "tag Calm" and "Favorites", match All. The Collections screen shows it
with a Smart marker and its count; opening it lists exactly the presets tagged Calm that I starred, and
Next/Previous walk them.

**Why this priority**: It is the row's observable behavior.

**Independent Test**: A package test builds membership from fixture presets, tags, favorites, colours and motion
classes, and asserts the exact ID list.

**Acceptance Scenarios**:

1. **Given** tagged presets, **When** I create a smart collection with a tag condition, **Then** it lists exactly the presets carrying that tag, alphabetically.
2. **Given** a smart collection, **When** I choose one of its presets, **Then** it plays and Next walks the smart collection's members.
3. **Given** a smart collection, **When** I tag another preset with its tag, **Then** the collection includes it the next time it is shown.

### User Story 2 - Rule changes update membership exactly (Priority: P1)

**Why this priority**: It is the row's acceptance ("Rule changes update membership without duplicate entries").

**Independent Test**: Package tests change rules (add and remove a tag condition, switch Any/All, add a pack) and
assert the exact member list after each change; a preset matching several conditions, and the same text in two
packs, appear once; the order is the same on every evaluation.

**Acceptance Scenarios**:

1. **Given** a smart collection, **When** I add or remove a condition, or switch All/Any, **Then** its members are recomputed at once and match the new rules exactly.
2. **Given** a preset matching several conditions, **When** the collection is listed, **Then** it appears once.
3. **Given** the same preset in two packs, **When** both packs are conditions, **Then** it appears once.

### User Story 3 - Smart collections are kept safely (Priority: P2)

**Independent Test**: Store round trip, migration from an older version through an injected step, newer version
unavailable, unreadable file set aside, unknown condition kind preserved; backup round trip.

**Acceptance Scenarios**:

1. **Given** smart collections, **When** the app relaunches, **Then** they are the same.
2. **Given** a file written by a newer version, **When** the app opens, **Then** smart collections are unavailable and the file is untouched.
3. **Given** a library backup, **When** it is restored on a fresh device, **Then** the smart collections are back.

### Edge Cases

- A rule names a tag, pack, colour or class that no preset has now: that condition matches nothing (the collection may be empty); it is kept, since the tag or pack may come back.
- A pack becomes locked or unavailable: its presets stay members and are shown locked (as manual collections); walking skips locked ones.
- Colour and motion classes come from thumbnails (PRE-004, PRE-005): presets without a picture yet have no colour or class and do not match those conditions.
- Deleting the smart collection that is the current scope falls back to All presets or Included, as PRE-007.
- An exclude-tag condition alone in All mode lists every preset without that tag (a large list is fine; the user chose it).
- Duplicate names are refused on create and rename (case and accents ignored, among smart collections), as PRE-007.
- PRE-018's integrity scanner is unchanged: rules reference tags, packs and classes, not preset IDs, so nothing can dangle.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-008-R1**: A smart collection MUST have a permanent ID (prefix `smart-`), a name (PRE-007 name rules), a match mode (`all` or `any`) and an ordered list of conditions, each a kind and a list of string values.
- **PRE-008-R2**: Condition kinds MUST be: `tag` (the preset carries any listed tag, folded), `notTag` (it carries none of them), `pack` (its source is any listed pack ID, `included` and `user` included), `motion` (its PRE-005 class is any listed class), `color` (its PRE-004 families include any listed family), `favorite` (it is a favorite; no values).
- **PRE-008-R3**: Membership MUST be computed, never stored: the matching listed presets in the library's alphabetical order, each preset ID at most once and at most one preset per non-empty content hash (the first in that order), recomputed whenever rules, tags, favorites, colours, motion classes or the library change.
- **PRE-008-R4**: A collection with no applicable condition MUST list nothing. Unknown condition kinds MUST be skipped when matching, kept unchanged on every save, and reported in the collection's screen.
- **PRE-008-R5**: Smart collections MUST be saved in `PresetCollections/smart-collections.json`: schema version 1, a migration table keyed by version (as PRE-007-R15), a newer version leaving the store unavailable and the file untouched, an unreadable file renamed aside, every change saved atomically before it is shown (a failed save changes nothing).
- **PRE-008-R6**: Limits: at most 100 smart collections, 32 conditions per collection, 64 values per condition, values up to 128 characters; the document is checked with a FILE-007 schema before it is read.
- **PRE-008-R7**: The Collections screen MUST list smart collections in their own section with a "Smart" marker, the live count, and VoiceOver label "<name>, smart collection, <n> presets"; create, edit rules, rename and delete MUST be offered.
- **PRE-008-R8**: The rule editor MUST show the match mode, the conditions as selectable values (tags from the tag vocabulary, packs from the library, the three motion classes, the colour families, Favorites) and the live count for the draft rules before saving.
- **PRE-008-R9**: A smart collection MUST be a scope (the existing `.collection(id)` storage form): choosing a member plays it in that scope, and the scope falls back when the smart collection is deleted.
- **PRE-008-R10**: FILE-005 MUST back up the file as `collections/smart-collections.json` and restore it per smart collection ID by the restore choice; FILE-011's collections erase MUST remove and count it.
- **PRE-008-R11**: The model, matching, file and store MUST be Foundation-only Swift in `PresetLibrary` that builds on Linux.

### Key Entities

- **PresetSmartCollection**: ID, name, match mode, conditions.
- **PresetSmartCondition**: kind (raw string, unknown kinds kept) and values.
- **PresetSmartContext**: the inputs to matching: library, tag index, favorites, colour filter, energy filter.
- **PresetSmartCollectionsFile** / **PresetSmartCollectionStore**: the versioned document and its transactional store.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-008-S1**: Changing a rule (add a tag condition, remove it, switch All/Any, add a pack) gives exactly the expected member list after each change; a preset matching several conditions, a duplicated value, folded tag spellings and the same text in two packs give no duplicate; two evaluations give the same order (package test, Linux-buildable).
- **PRE-008-S2**: Store round trip, injected migration from version 0, newer version unavailable, unreadable set aside, unknown kind preserved through an edit (package test).
- **PRE-008-S3**: Backup round trip restores the smart collections; erase removes the file (LibraryBackup test).
- **PRE-008-S4**: In the app, a smart collection's scope walks its members and follows a tag added later (app unit test on the simulator).
- **PRE-008-S5**: In the app on a simulator, creating a smart collection shows its count, and editing its rules changes the count (UI test under 30 s).

## Assumptions

- No new UserDefaults key: everything lives in the smart collections file.
- Rules use the facets that already exist; free-text search is not a condition (search results are capped at 200).
- Manual and smart collections have separate name spaces; the Smart marker tells them apart.
