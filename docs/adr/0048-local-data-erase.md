# ADR-0048: Local Data Erase by Category, Applied at the Next Launch Under a Journal

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FILE-011 (`specs/120-file-011-local-data-erase`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence-based quality); Privacy
- **Builds on**: ADR-0041 (FILE-005: library inventory, settings policy, records comparison, restore at
  next launch under a journal), ADR-0043 (FILE-008: content-addressed media with a reference
  registry), FILE-003 (tree snapshot), FILE-009 (storage measurement), FILE-010 (cache cleanup)

## Context

The roadmap row asks for an explicit confirmation to erase user-created scenes and mappings, with the
acceptance "Erase deletes selected data and leaves bundled assets untouched." The app's stores
(autosave, scene history, presets, collections, favorites, settings) hold their data in memory and
write it back on change, on backgrounding and on quit, so files deleted under a running app come back.
Several folders and UserDefaults keys must go together, and scenes share stored media by ID.

## Decision

1. **Six categories** (`LibraryErasePolicy`): Scenes and show (`Show`, `Scenes`); My Presets
   (`UserPresets`, plus `lastPresetID` when it names a user preset); Collections and favorites
   (`PresetCollections`, `favorites`); Photos and videos (`Photos`, `Videos`, the photo and video
   choices and the loop region); Imported audio (`AudioLibrary`); Settings (FILE-005's included keys
   minus those owned by other categories, minus Reduce flashing and the colour-blind-safe palette,
   plus OSC on and MIDI on). Select All chooses all six.
2. **Never touched**: the app bundle (built-in presets, packs, the full library), the StoreKit
   purchase, `Library/Caches` (Metal caches included: no user data, rebuilt by the system, cleared by
   FILE-010), `tmp`, notices, permission explanations, session recovery, guide state, Reduce flashing,
   the colour-blind-safe palette and FILE-005's restore folder. The eraser renames only folder names
   from the policy, under the library root.
3. **Confirmation**: a sheet with checkboxes, counts and sizes, and Back Up Library First…; then a
   destructive alert titled "Erase N categories?" naming each category and its count, with "Erase at
   Next Launch" (destructive role) and Cancel (cancel role). No typed confirmation.
4. **At the next launch**: confirming records `LibraryErase/request.json`; the launch hook runs the
   erase before any store loads (and before a pending FILE-005 restore, which it excludes in the UI).
   Nothing in memory can write erased data back. The request can be cancelled until then.
5. **All or nothing**: journal (prepared) → folders renamed into `LibraryErase/trash/` → journal
   (committed) → keys removed, media references released, trash and journal deleted. A failure before
   the commit renames everything back and reports "The erase did not finish. Nothing was erased."; at
   launch a prepared journal is rolled back (the still-pending request then runs again) and a committed
   one finished. An unreadable journal is rolled back.
6. **Media references**: erasing scenes (without photos and videos) releases, through FILE-008's
   registry, the photo and video IDs named only by the erased stored and current scenes, except the
   current photo and video; a payload goes with its last reference. Erasing photos and videos leaves
   scenes unchanged; they show the existing "no longer stored" notice.
7. **Result**: shown once in Settings › Storage ("Erased: scenes and show, photos and videos.") and
   announced on the `library` lane.

## Consequences

- An erase needs a relaunch to take effect, as a restore does; the pending state says so.
- Erasing My Presets leaves their identifiers in collections and favorites when those are kept; they
  read as unavailable presets, as after deleting a preset.
- Freed space is not overwritten; iOS data protection and APFS handle freed blocks.
- Evidence: package tests per category with records and tree snapshots, a fault at every file
  operation, recovery, references, no write-back; app tests; one simulator UI test.
