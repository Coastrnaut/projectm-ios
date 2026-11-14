# Feature Specification: FILE-011 Local Data Erase

**Feature Branch**: `feature/file-011` (spec directory `120-file-011-local-data-erase`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (FILE-011-T01-T12 verified on the Mac Studio: LibraryBackup package tests on the host, app unit tests and UI tests on an own iOS 27.2 simulator; the Linux job is left to CI). ADR-0048.

**speckit-analyze (2026-11-14)**: 0 critical, 0 high; every requirement and success criterion maps to a task (R1 T08/T09, R2 T09/T11, R3 T04/T08, R4 T01/T03/T05, R5 T01/T05, R6 T03/T06, R7 T10, R8 T07, R9 T02, R10 T09, R11 T12; S1 T05, S2 T06, S3 T07, S4 T07, S5 T11). Fixes applied: R8 named in T07; R7 (stores load empty after an erase) and the pending-restore exclusion get app tests in T10.

**Input**: User description: "Implement FILE-011 (Local data erase) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide explicit confirmation to
erase user-created scenes and mappings." Acceptance, verbatim: "Erase deletes selected data and leaves
bundled assets untouched." P1, M, depends on FILE-005 (integrated). Verification: schema and fixture
tests plus the simulator."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `FILE-011-R1…`, success criteria `FILE-011-S1…`, tasks `FILE-011-T01…`.

## Baseline: what the user created, and what is bundled (audit of 2026-11-14, commit `897bf1ba`)

The row's gap status is "Gap candidate". The audit confirms a gap: single records can be deleted one at
a time (a scene, a preset, a collection, the photo, the video, an audio track) and FILE-010 clears
caches, but nothing erases the user's data as a whole, and "mappings" (MOD-002 bindings, which live
inside scenes, and the OSC port) cannot be reset at all. FILE-005's inventory (`LibraryFolders`,
`LibrarySettingsPolicy`, `LibraryRecords`) already lists every user record; FILE-008 keeps photos and
videos content-addressed with a reference registry; FILE-009 measures each folder.

