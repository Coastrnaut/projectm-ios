# Research: SCN-004 Scene Folder Organization

## SCN-004-D1: Logical folders in the show index, not directories

- **Decision**: The folder tree and the scene → folder assignments are two optional fields of
  `show.json`. Scene files stay at `Show/Scenes/<ID>.scene.json`.
- **Rationale**: Every reference to a scene is its scene ID (baseline), so a move that changes only
  the index cannot break any reference. One atomic index write per edit; no multi-file move that can
  half-fail; SCN-013 originals and FILE-004 staging keep their paths.
- **Alternatives**: real subdirectories (paths change, partial moves, backup and import code would
  need folder walking); a `folderID` inside each scene document (a move rewrites the scene file,
  changes its bytes and archive digest, and splits the tree from its members across files); a
  separate `folders.json` (two files to keep in step; FILE-005 and FILE-004 would need changes).

## SCN-004-D2: Tree rules

- **Decision**: depth ≤ 5 (a top-level folder is depth 1), ≤ 256 folders, names via the cue label
  rule (trimmed, 1-80 characters, one line), sibling-unique by `folding([.caseInsensitive,
  .diacriticInsensitive, .widthInsensitive], locale: nil)` (the same fold UIX-002 uses). Moving a
  folder is refused if the target is the folder or a descendant (cycle), if the target's depth plus
  the moved subtree's height exceeds 5, or if a sibling name collides. Deleting re-parents children;
  a colliding child folder name gets " 2", " 3"… (shortened to fit 80).
- **Rationale**: Small, predictable limits; folding matches how users read names.

## SCN-004-D3: Encoding without a version bump

- **Decision**: `folders` (array, ordered by depth then canonical ID text) and `sceneFolders`
  (object; JSON sorted keys) are written only when non-empty; assignments are written only for
  scenes the cues refer to and folders that exist. Absent fields decode as an empty tree.
- **Rationale**: A show without folders is byte-identical to version 1 files written before this
  row (fixture test); an older app decodes the file (JSONDecoder ignores unknown keys). Owner
  convention: new fields optional, no version bump.

## SCN-004-D4: Damaged folder data is repaired, never fatal

- **Decision**: Decode folders in passes: accept a folder when its ID is canonical and unused, its
  name is valid, its parent is absent or already accepted, the depth is ≤ 5, its name is unique in
  the parent and the limit is not reached; repeat until nothing new is accepted. The rest is dropped
  (`droppedFolders(n)`). Assignments with a bad scene ID, an unknown folder or a scene no cue refers
  to are dropped (`droppedFolderAssignments(n)`).
- **Rationale**: The cues are the valuable part; refusing the whole show for a folder typo would set
  the show aside. Cycles and unknown parents are never accepted because a parent must be accepted
  first.

## SCN-004-D5: Backup, import and archives

- **Decision**: No code change in LibraryBackup or ShowStorage: both read the show through
  `ShowCueList.decode` and write `encoded()`, so folders are carried by exact restore and kept by
  merge restore and FILE-004 import (new cues' scenes land at the top level). FILE-001 single-scene
  archives carry no folder. A LibraryBackup test proves the round trip.

## SCN-004-D6: Switcher stays flat

- **Decision**: `SceneSwitcherEntry.folderPath` ("Set A / Encore"), shown in the subtitle and read
  as ", folder Set A / Encore"; the filter matches the folded path as a non-early match.
- **Rationale**: Show order is the performer's order; the switcher is a quick overlay.
