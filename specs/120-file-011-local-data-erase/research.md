# Research: FILE-011 Local Data Erase

## FILE-011-D1: When the erase happens

**Decision**: At the next launch, in the hook FILE-005 uses, before any store reads the library; erase
first, then a pending restore. **Rationale**: the scene autosave (SCN-002), scene history, the preset,
collection and favorites stores, and `AppSettings` hold state in memory and write it on change, on
backgrounding and on quit; deleting under them would be undone. At launch nothing has loaded.
**Alternatives**: reset every store in place (many coordinators, races with the autosave queue);
terminate the app (not allowed on iOS).

## FILE-011-D2: Atomicity

**Decision**: The same journal pattern as FILE-005's installer: write `erase.journal.json` (prepared:
folders, keys, media IDs), rename each chosen folder into `LibraryErase/trash/`, rewrite the journal as
committed (the commit point), then remove the keys, release media, delete `trash/` and the journal. A
failure before the commit renames everything back. `recover` at launch: prepared → roll back (the
request, still present, then runs again); committed → finish. Every step goes through `perform`, which
a test hook can make fail. **Rationale**: renames on one volume are atomic and cheap; deletion happens
only after the commit. **Alternative**: delete in place (not atomic).

## FILE-011-D3: Media references

**Decision**: When scenes are erased and photos and videos are not, the planner collects the photo and
video IDs named by the stored scenes (`ShowStore.referencedMediaIDs`) and the current scene, removes the
current photo and video IDs (`settings.photo.id`, `settings.video.id`), and releases the rest through
`ContentAddressedMediaFolder.release` after the commit (a payload goes with its last reference).
Erasing photos and videos removes both folders and the three media keys; scenes are untouched and
read "no longer stored". **Rationale**: FILE-008 keeps a reference per ID; references kept only for
erased scenes would otherwise linger invisibly.

## FILE-011-D4: Settings category

**Decision**: FILE-005's included keys minus `favorites` (Collections and favorites), `lastPresetID`
(forgotten with My Presets when it names a user preset), `settings.photo.id` (Photos and videos),
`settings.reduceFlashing` and `settings.visual.colorBlindSafePalette` (safety and accessibility),
plus `settings.osc.enabled` and `settings.midi.enabled` (back to off). Keys are removed, so each store
reads its default. **Rationale**: a reset must never weaken a photosensitivity or accessibility choice.

## FILE-011-D5: Confirmation

**Decision**: Sheet with checkboxes → destructive alert naming every category and count, "Erase at
Next Launch" (destructive role) and Cancel (cancel role, so neither is a default action that Return
triggers on Erase); no typed confirmation. **Rationale**: two explicit steps plus a cancellable pending
state; a typed word in an alert is a VoiceOver and Dynamic Type burden.

## FILE-011-D6: Counts and sizes

**Decision**: `LibraryEraseInventory` reads counts with the stores' readers (ShowStore scene IDs, the
preset index, the collections file, the favorites setting, media registries, audio asset files, set
keys) and sizes with `StorageUsageCalculator` (FILE-009) over each category's folders, on a detached
utility task.

## FILE-011-D7: Never touched

The bundle, StoreKit, `Library/Caches` (Metal caches stay: no user data, rebuilt by the system,
cleared by FILE-010), `tmp`, `notice.*`, `permission.*`, `session.*`, `guide.*`, the two kept
settings, `LibraryRestore/`. The eraser only renames folders whose names come from the policy, under
the library root, and refuses a folder path that resolves outside it.
