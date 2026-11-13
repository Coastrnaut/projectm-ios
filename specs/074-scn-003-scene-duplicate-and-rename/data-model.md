# Data Model: SCN-003 Scene Duplicate and Rename

No stored format changes: the scene document (SCN-001 v1) and the show document (SHOW-001 v1) are
unchanged. New values and errors only.

## Scene document (SCN-001, unchanged)

| Field | Duplicate | Rename |
|---|---|---|
| `id` | new canonical UUID ≠ original | kept |
| `name` | given name (normalized) | new name (normalized) |
| `layers` (instance IDs, content, values, composite, extra) | kept exactly | kept exactly |
| `parameters` (MOD-001 IDs → values) | kept exactly | kept exactly |
| `bindings` (source IDs, targets, mapping, expression, extra) | kept exactly | kept exactly |
| `modulation` (generator IDs, connections) | kept exactly | kept exactly |
| `assets` (keys → photo/video store IDs, embedded text/graph JSON, unknown) | kept exactly (media shared by store ID; embedded documents copied with the document) | kept exactly |
| `extra` (unknown top-level fields) | kept exactly | kept exactly |

## SceneEditError (new, SceneFormat)

`invalidName` · `invalidSceneID(String)` · `sameSceneID`

## Cue (SHOW-001, unchanged)

`insert(sceneID:label:after:cueID:)`: the new cue goes at the index after `after`; errors as
`append` plus `unknownCue(after)`. The position is a cue ID, so it does not move.

## ShowSceneEditError (new, ShowStorage)

`unreadable(ShowSceneReadError)` · `invalid(SceneEditError)` · `sceneIDTaken(String)` · `writeFailed`

## StoredMediaReferences (new, ShowStorage)

`photos: Set<String>`, `videos: Set<String>`: store IDs named by `photo`/`video` assets of every
readable stored scene. Computed on each call from the files.

## Lifecycle

- Duplicate: read A → copy B (new ID, name "<A> copy") → write `Scenes/B.scene.json` (atomic) → insert
  cue → write `show.json` (atomic). If the show write fails, B's file is an orphan removed at the next
  successful save (SHOW-001 rule).
- Rename: read A → A′ (same ID, new name) → rewrite `Scenes/A.scene.json` (atomic). `show.json` is not
  written (no cue changes).
- Deleting the last cue of A removes A's file; B and the media it names are untouched.
