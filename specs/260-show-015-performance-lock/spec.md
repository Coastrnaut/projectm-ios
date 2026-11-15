# Feature Specification: SHOW-015 Performance Lock

**Feature Branch**: `feature/show-015` (spec directory `260-show-015-performance-lock`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SHOW-015-T01-T11 verified on the Mac, simulator "SHOW15 iPhone 17", iOS 27.2; no
device claim; T12 `{device}` open). Extends the SCN-015 scene lock (no new state). PerformanceLockAcceptanceTests 4
(0.07 s); unit regression 69 tests (1.9 s); PerformanceLockUITests 1 (under 30 s); UI regression: SceneLock, SceneFolders,
PresetCollections (9), PresetSmartCollection, LibraryErase, LibraryBackup.

**Input**: Roadmap row SHOW-015 (P1, size S, depends on SHOW-014, integrated). Observable behavior, verbatim:
"Disable destructive gestures while retaining emergency controls." Acceptance, verbatim: "Lock blocks delete/reorder
but blackout remains accessible."

Identifiers carry the roadmap ID: requirements `SHOW-015-R1…`, success criteria `SHOW-015-S1…`, tasks
`SHOW-015-T01…`, research decisions `SHOW-015-D1…`. Other features are cited by their own IDs: SCN-015 (scene lock),
SHOW-001 (show and cues), SHOW-014 (emergency blackout), OUT-010 (output blackout), SCN-004 (scene folders), SCN-005
(scene tags), PRE-007 (preset collections), PRE-008 (smart collections), FILE-005 (library backup and restore),
FILE-011 (data erase), FR-072 (Reduce flashing), ACC-004 (announcer lanes).

## Baseline: destructive gestures on performance surfaces (audit of 2026-11-14, commit `2279477a`)

| Surface and gesture | Owner of the write | Today, with SCN-015's lock on | SHOW-015 decision |
|---|---|---|---|
| Show editor: cue swipe-to-delete, Edit button, drag reorder, Delete/Move/Rename/Duplicate menu items and VoiceOver actions, add buttons | `ShowCoordinator.remove/move/…` | Refused in the coordinator; gestures hidden, add disabled, note shown | Already done (reused) |
| Show transport: Next, Previous, Go to cue (buttons, keys, MIDI) | `ShowCoordinator.next/previous/go` | Works | Emergency control: stays |
| Scene Folders (Settings › Show): folder Delete…/Rename…/Move to…, scene Move to…/Tags…, New Folder | `ShowCoordinator.deleteFolder/renameFolder/moveFolder/moveScene/addTag/removeTag/createFolder` | Refused in the coordinator, but every swipe action, menu item and VoiceOver action is still offered (refusal only after the tap) | Hide or disable them while locked; show the lock note |
| Scene switcher (UIX-002) | `ShowCoordinator.goToScene` | Navigation only (no delete there) | Unchanged (navigation) |
| Preset collections (PRE-007): delete (swipe, menu, alert), Edit and drag reorder, Move Up/Down (menu, VoiceOver), Remove from Collection (swipe, menu, VoiceOver), reorder inside a collection | `PresetCoordinator.deleteCollection/moveCollections/moveCollection/movePresets/movePreset/removeFromCollection` | Not locked at all | Refused in the coordinator; gestures hidden; note shown |
| Smart collections (PRE-008): Delete (swipe, menu) | `PresetCoordinator.deleteSmartCollection` | Not locked | Refused; Delete hidden |
| Settings › Storage: Erase Data… (FILE-011) | `LibraryEraseCoordinator.openSheet/requestErase` | Not locked | Refused; button disabled with the note |
| Settings › Storage: Restore from Backup… (FILE-005, replaces the show and library at the next launch) | `LibraryBackupCoordinator.restoreTapped/requestRestore` | Not locked | Refused; button disabled with the note |
| Blackout: emergency button, B key, OUT-010 Black out/Restore | `OutputBlackout` | Works | Emergency control: stays |
| Reduce flashing (Settings safety section, FR-072) | `AppSettings.reduceFlashing` | Works (the safety sections are never disabled) | Emergency control: stays |
| Lock control: "Lock scene"/"Unlock scene" (controls, Settings, badge) | `SceneLock` | Unlock asks for confirmation | The unlock control (reused) |
| My Presets: Remove from My Presets (PRE-015), recordings delete (REC), slideshow/media item removal | their coordinators | Not locked | Out of scope (library management screens, each confirmed or reversible; not a show surface), see Clarifications |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9); each answer is the conservative,
local-first option.

