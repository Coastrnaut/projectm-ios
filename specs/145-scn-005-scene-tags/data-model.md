# Data Model: SCN-005 Scene Tags

## SceneTagMap (ShowControl, value type)

| Field | Type | Rules |
|---|---|---|
| `tags` | `[String: [String]]` scene ID → tags | each list sorted by (fold, text), no folded duplicates, ≤ 16; ≤ 256 distinct folded tags in the map; empty lists are removed |

Derived: `vocabulary: [String]` (one spelling per folded tag, smallest by (fold, text), sorted),
`count(of tag:)` (scenes carrying it).

Operations: `add(_:to:)` (normalizes, adopts the existing spelling, refuses invalid / present /
over-limit), `remove(_:from:)` (folded match), `copyTags(from:to:)`, `matches(sceneID:all:)`,
`prune(keepingScenes:)`, `repaired(raw:sceneIDs:)`.

`SceneTagError`: `invalidTag`, `alreadyTagged(String)`, `tooManyTags(limit: 16)`,
`tooManyDistinctTags(limit: 256)`, `notTagged(String)`, `sceneNotInShow(String)`.

## ShowCueList

- `tags: SceneTagMap` (internal(set)), `addTag`, `removeTag`, `copyTags` (scene must be in the show).

## show.json (version 1, contract T1)

```json
"sceneTags": { "<SCENE-ID>": ["Intro", "Loud"] }
```

Absent when no scene in the show has tags.

## ShowDecodeWarning

- `droppedTags(Int)`: tags or entries left out of `sceneTags`.

## SceneSwitcherEntry / SceneSwitcherModel (app)

- `SceneSwitcherEntry.tags: [String]` (the scene's tags).
- `SceneSwitcherModel.selectedTags: Set<String>` (folded; in memory), `toggleTag(_:)`.
