# Feature Specification: PRE-007 Preset collections

**Feature Branch**: `feature/pre-007` (spec directory `005-pre-007-preset-collections`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement PRE-007 (Preset collections) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Create named custom collections with manual ordering." Acceptance, verbatim: "Reordering persists and deleting collection preserves presets." Dependencies: none. Honor the repository constitution."

**Roadmap row**: PRE-007, priority P0, effort M, no dependencies
(`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table).

**ID convention**: requirements are `PRE-007-R1…`, success criteria `PRE-007-S1…`, tasks
`PRE-007-T01…`. Identifiers such as FR-065 cite feature 001
(`specs/001-ios-projectm-visualizer/spec.md`); FR-101 and above cite feature 002
(`specs/002-preset-library-unlock/spec.md`).

## What already exists (audit of HEAD, 2026-11-12)

This feature adds only what is missing. The audit read the code and its tests at commit `6d669fc`.

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| Preset identity | Every preset has a stable id, `<source>/<path in source>`; Included ids are unchanged since release 1.0 (FR-104). | `Packages/PresetLibrary/Sources/PresetLibrary/PresetIndex.swift` | None. Collections refer to presets by this id. |
| Lists the user owns | One: Favorites, an unordered set of preset ids shown alphabetically (FR-044, FR-114). | `Apps/projectM-iOS/Coordinators/FavoritesStore.swift`, `PresetTests.swift` | No named lists, no manual order. |
| Navigation scope | Next, Previous and Random walk the members of one scope: Included, a pack, a folder, Favorites, a search or All; playable presets only, wrapping (FR-116-FR-119). | `PresetScope.swift`, `PresetLibrary.members(of:unlocked:favorites:excluded:)`, `PresetCoordinator.swift` | A collection cannot be a scope. |
| Lock state | A preset of a locked pack never plays before purchase; choosing it opens the purchase sheet (FR-106). Locked favorites are listed with a lock (FR-114). | `PresetLibrary.isLocked`, `PresetCoordinator.choose` | Must also hold inside collections. |
| Browser | Home (Included, packs, All A-Z), folders, search, Favorites. | `PresetBrowserView.swift`, `PresetFolderView.swift`, `PresetLibraryUITests.swift` | No collections screens. |
| Persistence | Settings storage only: favorites, last preset, settings, notice (FR-065, FR-123). | `AppSettings.swift`, `docs/privacy-policy.md` | No file of user-created data; no versioned format or migration. |

## Clarifications

### Session 2026-11-12

Answered under the standing delegation (recommended option first; no owner question was needed).

- Q: May two collections have the same name? → A: No. A name is refused when another collection already has it, compared after trimming surrounding white space and ignoring letter case and diacritics ("Chill" equals " chill " and "Chíll"). The collection's own current name is always accepted when renaming. Unique names keep the list, the "add to collection" chooser and VoiceOver unambiguous; the identifier, not the name, is what the scope and later features refer to. (R9)
- Q: What are the limits on name length, number of collections and presets per collection? → A: A name has 1 to 60 characters after trimming (user-perceived characters, so an emoji counts once); line breaks inside a name are replaced by spaces. At most 100 collections; at most 1,000 presets in one collection. With these limits the saved data stays below about 8 MB in the worst case and is typically a few kilobytes; saved data larger than 16 MB is treated as unreadable. (R9, R10, S9)
- Q: In what order do Next and Previous walk a collection used as the scope? → A: In the user's manual order, wrapping at both ends, not alphabetically. Every other scope stays alphabetical (FR-115). Manual order is the point of a collection, and a set list is meant to be played in the order arranged. Random stays uniform over the playable members. (R11, S4)
- Q: How are locked presets handled in a collection? → A: Exactly as locked favorites are (FR-114): they can be added before purchase, are listed in their position with a lock mark and "locked" in the accessibility label, open the purchase sheet when tapped, and are left out of the scope's members, so Next, Previous and Random never reach them and the scope line counts only playable presets. The collection row's count is the number of listed presets, locked ones included. Nothing is removed on a refund. (R13, S3)
- Q: What happens to saved collections the app cannot use: a newer format version, or unreadable data? → A: Newer version: the saved data is not interpreted and not modified; collections show as unavailable with the sentence "These collections were saved by a newer version of the app. Update the app to use them."; create, add, rename, reorder and delete are refused; a stored collection scope falls back. Unreadable data (damaged, not the expected shape, or over the size limit): it is renamed aside once (one set-aside copy is kept; a later one replaces it), the app starts with no collections and shows "Your collections could not be read and were set aside." once. Neither case deletes user data or crashes. (R15, S6)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Make a collection and fill it (Priority: P1)

A person browsing presets wants to keep a set of them together under a name of their own, for
example "Friday set". They create a collection, give it a name, and add presets to it from any
list in the browser (a pack, a folder, search results, Favorites, All). They can open the
collection to see what is in it, remove a preset from it, rename it, or delete it. Deleting a
collection removes only the list: every preset stays in the library, stays a favorite if it was
one, and stays in every other collection.

**Why this priority**: This is the roadmap row's observable behavior ("create named custom
collections") and half of its acceptance check ("deleting collection preserves presets").
Nothing else in the feature is usable without it.

**Independent Test**: Create two collections, add the same preset to both and star it, delete one
collection, and check that the preset is still in the library, still a favorite and still in the
other collection.

**Acceptance Scenarios**:

1. **Given** no collections exist, **When** the user creates a collection named "Friday set",
   **Then** it appears in the list of collections with zero presets.
2. **Given** a collection exists, **When** the user adds a preset to it from any preset list,
   **Then** the preset appears at the end of that collection and the collection's count rises by one.
3. **Given** a preset is already in a collection, **When** the user adds it to the same collection
   again, **Then** the collection is unchanged and the user is told it is already there.
4. **Given** a collection with presets, **When** the user removes one preset from it, **Then** only
   that entry leaves the collection; the preset remains in the library, in Favorites and in other
   collections.
5. **Given** a collection, **When** the user renames it, **Then** the new name is shown everywhere
   and its contents and order are unchanged.
6. **Given** two collections sharing a starred preset, **When** the user deletes one collection
   and confirms, **Then** that collection is gone, the other collection still lists the preset,
   the preset is still a favorite and is still listed in its pack.
7. **Given** the user enters an empty name, a name that is too long, or a name another collection
   already has, **When** they try to save it, **Then** nothing is created or renamed and the
   reason is shown.

---

### User Story 2 - Put things in my own order, and keep it (Priority: P1)

The person arranges the presets inside a collection in the order they want to see them, and
arranges the collections themselves in the order they prefer. The order they set is the order
they see the next time they open the browser and after the app is closed and opened again.

**Why this priority**: "Manual ordering" and "reordering persists" are the other half of the
roadmap row and its acceptance check.

**Independent Test**: Reorder the presets of a collection and the list of collections, close and
reopen the app, and compare both orders with what was set.

**Acceptance Scenarios**:

1. **Given** a collection with presets A, B, C, **When** the user moves C to the first position,
   **Then** the collection shows C, A, B.
2. **Given** collections X, Y, Z, **When** the user moves Z to the first position, **Then** the
   list shows Z, X, Y.
3. **Given** either reordering was done, **When** the app is closed and started again, **Then**
   the same order is shown, with the same names and contents.
4. **Given** a person using VoiceOver or Switch Control, **When** they want to reorder, **Then**
   they can move an item up or down without a drag gesture.
5. **Given** saving a change fails (for example the device storage is full), **When** the user
   reorders, **Then** the previous saved state remains intact on the device, the screen shows the
   state that is actually saved, and the user is told the change was not saved.

---

### User Story 3 - Play a collection (Priority: P2)

The person opens a collection and taps a preset. It plays, and from then on Next and Previous step
through that collection in the order the user arranged, wrapping at both ends, and Random picks
only from it, exactly as Favorites or a folder work today. The scope line under the preset name
shows the collection's name and how many of its presets can play. The choice survives a relaunch.

**Why this priority**: A collection that cannot be played is only a list. It depends on stories 1
and 2.

**Independent Test**: Choose a preset inside a collection, step Next past the end and Previous
past the start, press Random repeatedly, and check every preset shown is a member and Next follows
the manual order.

**Acceptance Scenarios**:

1. **Given** a collection C, A, B, **When** the user chooses A in it, **Then** A plays, the scope
   line shows the collection's name and "3", Next plays B, Next again plays C (wrap), Previous
   plays B.
2. **Given** a collection is the scope, **When** Random is pressed repeatedly, **Then** every pick
   is a member of the collection and never the preset already playing when another member exists.
3. **Given** a collection is the scope, **When** the app is relaunched, **Then** the scope is still
   that collection.
4. **Given** a collection is the scope, **When** the user deletes it, **Then** the playing preset
   keeps playing and the scope falls back to a list that exists (the same fallback as for a stored
   scope that no longer resolves).
5. **Given** a collection is the scope, **When** the user reorders it or removes a preset from it,
   **Then** Next and Previous follow the new contents at once.

---

### User Story 4 - Locked presets stay locked (Priority: P1)

Before buying the full library a person can already organize: a preset from a locked pack can be
put into a collection, where it is listed with a lock, exactly as a locked favorite is. It still
cannot play: tapping it opens the purchase sheet, and Next, Previous and Random skip it. After a
purchase the same entries play; after a refund they are locked again.

**Why this priority**: A collection must never become a way around the purchase (FR-106), and it
must not lose the user's entries when the entitlement changes.

**Independent Test**: With the library locked, put one Included and one locked preset in a
collection; check the locked one shows a lock, opens the purchase sheet when tapped, and is never
reached by Next, Previous or Random; then unlock and check both play.

**Acceptance Scenarios**:

1. **Given** the library is locked and a collection holds an Included preset and a locked preset,
   **When** the user opens it, **Then** both are listed and the locked one is marked locked, in
   words for VoiceOver as well.
2. **Given** that collection, **When** the user taps the locked preset, **Then** the purchase
   sheet opens and the playing preset does not change.
3. **Given** that collection is the scope, **When** Next, Previous or Random is used, **Then** only
   the Included preset is ever played and the scope line counts 1.
4. **Given** the library becomes unlocked, **When** the user opens the collection, **Then** both
   presets play and the order is as it was.

---

### Edge Cases

- **A preset that no longer exists** (excluded by a later blocklist, or a pack changed in an app
  update): its entry stays in the saved data, is not shown, is not counted, is skipped by
  navigation, and reappears in its old position if the preset comes back. Nothing fails.
- **Reordering while some entries are hidden**: hidden entries keep their positions relative to
  the entries around them; the visible entries take exactly the order the user set.
- **A preset that failed to load this session** stays listed in the collection but is skipped by
  Next, Previous and Random for the rest of the session (FR-118).
- **An empty collection** can exist, be renamed, reordered and deleted. It cannot become the scope
  because there is nothing to choose in it.
- **A collection whose every preset is locked or missing**, used as the scope: Next, Previous and
  Random do nothing and nothing fails.
- **Saved data written by a newer version of the app** (after a downgrade or a restore from a
  backup made by a newer version): the data is left exactly as it is, collections are shown as
  unavailable with an explanation, and nothing can be changed until an app version that
  understands it is installed. Nothing is lost.
- **Saved data that cannot be read** (damaged file): the damaged data is set aside, not deleted;
  the app starts with no collections, tells the user once, and keeps working.
- **Saved data from an older format** (once a later version changes the format): it is converted
  on first start, and the original is kept until the converted data was saved successfully.
- **Limits reached** (100 collections, 1,000 presets in one collection, 60 characters in a name):
  the action is refused with the reason; existing data is unchanged.
- **Names**: leading and trailing spaces are ignored; a name that is empty after that is refused.
  Names may contain any characters, including emoji and right-to-left text.
- **Very large text sizes**: names and counts wrap; no control is clipped.
- **The same preset in many collections**: allowed; removing it from one does not affect the
  others.
- **Favorites and collections are independent**: starring or unstarring a preset never changes a
  collection, and the reverse.
- **Purchases**: collections never read or write purchase state; they only ask the library
  whether a preset is locked.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-007-R1**: The user MUST be able to create a collection with a name. A new collection is
  empty and is placed last in the list of collections.
- **PRE-007-R2**: The user MUST be able to rename a collection. Renaming changes nothing else.
- **PRE-007-R3**: The user MUST be able to delete a collection after confirming. Deleting removes
  only that collection: no preset, favorite or other collection is changed, and no bundled preset
  file is touched.
- **PRE-007-R4**: The user MUST be able to add a preset to a collection from every preset list in
  the browser (Included, a pack or folder, All A-Z, search results, Favorites, another collection),
  choosing an existing collection or creating a new one in the same step. The preset is appended
  at the end. A preset appears at most once in a collection; adding it again changes nothing and
  says so.
- **PRE-007-R5**: The user MUST be able to remove a preset from a collection. Only that entry is
  removed.
- **PRE-007-R6**: The user MUST be able to reorder the presets inside a collection by hand, and
  the order shown MUST be exactly the order set.
- **PRE-007-R7**: The user MUST be able to reorder the collections by hand, and the order shown
  MUST be exactly the order set.
- **PRE-007-R8**: Every change (R1-R7) MUST be saved at once and MUST be the state shown after the
  app is relaunched. A change that cannot be saved MUST leave the previously saved data intact,
  MUST NOT be shown as if it were saved, and MUST be reported to the user.
- **PRE-007-R9**: Collection names MUST be validated: surrounding white space is ignored; the name
  MUST have 1 to 60 user-perceived characters; line breaks become spaces; two collections MUST NOT
  have the same name, compared ignoring letter case and diacritics. A refused name MUST state the
  reason.
- **PRE-007-R10**: The number of collections and the number of presets in one collection MUST be
  bounded: at most 100 collections and at most 1,000 presets in one collection. Reaching a limit
  refuses the action with the reason.
- **PRE-007-R11**: A collection MUST be usable as a navigation scope: choosing a preset in a
  collection plays it and makes that collection the scope; Next and Previous then step through the
  collection's playable presets in the user's order, wrapping at both ends; Random picks only
  among them and never repeats the playing preset when another exists (the user's order applies
  to Next and Previous only; all other scopes stay alphabetical, FR-115); the scope line shows the
  collection's name and its playable count; the scope is announced like other scope changes
  (FR-116-FR-120, FR-124).
- **PRE-007-R12**: A collection scope MUST survive a relaunch. If the collection no longer exists
  (deleted, or the saved data is unavailable), the scope MUST fall back the way an unresolvable
  stored scope already does, and the playing preset keeps playing.
- **PRE-007-R13**: Lock state MUST hold in collections. A locked preset MAY be added to a
  collection and MUST be listed there marked as locked; choosing it MUST open the purchase sheet
  and MUST NOT play it; it MUST NOT be a member of the collection's scope while locked (FR-106,
  FR-118). A collection row counts its listed presets, locked ones included; the scope line counts
  playable ones. Collections MUST NOT read, write or depend on purchase or entitlement data beyond
  asking whether a preset is locked.
- **PRE-007-R14**: Entries whose preset is not in the current library MUST be kept in the saved
  data, MUST NOT be shown or counted, MUST be skipped by navigation and MUST NOT cause a failure.
  Reordering, adding, removing and renaming MUST NOT discard them.
- **PRE-007-R15**: The saved data MUST carry a format version. Data of the current version MUST be
  read back exactly. Data of an older version MUST be converted by a pure, tested conversion, with
  the original kept until the converted data is saved. Data of a newer, unknown version MUST be
  left untouched, MUST make collections read as unavailable (no create, change or delete), and
  MUST NOT crash or lose data. Data that cannot be read at all (damaged, wrong shape, or larger
  than 16 MB) MUST be set aside, not deleted; one set-aside copy is kept. Both cases MUST be
  explained to the user in a sentence.
- **PRE-007-R16**: Collections MUST be stored only on the device, in the app's own storage, keyed
  by the library's stable preset ids. They contain only what the user entered: names, membership
  and order. No timestamps, play counts or history are stored. Nothing is sent anywhere; no
  network, account, permission or entitlement is added.
- **PRE-007-R17**: Amends FR-065 as amended by FR-123: on-device persistence additionally includes
  the user's preset collections (R16) and, as part of the scope setting, the identifier of a
  collection chosen as scope. The privacy policy's list of stored data MUST say so.
- **PRE-007-R18**: Every new control, row and message MUST have an accessible label; a collection
  row states its name and preset count; a locked entry states that it is locked. Reordering
  (R6, R7) MUST be possible without a drag gesture. Text MUST remain readable at the largest
  accessibility text sizes.
- **PRE-007-R19**: Favorites behavior, the existing scopes, search, the purchase flow and the
  bundled preset files MUST be unchanged.
- **PRE-007-R20**: The collections data and its operations MUST be designed so that later features
  can build on them without a format break where possible: other kinds of user lists and metadata
  (PRE-003 tags, PRE-008 smart collections) can be added in a later format version through the
  conversion path of R15, and the whole of the user's collections can be read as plain logical
  records for export or backup (PRE-014, FILE-005). Those features are not part of this one.

### Key Entities

- **Collection**: a named, user-ordered list of preset references. Has a permanent identifier that
  never changes when it is renamed, a name, and an ordered list of preset ids without duplicates.
- **Collection library**: the user-ordered list of all collections, with the format version. It is
  the unit that is saved and restored.
- **Preset reference**: the library's stable preset id. It may point at a preset that is locked,
  failed this session, or absent from the current library.
- **Collection scope**: a navigation scope naming one collection by its identifier; its members are
  the collection's entries that exist and can play, in the user's order.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-007-S1**: After reordering the presets of a collection and reordering the collections,
  closing the app and starting it again shows both orders exactly as set, in 100% of automated
  runs (roadmap acceptance: "reordering persists").
- **PRE-007-S2**: After deleting a collection, 100% of the presets it listed are still in the
  library, every one that was a favorite is still a favorite, and every other collection has the
  same contents and order as before (roadmap acceptance: "deleting collection preserves presets").
- **PRE-007-S3**: With the library locked, zero locked presets are played through a collection
  across choosing, Next, Previous and 1,000 Random picks.
- **PRE-007-S4**: With a collection as scope, 100% of presets reached by Next, Previous and Random
  are members of it, and a full cycle of Next visits the playable members once each in the user's
  order.
- **PRE-007-S5**: A failed save leaves the previously saved data byte-for-byte unchanged and the
  shown state equal to it.
- **PRE-007-S6**: Saved data of the current format version, kept as a fixed sample, is read back
  with every name, order and entry intact; saved data marked with a newer version is byte-for-byte
  unchanged after the app has run and attempted changes.
- **PRE-007-S7**: A collection with entries for presets that are not in the library shows and
  plays only the existing ones, and after any change the missing entries are still in the saved
  data.
- **PRE-007-S8**: A user can create a collection, add a preset to it and start playing it in under
  30 seconds from the open browser.
- **PRE-007-S9**: With the largest collection allowed (1,000 presets), opening it and saving a reorder each take
  under half a second on the build machine (simulator and host results are not device evidence).
- **PRE-007-S10**: The existing preset, favorites, purchase and browser tests pass unchanged in
  meaning.
- **PRE-007-S11** `{device}`: On D1-D3, collections survive an app update install over the
  previous build, and reordering with VoiceOver works with the described actions. Checked in the
  final device stage; not claimed until then.

## Assumptions

- Collections live in the preset browser of `projectM-iOS`; the harness apps are unchanged.
- A collection holds presets from the bundled library only. Imported and user-authored presets
  (PRE-012, PRE-015) do not exist yet; when they do, they get stable ids of the same shape and need
  no change here.
- Sharing, exporting or importing collections (PRE-014, FILE-005), tags (PRE-003), recently played
  (PRE-006) and smart collections (PRE-008) are separate roadmap rows and out of scope. The
  roadmap's technical hint mentions a document picker; nothing in this row's behavior or
  acceptance needs one, so none is added.
- The collections data is part of the device's normal app-data backup, like the app's settings.
  Deleting the app deletes it.
- One user, one device, one window: no syncing and no concurrent editors.
- Simulator and host tests prove the logic, persistence and screens. They are not device evidence
  (constitution X); device-only checks are tagged `{device}` and left to the final device stage.