- Q: Is the performance lock a new, separate lock or the SCN-015 scene lock? → A: The same lock. SCN-015's `SceneLock` (`settings.scene.locked`) already exists to "prevent accidental editing while in performance mode", already removes the show editor's delete and reorder gestures, already keeps blackout, cues and Reduce flashing working, and already has a deliberate unlock. A second switch would let the performer believe the show is safe while only one of two locks is on, and would add a second persisted key and a second badge. SHOW-015 extends that lock's coverage to the destructive gestures it still leaves (the baseline's last column). Rejected: a separate "Performance lock" mode (duplicate state, two badges, two confirmations).
- Q: Does the user-visible name change to "Performance lock"? → A: No. The control stays "Lock scene" / "Unlock scene" and the badge "Scene locked" (existing UI tests, VoiceOver labels and the SCN-015 contract stay valid); its Settings footer and unlock message now list what the lock also protects (collections, erase and restore).
- Q: Which surfaces count as performance surfaces? → A: Everything a performer touches during a show that can destroy or reorder show material: the show editor (done by SCN-015), Scene Folders and tags, preset collections and smart collections (they scope Next/Random live), and the two library-wide destructive actions in Settings › Storage (Erase Data… and Restore from Backup…, which clear or replace the show at the next launch).
- Q: Are blocked controls hidden or disabled? → A: Row gestures (swipe actions, context-menu items, VoiceOver actions, Edit/drag reorder) are hidden, as SCN-015 does in the show editor, because a disabled swipe action cannot explain itself; the screen shows the one-line note "Scene locked. Unlock the scene to edit." Toolbar and Settings buttons (New Folder, Erase Data…, Restore from Backup…) are disabled with the same note beside them. Nothing is silently ignored: a refusal that still reaches a coordinator (an alert already open, a keyboard path) changes nothing and reports the message (SCN-015-R4).
- Q: Which controls stay usable while locked (emergency controls)? → A: The emergency blackout button and B key (SHOW-014), OUT-010 Black out and Restore, the show transport (Next, Previous, Go to cue, timed advance), Reduce flashing and the other safety settings, and the unlock control. None of them consults the lock.
- Q: How is unlocking made deliberate? → A: As SCN-015 does: "Unlock scene" (controls, Settings switch or badge) opens the "Unlock scene?" confirmation with Unlock and Cancel; only Unlock unlocks. A confirmation is a standard button pair that VoiceOver, Switch Control and Full Keyboard Access reach without any special gesture; a long press is hard to discover and conflicts with VoiceOver's own gestures. The lock button's VoiceOver label, value and hint already name the action. Rejected: long press (accessibility), a custom VoiceOver-only action (the visible button already is one).
- Q: Does the lock persist across relaunch? → A: Yes (unchanged from SCN-015). If the app crashes or is killed mid-show, it comes back locked, so the first mis-tap after the relaunch is still harmless. Rejected: session-only (a crash would silently drop the protection exactly when the show is under stress).
- Q: Are destructive settings resets covered? → A: Yes for Erase Data… and Restore from Backup… (they clear or replace the show and library). A pending erase or restore that was requested before locking can still be cancelled (Cancel is the safe direction). Media restore from a folder (FILE-006) only adds files and stays available.
- Q: Are My Presets removal, recordings and media list edits covered? → A: No. They are library-management screens reached from the preset browser or Settings, each removal confirmed or reversible, and none of them changes the show, its cues or its scenes. Covering every list in the app would turn the lock into a read-only mode, which the roadmap row does not ask for.
- Q: New stored data? → A: None. The lock key `settings.scene.locked` already exists and is already in the device-test allowed keys, the Library settings policy (excluded) and the UI-test reset.

### Session 2026-11-14 (speckit-clarify)

- Q: Where does a refused collection delete or reorder (one that still reaches the coordinator, such as a delete alert already open when the lock turned on) show its message? → A: In the collections' existing message alert (`collectionsMessage`, PRE-007-R8) with the lock's text "Scene locked. Unlock the scene to edit.", and the lock announces it on VoiceOver's library lane as every SCN-015 refusal does. Rejected: a new banner (a second message channel for one screen).
- Q: Should a refused gesture be counted with the lock's other refusals? → A: Yes: every SHOW-015 refusal goes through the same `refusesEdit()` choke point, so the refusal count, last message and announcement stay one mechanism. Rejected: a separate refusal path per screen.
- Q: Do the collection and Storage screens show the visualizer's "Scene locked" badge? → A: No; they show the one-line lock note at the top of the list (as the show editor does). The badge stays a visualizer element.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Nothing can be deleted or reordered mid-show (Priority: P1)

A performer locks before the show. During it, an accidental swipe or long press on a cue, a scene folder or a preset
collection deletes, moves or reorders nothing, and the Storage buttons that would erase or replace the library cannot
be used.

**Why this priority**: It is the roadmap row.

**Independent Test**: Lock; call every delete and move handler of the show, the folders and the collections and the
erase/restore entry points; the show list, the folder tree and the collections are unchanged.

**Acceptance Scenarios**:

1. **Given** the lock is on, **When** a cue delete, a cue move, a folder delete, a collection delete, a collection reorder, a preset reorder inside a collection or a Remove from Collection is attempted, **Then** each is refused and the show and the collections are unchanged.
2. **Given** the lock is on, **When** the user swipes left on a cue or a collection, **Then** no Delete action is offered, and no Edit button (reorder) is shown.
3. **Given** the lock is on, **When** Settings › Storage opens, **Then** Erase Data… and Restore from Backup… are disabled and a note says the scene is locked.

### User Story 2 - Emergency controls stay available (Priority: P1)

While locked, the performer blacks out (emergency button), restores, steps cues with Go, and turns Reduce flashing on.

**Why this priority**: The roadmap acceptance requires blackout to stay accessible.

**Independent Test**: Lock; blackout, restore, Go to cue and Reduce flashing each act as when unlocked.

**Acceptance Scenarios**:

1. **Given** the lock is on, **When** the user taps the emergency Black out button, **Then** the output goes black and the blackout badge with Restore shows.
2. **Given** the lock is on, **When** Go to cue 3 or Next is used, **Then** the cue's scene is applied.
3. **Given** the lock is on, **When** Reduce flashing is switched, **Then** the setting changes.

### User Story 3 - Unlock deliberately, then edit (Priority: P1)

After the show the performer unlocks with a confirmation and can delete and reorder again.

**Independent Test**: Unlock; the same delete and move handlers succeed.

**Acceptance Scenarios**:

1. **Given** the lock is on, **When** the user taps Unlock scene and confirms, **Then** the delete and reorder gestures are offered again and work.

### Edge Cases

- A delete alert that was open when the lock turned on (collection or folder): its confirm is refused by the coordinator and the message is shown (collections: the message alert; folders: the Scene Folders message row).
- A list's drag reorder that was in Edit mode when the lock turned on: Edit mode ends (the Edit button and handles disappear); any move that still arrives is refused.
- A pending erase or restore requested before the lock: still listed, and Cancel still works.
- Creating a collection or adding a preset to one while locked: allowed (additive, nothing lost), consistent with "blocks delete/reorder".
- Renaming a collection or editing a smart collection's rules while locked: allowed (nothing is lost and nothing is reordered). Scene and folder renames stay refused because SCN-015 already treats them as scene edits.

## Requirements *(mandatory)*

### Functional Requirements

- **SHOW-015-R1**: The performance lock MUST be the SCN-015 scene lock (one state, one control, one badge); no new stored key.
- **SHOW-015-R2**: While locked, the preset collection deletes and reorders (delete collection, delete smart collection, reorder collections, reorder presets inside a collection, Remove from Collection) MUST be refused in the coordinator that owns the write, change nothing, and report "Scene locked. Unlock the scene to edit."
- **SHOW-015-R3**: While locked, Erase Data… and Restore from Backup… MUST be refused in their coordinators (no sheet, no request recorded) and their buttons disabled; Cancel of an already pending erase or restore stays available.
- **SHOW-015-R4**: While locked, the destructive and reorder gestures MUST NOT be offered: swipe Delete/Remove, Edit (drag reorder), Move Up/Down and Delete menu items and the matching VoiceOver actions on the preset collection and smart collection lists, inside a collection, and on Scene Folders' folder and scene rows (with New Folder disabled). Each such screen MUST show the lock note.
- **SHOW-015-R5**: While locked, the emergency controls MUST work as when unlocked: the emergency blackout button and B key, OUT-010 Black out and Restore, Next/Previous/Go to cue, Reduce flashing and the unlock control.
- **SHOW-015-R6**: Unlocking MUST stay deliberate (SCN-015's confirmation) and the lock MUST persist across relaunch (SCN-015-R1).
- **SHOW-015-R7**: The lock's Settings footer and unlock message MUST name what it protects, including collections, erase and restore.
- **SHOW-015-R8**: No scene format change, no new stored key, no network access.

### Key Entities

- **Scene lock** (existing, SCN-015): one Boolean on the device (`settings.scene.locked`); SHOW-015 adds consumers, not state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHOW-015-S1**: With the lock on, 8 of 8 representative delete/reorder attempts (cue delete, cue move, folder delete, collection delete, collection reorder, preset reorder in a collection, Remove from Collection, smart collection delete) are refused and the show list and the collections are equal to before; with the lock off the same attempts succeed.
- **SHOW-015-S2**: With the lock on, Erase Data… and Restore from Backup… open nothing and record no request.
- **SHOW-015-S3**: With the lock on, blackout, restore, Go to cue and Reduce flashing each act (4 of 4).
- **SHOW-015-S4**: In the app, with the lock on: no Delete swipe action and no Edit button on the collections list, the emergency blackout succeeds, and unlocking with confirmation works — in a UI test under 30 s.

## Assumptions

- SCN-015's coverage (show editor, Settings scene sections, undo, macros, snapshots) is unchanged and its tests stay green.
- Simulator results prove behavior only, not timing on a device; the on-device check is a `{device}` task.