| Data | Where it lives | Erase category |
|---|---|---|
| The show, its stored scenes (layers, MOD-002 bindings), the current scene and its recovery copies | `Application Support/Show/`, `Application Support/Scenes/` | **Scenes and show** |
| My Presets: imported presets, copies of Included or full-library presets, quarantined texts | `Application Support/UserPresets/` | **My Presets** |
| Collections and favorites | `Application Support/PresetCollections/`, UserDefaults `favorites` | **Collections and favorites** |
| Imported photos and videos, the current photo and video choice, the loop region | `Application Support/Photos/`, `Videos/`; `settings.photo.id`, `settings.video.id`, `settings.video.loop` | **Photos and videos** |
| Imported audio tracks (AUD-001) | `Application Support/AudioLibrary/` | **Imported audio** |
| Visual, audio, camera, OSC and MIDI settings, the text overlay | UserDefaults `settings.*` (listed in FILE-011-R4) | **Settings** |
| The app bundle: built-in presets, the preset packs, the full library archive and its index | the app bundle (read-only) | Never touched |
| The purchase | StoreKit (no stored flag, no receipt file the app writes) | Never touched |
| Caches (Metal shader caches, thumbnails), recordings, shares and exports | `Library/Caches`, `tmp` | Never touched (FILE-010 clears them) |
| Notices, permission explanations, session recovery, guide state | UserDefaults `notice.*`, `permission.*`, `session.*`, `guide.*` | Never touched |
| Reduce flashing and the colour-blind-safe palette | UserDefaults `settings.reduceFlashing`, `settings.visual.colorBlindSafePalette` | Never touched (safety and accessibility) |
| The backup's own work folder (a pending restore) | `Application Support/LibraryRestore/` | Never touched |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which categories can the user choose? → A: Six, each a checkbox in the Erase sheet: Scenes and show; My Presets; Collections and favorites; Photos and videos; Imported audio; Settings. "Select All" checks all six ("everything"). Each row shows how many records it holds and the space it takes (FILE-009's measurement); a category with nothing in it can still be selected (it erases nothing).
- Q: When does an erase take effect? → A: At the next launch, before any store reads the library, exactly like FILE-005's restore. The running app keeps scenes, presets, collections, the autosave and settings in memory and would write them back over files deleted under it; erasing at launch, before any of them load, makes a write-back impossible. The Erase confirmation records a request; Settings › Storage then says "Erase ready. Close projectM-iOS and open it again to finish." with a Cancel Erase button that removes the request and changes nothing else.
- Q: How explicit is the confirmation? → A: Two steps. The Erase sheet's "Erase…" button is enabled only with at least one category checked; it opens a destructive confirmation titled "Erase N categories?" whose message names every chosen category with its count, says that bundled presets, the purchase and caches are kept, and that it cannot be undone except from a backup. Its buttons are "Erase at Next Launch" (destructive, not the default) and "Cancel" (the cancel action). No typed confirmation: the two steps, the named list and the pending state that can still be cancelled are explicit enough, and a text field in an alert is a VoiceOver and Dynamic Type burden.
- Q: Does the flow offer a backup first? → A: Yes. The Erase sheet has "Back Up Library First…" (FILE-005's Back Up Library…), and its footer says that an erase cannot be undone except from a backup.
- Q: What is never touched? → A: The app bundle (built-in presets, packs, the full library), the StoreKit purchase, caches including Metal caches, temporary recordings, shares and exports, notices, permission explanations, session recovery and guide state, Reduce flashing and the colour-blind-safe palette, the restore work folder, and anything outside the app's own container.

### Session 2026-11-14 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rules 4 and 9).

- Q: What does each category's count mean? → A: Scenes and show: stored scenes plus the current scene (0 or 1); My Presets: records in the preset index; Collections and favorites: collections plus favorites; Photos and videos: stored photo and video references; Imported audio: imported tracks; Settings: listed settings that differ from their default (have a stored value). Sizes are the space the category's folders take (FILE-009); settings show no size (FILE-011-R9).
- Q: What happens when the launch-time erase fails without a crash (a file cannot be moved)? → A: Every folder already moved is moved back, the journal and the request are removed, nothing else changes, and Settings › Storage shows "The erase did not finish. Nothing was erased." once; the user can request it again (FILE-011-R6).
- Q: Does erasing scenes also delete photos and videos? → A: Only the references no one else keeps: references named only by the erased scenes (stored and current) are released, unless they are the current photo or video; a payload is deleted when its last reference goes (FILE-008). Photos and videos as a whole are erased only by their own category (FILE-011-R4).
- Q: Can a pending erase be changed? → A: No; while it is pending, Settings › Storage lists the chosen categories with "Cancel Erase", and "Erase Data…" is disabled. Cancel Erase, then choose again (FILE-011-R3).
- Q: Are Metal shader caches cleared by "Select All"? → A: No. Caches hold no user-created data, are rebuilt by the system and are cleared by FILE-010's Clear Caches; leaving them avoids a slow first frame for every preset after an erase (FILE-011-R5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Erase chosen categories (Priority: P1)

A user opens Settings › Storage, taps "Erase Data…", checks "Scenes and show" and "Photos and videos",
reads the counts and sizes, taps "Erase…", reads the confirmation naming both categories and taps
"Erase at Next Launch". After reopening the app, the show and scenes, photos and videos are gone; My
Presets, collections, imported audio and settings are as before; bundled presets still play.

**Why this priority**: It is the row's observable behaviour and its acceptance.

**Independent Test**: A temp sandbox holds every record kind, a fake bundle folder and a purchase
marker. Each category is erased alone, then all six: only the chosen records are gone (FILE-005's
`LibraryRecords` and FILE-003's tree snapshot), unchosen categories and the bundle are byte-for-byte
unchanged.

**Acceptance Scenarios**:

1. **Given** a library with every record kind, **When** the user erases "My Presets", **Then** every user preset and its text are gone and the scenes, collections, favorites, photos, videos, audio and settings are unchanged.
2. **Given** the same library, **When** the user erases all six categories, **Then** the library reads as a fresh library and the bundle folder, the purchase marker and the caches are unchanged.
3. **Given** the Erase sheet with nothing checked, **Then** "Erase…" is disabled.

### User Story 2 - Nothing happens without confirmation (Priority: P1)

A user opens the confirmation and taps Cancel, or cancels a pending erase before reopening the app.
Nothing is erased.

**Independent Test**: Cancel at the confirmation records no request; Cancel Erase removes the request;
the library snapshot is identical afterwards, also across a relaunch.

### User Story 3 - Nothing half-erased (Priority: P1)

The erase fails part-way (a file operation fails, the app is killed). The library is exactly as before,
or exactly the erased one; never a mix.

**Independent Test**: A fault at every file operation of an erase leaves the snapshot equal to the one
before; a kill after the commit point is completed at the next launch; a kill before it is rolled back
and the still-pending request runs again.

### User Story 4 - References stay consistent (Priority: P2)

Erasing photos and videos while scenes name them leaves those scenes showing the existing "no longer
stored" notice. Erasing scenes releases the photo and video references only those scenes kept, so their
payloads do not linger, while the current photo and video stay.

**Independent Test**: A scene names photo A (also the current photo) and photo B (scene only). Erasing
scenes keeps A and removes B's reference and payload. Erasing photos and videos instead leaves the scene
naming A and B, which no longer resolve.

### User Story 5 - Told what happened (Priority: P2)

After the launch-time erase, Settings › Storage shows the result once ("Erased: scenes and show, photos
and videos.") and it is announced on the `library` lane.

### Edge Cases

- A restore is pending: Erase Data… is disabled with a note ("Cancel the pending restore first."); while an erase is pending, Restore from Backup… is disabled. If both are found at launch (an older build), the erase runs first, then the restore.
- An erase request from a newer app version (unknown schema or category): ignored and removed; nothing is erased, the result says so.
- Erasing "My Presets" leaves preset identifiers in collections and favorites (when those are not chosen); they read as unavailable presets, as after deleting a preset. The last-played preset is forgotten when it was a user preset.
- Erasing "Collections and favorites" never removes a preset.
- Erasing "Settings" returns each listed setting to its default; Reduce flashing keeps its value.
- The app is killed during the launch-time erase: the next launch rolls it back or forward (FILE-011-R6).
- An empty library: an erase of any category succeeds and erases nothing.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-011-R1**: Settings › Storage offers "Erase Data…", which opens a sheet listing the six categories of the Baseline as checkboxes, each with its record count and size, a "Select All" control, "Back Up Library First…", Cancel and "Erase…" (enabled with at least one category checked).
- **FILE-011-R2**: "Erase…" opens a destructive confirmation that names every chosen category with its count and states what is kept; "Erase at Next Launch" is destructive and not the default; Cancel records nothing.
- **FILE-011-R3**: Confirming records an erase request (the chosen categories); the request takes effect at the next launch before any store reads the library; it can be cancelled until then (Settings › Storage lists the pending categories with "Cancel Erase"; "Erase Data…" is disabled while one is pending); its result is shown once in Settings › Storage and announced on the `library` lane.
- **FILE-011-R4**: Each category erases exactly its data and nothing else:
  - Scenes and show: the `Show` and `Scenes` folders; then the photo and video references named only by the erased stored scenes and the erased current scene, except the current photo and video, are released through FILE-008's registry (payloads without a reference are deleted).
  - My Presets: the `UserPresets` folder; `lastPresetID` when it names a user preset.
  - Collections and favorites: the `PresetCollections` folder and `favorites`.
  - Photos and videos: the `Photos` and `Videos` folders, `settings.photo.id`, `settings.video.id`, `settings.video.loop`.
  - Imported audio: the `AudioLibrary` folder.
  - Settings: FILE-005's included setting keys except favorites, the last preset, the photo choice, Reduce flashing and the colour-blind-safe palette, plus `settings.osc.enabled` and `settings.midi.enabled`.
- **FILE-011-R5**: Never touched by any erase: the app bundle (built-in presets, packs, full library), the StoreKit purchase, `Library/Caches` (Metal caches included), `tmp`, notices, permission explanations, session recovery, guide state, Reduce flashing, the colour-blind-safe palette, the restore work folder, and anything outside the library root.
- **FILE-011-R6**: The erase is all or nothing: the chosen folders are moved aside under a journal, then the journal is marked committed; settings and media references are changed only after the commit point; the moved folders are deleted last. A failure before the commit moves every folder back (byte-for-byte as before), removes the request and reports "The erase did not finish. Nothing was erased."; at the next launch a prepared journal is rolled back (then the still-pending request runs again) and a committed one is completed.
- **FILE-011-R7**: After an erase the app starts as with a fresh library for the erased categories: every store reads its folder as empty, no error is shown, and bundled presets play.
- **FILE-011-R8**: Erasing photos and videos while scenes name them leaves the scenes unchanged; their media reads as "no longer stored" (SCN-003-R9).
- **FILE-011-R9**: Counts and sizes per category come from the library itself (records counted by their stores' readers, as defined in Clarifications; sizes of the category's folders by FILE-009's measurement; settings have no size), measured off the main thread.
- **FILE-011-R10**: The sheet and confirmation use standard rows and text that wraps at accessibility sizes; nothing animates; every control has an accessibility label; VoiceOver reads each category as "<name>, <count> items, <size>" with the Selected trait when chosen.
- **FILE-011-R11**: No networking, no new permission, public APIs only; the privacy policy and the Storage footer say the erase removes data only on this device.

### Key Entities

- **Erase category**: one of the six; its folders and setting keys.
- **Erase request**: the chosen categories, recorded until the next launch.
- **Erase plan**: the folders to move, the setting keys to remove and the media references to release, computed at launch from the request and the library.
- **Erase journal**: the commit point of a running erase.
- **Erase result**: what was erased (or why not), shown once.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-011-S1**: For each of the six categories alone and for all six, an erase of a fixture sandbox removes 100% of that category's records and changes 0 records of the others; the fake bundle folder and purchase marker are byte-for-byte unchanged in every case.
- **FILE-011-S2**: A fault at each file operation of an erase leaves the library snapshot identical every time; an interrupted erase is finished or rolled back at the next launch.
- **FILE-011-S3**: Media references: scene-only references are released after a scenes erase and the current photo is kept; scenes keep naming erased media after a media erase.
- **FILE-011-S4**: No write-back: data written after the request (an autosave tick) is gone after the launch-time erase, and a store loaded afterwards reads empty.
- **FILE-011-S5**: A simulator UI test shows the confirmation naming the categories, Cancel erasing nothing, and an erase of one category across a relaunch, in under 30 seconds.

## Assumptions

- FILE-005's folder inventory, settings policy, records comparison and launch-time hook; FILE-003's tree snapshot; FILE-008's media registry; FILE-009's measurement are the base.
- Every folder of a category lives under one root (Application Support), so moves are renames on one volume.
- Simulator results prove behaviour only, never performance.

## Out of Scope

- Erasing single records (each store already deletes its own), recordings, shares or caches (FILE-010).
- Secure overwrite of freed blocks (iOS file protection and APFS handle freed space).
- Resetting the purchase, notices or system permissions (Settings app).
