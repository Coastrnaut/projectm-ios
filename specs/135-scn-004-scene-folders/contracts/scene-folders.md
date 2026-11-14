# Contract: Scene Folders (SCN-004)

## F1 — References stay valid

A scene or folder operation never changes: any scene ID, any scene file's bytes, the cue list's
cues or order, or the show's position. A cue that showed scene X before a move shows the same scene
X (same ID, same document) after it. Proven by `SceneFolderAcceptanceTests` and the package tests.

## F2 — Tree invariants (after every successful operation and every decode)

1. Every folder's parent is nil or an existing folder; following parents always reaches the top
   level within 5 steps (no cycles, depth ≤ 5).
2. Sibling names are unique under the folded comparison.
3. At most 256 folders.
4. Every written assignment names an existing folder and a scene the cues refer to.

## F3 — Delete folder

Children (folders and scenes) move to the deleted folder's parent. A child folder whose folded name
collides with a sibling there is renamed `<name> 2`, `<name> 3`… (shortened so the result fits 80
characters). No scene, cue or scene file is removed.

## F4 — File format

- Keys `folders` and `sceneFolders` are optional; absent = empty tree; `version` stays 1.
- A show with an empty tree encodes to exactly the bytes it encoded to before SCN-004.
- Encoding is deterministic: `folders` ordered by depth then ID text; JSON keys sorted.
- Damaged folder data never refuses the show; dropped entries are counted as warnings.

## F5 — UI (Settings → Show → Scene Folders)

| Element | Identifier | VoiceOver |
|---|---|---|
| Link from the Show editor | `showSceneFoldersLink` | "Scene Folders" |
| New Folder button | `sceneFoldersNewFolder` | "New Folder" |
| Folder row (n = 1-based row) | `sceneFolderRow.<name>` | label: name; value "Folder, N scenes, M folders"; actions Open (default), Rename, Move to, Delete |
| Scene row | `sceneFolderScene.<scene name or ID>` | label: name; value "Scene, N cues" (+ ", scene missing"); actions Move to, Go to Cue |
| Move sheet destination | `sceneFolderDestination.top`, `sceneFolderDestination.<folder ID>` | label: folder path or "Top Level"; dimmed = not enabled |
| New/rename alert field | — | "Folder name" |

Announcements (library lane): "Moved <scene> to <path or Top Level>.", "Created folder <name>.",
"Renamed folder to <name>.", "Deleted folder <name>; its contents moved to <parent path or Top Level>.",
and refusal messages: "A folder cannot be moved into itself.", "A folder named <name> already exists
here.", "Folders can be nested at most 5 levels deep.", "A show holds at most 256 folders.",
"A folder name is 1 to 80 characters on one line."

## F6 — Switcher

Entries stay in show order. `folderPath` = the scene's folder path joined by " / ", nil at the top
level; subtitle `Cue 3 · <scene name> · <folder path>`; VoiceOver value gains ", folder <path>"; a
query matching only the folder path lists the entry after prefix and word-start matches.
