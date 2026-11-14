# Data Model: SCN-004 Scene Folder Organization

## SceneFolder

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | Stable; canonical uppercase text in the file; never changes on rename or move. |
| `name` | String | Trimmed, 1-80 characters, one line; unique among siblings (folded: case, accents, width). |
| `parentID` | UUID? | nil = top level; must name an existing folder; no cycles; depth ≤ 5. |

## SceneFolderTree (part of `ShowCueList` as `folders`)

| Field | Type | Rules |
|---|---|---|
| `folders` | [UUID: SceneFolder] | ≤ 256. |
| `assignments` | [String: UUID] | Scene ID → folder ID; a scene without an entry is at the top level. Only scenes the cues refer to are written. |

Derived: `children(of:)` (sorted by folded name, then ID), `sceneIDs(in:among:)`, `path(of:)`
(top-down names), `depth(of:)` (top level = 1), `height(of:)` (1 for a leaf).

Operations and outcomes (all throw `SceneFolderError` and change nothing on refusal):

| Operation | Refusals |
|---|---|
| `createFolder(named:in:id:)` | invalidName, nameTaken, unknownFolder (parent), tooDeep, tooManyFolders, duplicateFolderID |
| `renameFolder(_:to:)` | unknownFolder, invalidName, nameTaken |
| `moveFolder(_:to:)` | unknownFolder, intoItself (cycle), tooDeep, nameTaken |
| `moveScene(_:to:)` | unknownFolder, sceneNotInShow (ShowCueList) |
| `deleteFolder(_:)` | unknownFolder; returns what moved (scene count, folder count, renamed folders) |

## show.json (version 1, optional keys)

```json
{
  "cues": [...], "format": "projectm-ios.show", "id": "...", "name": "Show", "position": null,
  "folders": [{"id": "F...", "name": "Set A", "parent": null}, {"id": "F...", "name": "Encore", "parent": "F..."}],
  "sceneFolders": {"5CE7E000-...": "F..."},
  "version": 1
}
```

Written only when non-empty. Decode warnings: `droppedFolders(Int)`, `droppedFolderAssignments(Int)`.

## App view state

- `SceneFolderLevel`: the folder shown (nil = top level), its subfolders and scenes (scene ID, name or
  nil when unreadable, cue count).
- Switcher: `SceneSwitcherEntry.folderPath: String?`.
