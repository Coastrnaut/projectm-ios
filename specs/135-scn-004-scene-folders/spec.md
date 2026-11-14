# Feature Specification: SCN-004 Scene Folder Organization

**Feature Branch**: `feature/scn-004` (spec directory `135-scn-004-scene-folders`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (SCN-004-T01-T14 verified on the Mac: host package tests and the
feature's own iOS 27.2 simulator "SCN4"; no device claim). ShowControl 56 tests (0.74 s; 14 new),
LibraryBackup 45 (13.9 s; 1 new), projectM-iOSTests 616 (42.2 s; SceneFolderAcceptanceTests 6 in
0.06 s, one new switcher test), SceneFoldersUITests 1 (28.1 s, 28.9 s). Linux: not run here (no
container on this Mac); CI's Linux job builds and tests ShowControl and LibraryBackup.

**Input**: User description: "Implement SCN-004 (Scene folder organization) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Organize saved scenes in nested
local folders." Acceptance, verbatim: "Move scene between folders; references remain valid."
Verification: schema round trip, integration, and simulator. P1, size M, depends on SCN-001
(integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SCN-004-R1…`, success criteria `SCN-004-S1…`, tasks `SCN-004-T01…`. Other features
are cited by their own IDs: SCN-001 (scene document), SCN-003 (duplicate and rename), SHOW-001 (cue
list), UIX-002 (scene switcher), FILE-001 (scene archive), FILE-004 (import), FILE-005 (library
backup), FILE-011 (local data erase), SCN-013 (migration), FR-070 (accessibility).

## Baseline: what exists today (audit of 2026-11-14, commit `e8dde5c0`)

The row's gap status is "Gap candidate". The audit confirms the gap: there are no folders.

| Area | Today |
|---|---|
| Saved scenes | SHOW-001's show is the only place named scenes are kept: `Show/show.json` (the cue list, format version 1) and `Show/Scenes/<SCENE-ID>.scene.json` (canonical SCN-001 bytes, file named by the scene ID). A scene is stored while at least one cue refers to it; saving the show removes scene files no cue refers to. SCN-002's `current.scene` is the live look (one fixed file), not a named scene. |
| Scene identity | Every reference uses the scene ID: cues (`scene` field), the show's position (a cue ID), UIX-002's switcher rows (cues), FILE-001 archives and FILE-004 imports (scene ID plus derived IDs on conflict). |
| Scene editing | SCN-003: Duplicate Scene (new scene ID, new cue after its source) and Rename Scene (rewrites the file under the same ID) from Settings → Show; byte-exact apart from ID and name. |
| Switcher | UIX-002 lists the show's cues in show order with the scene name when it differs from the label; search folds case, accents and width. |
| Backup and restore | FILE-005 reads `show.json` through the show model and re-encodes it, and copies each scene's canonical bytes; exact restore writes them back; merge restore goes through FILE-004's import, which decodes the stored show, appends cues and saves it. |
| Erase | FILE-011's Show category removes the whole `Show` folder. |
| Other references | No MIDI, OSC or favourite references a scene; session recovery and autosave use `current.scene` only. No "last scene" key exists besides the show's stored position. |

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the conservative, local-first option.

- Q: Which scenes does the user organize, given there is no separate scene library? → A: The show's stored scenes (each distinct scene ID the cues refer to). They are the app's only saved, named scenes (baseline); a scene appears once in the folder view however many cues show it. Rejected: building a second scene library beside the show (a new store that every other row would have to keep in step with the show).
- Q: Are folders real directories on disk? → A: No, folders are logical. The folder tree (ID, name, parent) and each scene's folder assignment live in the show's index file (`show.json`), and scene files never move. Moving files would change paths that backups, imports and the SCN-013 originals rely on and could half-fail; a logical move rewrites one index file atomically. Because a scene is always referenced by its scene ID, a move never changes the ID and every reference stays valid by construction.
- Q: How deep can folders nest, and what names are allowed? → A: At most 5 levels; at most 256 folders. A name is trimmed, 1 to 80 characters on one line, and unique among its siblings regardless of case, accents and width (so "Live" and "live" cannot sit side by side). A move that would put a folder inside itself or its own descendants, or past 5 levels, is refused with a message and changes nothing.
- Q: What does deleting a folder do with its contents? → A: Its scenes and subfolders move up to its parent (the top level for a top-level folder); no scene is ever deleted with a folder. A moved subfolder whose name collides with a sibling in the parent gets " 2", " 3"… appended. Deleting a non-empty folder asks for confirmation that names what will move. Rejected: recursive deletion of scenes (a scene exists because cues show it; deleting it would silently break cues; scenes leave the show by removing their cues, as today).
- Q: How is the existing index migrated? → A: The new fields are optional and the format version stays 1. A file without them reads as "every scene at the top level, no folders", and writing a show with no folders and no assignments gives exactly the same bytes as before, so files written before this row round-trip byte for byte and an older app version can still read new files (it ignores the extra fields; it drops them if it saves).
- Q: Does a single-scene archive (FILE-001) carry the folder? → A: No. A scene archive holds the scene only; an imported scene lands at the top level. Folder paths are the user's organization on one device and another device may not have the same folders; scene files are not changed by this row at all. The full library backup (FILE-005) does carry folders, since it carries the show's index.
- Q: Does the scene switcher (UIX-002) show folders? → A: It stays flat in show order (show order is what a performer steps through), and each row gains its scene's folder path as a secondary line and in its VoiceOver value; a search also matches the folder path. Rejected: drill-down in the switcher (it is a quick, keyboard-first overlay).
- Q: Where does a duplicated scene (SCN-003) go? → A: Into the same folder as its source, so a variation sits next to the scene it came from.

### Session 2026-11-14 (speckit-clarify)

Answered by Claude under owner rules 4 and 9 (recommended option first).

- Q: Can a scene be shown (applied) from the folder view? → A: Yes, through one action, "Go to Cue", which goes to the first cue (in show order) that shows the scene, exactly as SHOW-001's Go to Cue; tapping a scene row does nothing else, so browsing never changes the output by accident. Rejected: tap to apply (an accidental tap on stage changes the look); no way to apply (the folder view would be a dead end).
- Q: How does the user pick a destination for "Move to…"? → A: A sheet lists "Top Level" and the whole folder tree, indented by depth, with each folder's path read by VoiceOver; destinations that would be refused (the current folder, for a folder itself and its descendants, or one that would exceed 5 levels) are shown dimmed and cannot be chosen. Rejected: drag and drop between levels (hard with VoiceOver and Full Keyboard Access, and impossible across drill-down screens).
- Q: Are folder edits undoable? → A: No undo history: a move is reversed by moving back, and folder deletion never deletes a scene. Folder edits are not scene content, so they stay out of SCN-010's scene history (a scene undo must never reorganize the library).
- Q: What does VoiceOver announce? → A: A completed move ("Moved Finale to Set A / Encore."), a created, renamed or deleted folder, and every refusal with its reason, through the shared announcer's library lane. Rejected: silent edits (a VoiceOver user cannot see the row disappear from the current level).
- Q: Can a folder hold a scene that is not stored any more? → A: No. Assignments exist only for scenes the show's cues refer to; when the last cue of a scene is removed, its assignment is dropped at the next save together with the scene file (as SHOW-001 removes the file). A scene that is referred to but unreadable keeps its folder and is listed as "Scene missing".

## User Scenarios & Testing *(mandatory)*

### User Story 1 - I sort my scenes into folders (Priority: P1) — MVP

A performer with twenty scenes in their show opens Settings → Show → Scene Folders, creates a folder
"Set A", and inside it "Encore". They move the "Finale" scene into "Set A / Encore". Opening "Set A",
then "Encore", shows "Finale". Their cues still show the same scenes; stepping to the Finale cue
shows Finale exactly as before.

**Why this priority**: It is the row's behaviour and acceptance.

**Independent Test**: Create nested folders, move a scene from one folder to another, and check that
its scene ID is unchanged, a cue referencing it still resolves and applies, the switcher still lists
it, and after reloading the show from disk the scene is still in the new folder.

**Acceptance Scenarios**:

1. **Given** folders A and B/C and a scene in A, **When** the user moves it to B/C, **Then** its scene ID is unchanged, the scene file's bytes are unchanged, a cue that shows it still applies the same scene, and the switcher row still resolves to it.
2. **Given** that move, **When** the app is relaunched (the show reloaded from disk), **Then** the scene is in B/C.
3. **Given** the scene list at the top level, **When** the user creates a folder, moves a scene into it and opens the folder, **Then** the scene is listed there and no longer at the top level.

---

### User Story 2 - I keep the folder tree tidy (Priority: P2)

The performer renames "Encore" to "Encores", moves it to the top level, and later deletes "Set A";
its scenes move up to the top level and nothing is lost.

**Why this priority**: Organizing needs rename, move and delete to be usable for more than one set.

**Independent Test**: Rename, move and delete folders, including refused moves (cycle, too deep,
name taken), and check the tree and every scene's folder afterwards.

**Acceptance Scenarios**:

1. **Given** A/B, **When** the user tries to move A into B, **Then** the move is refused ("A folder cannot be moved into itself."), and nothing changes.
2. **Given** a folder with two scenes and one subfolder, **When** the user deletes it and confirms, **Then** the scenes and the subfolder are in its parent and every cue still shows its scene.
3. **Given** a folder "Live" at the top level, **When** the user creates or renames another top-level folder to "live", **Then** it is refused ("A folder named live already exists here.").
4. **Given** a folder nested 5 levels deep, **When** the user tries to create a folder inside it, **Then** it is refused.

---

### User Story 3 - My folders survive backup and upgrades (Priority: P2)

The performer backs up the library, erases it and restores it: their folders come back. A show saved
before this version opens with every scene at the top level.

**Independent Test**: A full backup round trip keeps the tree and assignments; a fixture show file
without folder fields decodes with no folders and re-encodes byte for byte.

**Acceptance Scenarios**:

1. **Given** a show with folders, **When** it is backed up and restored exactly, **Then** the folders and assignments are the same.
2. **Given** a version 1 show file written before this row, **When** it is read, **Then** every scene is at the top level and writing it again gives identical bytes.
3. **Given** a show file whose folder data is damaged (unknown parent, cycle, duplicate name, assignment to an unknown folder), **When** it is read, **Then** the show and its cues load, the bad folder entries are dropped with a warning, and affected scenes appear at the top level.

### Edge Cases

- A scene whose cues are all removed leaves the show (as today); its folder assignment is dropped with it. Empty folders stay.
- A scene that cannot be read is still listed in its folder, marked "Scene missing", and can be moved.
- Two cues showing the same scene: the scene is listed once; moving it affects both cues' scene (they share it).
- Merge restore and scene import (FILE-004): imported scenes land at the top level; the existing folders and assignments are kept.
- Moving a scene to the folder it is already in changes nothing and writes nothing.
- A move or folder edit that cannot be saved stays in effect for the session and the editor shows "The show could not be saved." (as other show edits).

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-004-R1**: The show keeps a folder tree: each folder has a stable ID, a name and an optional parent folder (none = top level). Empty folders are allowed.
- **SCN-004-R2**: Each stored scene has at most one folder (none = top level); a scene's folder is recorded by its scene ID and never changes the scene ID, the scene file or any cue.
- **SCN-004-R3**: Folder names are trimmed, 1 to 80 characters, one line, and unique among siblings ignoring case, accents and width; at most 256 folders; at most 5 levels.
- **SCN-004-R4**: The user can create a folder (at the top level or inside a folder), rename a folder, move a folder (refused when it would contain itself or exceed 5 levels or collide with a sibling name), and move a scene to any folder or the top level.
- **SCN-004-R5**: Deleting a folder moves its scenes and subfolders to its parent; colliding subfolder names get a numeric suffix; no scene is deleted. A non-empty folder asks for confirmation first.
- **SCN-004-R6**: Folder changes never apply a scene or change the show's position or cue order (as SHOW-001 edits).
- **SCN-004-R7**: The folder data is stored in the show's index as optional fields; format version stays 1; a file without them reads as all scenes at the top level, and a show without folders encodes to the same bytes as before this row. Encoding is deterministic (same show → same bytes).
- **SCN-004-R8**: Damaged folder data never refuses the show: invalid folders (bad ID or name, unknown parent, cycle, too deep, duplicate sibling name, over the limit) and assignments to unknown folders or to scenes no cue shows are dropped with a warning.
- **SCN-004-R9**: The library backup and exact restore (FILE-005) carry the folders; merge restore and scene import keep the existing folders and put imported scenes at the top level; single-scene archives (FILE-001) carry no folder.
- **SCN-004-R10**: Settings → Show → Scene Folders lists the folders and scenes of one level (folders first, then scenes, each sorted by name), with drill-down into a folder, "New Folder", and per row Rename / Move to… / Delete (folders) and Move to… (scenes) through swipe actions, context menus and VoiceOver actions, plus Go to Cue for a scene (its first cue). "Move to…" offers Top Level and the folder tree, with refused destinations dimmed.
- **SCN-004-R11**: The scene switcher stays flat in show order; each row shows its scene's folder path (e.g. "Set A / Encore") and VoiceOver reads ", folder Set A / Encore"; search also matches the folder path.
- **SCN-004-R12**: Duplicate Scene puts the copy in its source's folder.
- **SCN-004-R13**: Every folder row and scene row has a VoiceOver label (its name), a value ("Folder, 3 scenes, 1 folder" or "Scene, 2 cues" plus ", scene missing"), and named actions for its operations (FR-070); refusals, completed moves and folder creation, rename and deletion are announced through the app's announcer (library lane).
- **SCN-004-R15**: Folder edits have no undo history and are not part of SCN-010's scene history.
- **SCN-004-R14**: No networking, no new stored settings keys; all data stays in the app's local show folder.

### Key Entities

- **Scene folder**: stable ID, name, optional parent folder ID.
- **Folder tree**: the set of folders plus the scene-to-folder assignments (by scene ID), part of the show.
- **Folder path**: the names from the top level down to a folder, joined with " / ".

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-004-S1**: Moving a scene between folders leaves its scene ID, its file bytes and every cue unchanged; the cue applies the same scene before and after (automated acceptance test).
- **SCN-004-S2**: After a reload from disk, 100% of folder assignments and folders are as before the reload (round trip test).
- **SCN-004-S3**: A show file written before this row decodes with no folders and re-encodes byte for byte (fixture test).
- **SCN-004-S4**: 100% of cycle, depth and name-collision attempts in the tests are refused with no change.
- **SCN-004-S5**: A user creates a folder, moves a scene into it and finds it there in under 30 seconds on the simulator (UI test).
- **SCN-004-S6**: A backup round trip preserves every folder and assignment.

## Assumptions

- The show's scenes are the saved scenes this row organizes (baseline). A separate scene library is not built.
- Folder order is by name (localized, case-insensitive), not manual; manual ordering can come later.
- Simulator and Mac results are not device evidence; this row needs no device-only check.
