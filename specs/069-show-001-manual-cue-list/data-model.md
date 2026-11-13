# Data Model: SHOW-001 Manual Cue List

## ShowCue

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | Unique in the show; never changes (moves, renames keep it). |
| `sceneID` | String | Canonical uppercase UUID text (SCN-001 scene `id`). May repeat across cues. |
| `label` | String | Trimmed, 1…80 characters (grapheme clusters); newlines refused. |

## ShowCueList (the show)

| Field | Type | Rules |
|---|---|---|
| `id` | UUID | The show's ID. |
| `name` | String | Trimmed, 1…80 characters; default "Show". |
| `cues` | [ShowCue] | Ordered; at most 256. |
| `position` | `.standby` \| `.cue(UUID)` | `.cue` names an existing cue. |

Derived: `activeIndex` (Int?), `activeCue`, `activeSceneID`, `canGoNext`, `canGoPrevious`,
`positionText` ("Cue 2 of 5" / "Standby").

### Operations (all pure, mutating)

| Operation | Result | Position afterwards |
|---|---|---|
| `next()` | `.moved` / `.atEnd` / `.empty` | standby → first; n → n+1; last unchanged |
| `previous()` | `.moved` / `.atStart` / `.empty` | n → n−1; first and standby unchanged |
| `go(to: cueID)` | `.moved` / `.unknownCue` | the cue |
| `append(sceneID:label:)` | cue or `ShowEditError.tooManyCues/invalidLabel/invalidSceneID` | unchanged |
| `remove(cueID)` | removed cue or `.unknownCue` | active removed → cue before it, or standby |
| `move(fromOffsets:toOffset:)` | — | unchanged (cue ID) |
| `rename(cueID, label)` | `.unknownCue/.invalidLabel` | unchanged |

`ShowStep` = `{ outcome, position, sceneID? }` for each step.

### State transitions (position)

```text
standby --next--> cue[0]
cue[i]  --next--> cue[i+1]   (i < last)      cue[last] --next--> cue[last] (atEnd)
cue[i]  --prev--> cue[i-1]   (i > 0)         cue[0]/standby --prev--> unchanged (atStart)
any     --go(c)--> cue c
cue[i]  --remove(cue[i])--> cue[i-1] or standby
```

## Validation (load)

| Problem | Severity | Effect |
|---|---|---|
| file > 1 MiB, not JSON, wrong `format`, missing field | error | refuse the file (set aside) |
| `version` > 1 | error (`newerVersion`) | refuse (set aside, never overwritten) |
| more than 256 cues | error | refuse |
| duplicate cue ID | error | refuse |
| bad UUID text, bad label | error | refuse |
| `position` names no cue | warning | position becomes standby |
| scene file missing / unreadable / invalid for a cue | warning (`missingScene`) | cue kept and flagged |

## Stored files

```text
Application Support/Show/
├── show.json                      ShowDocument v1 (contracts/show-document.md)
├── show.damaged-<n>.json          a refused file, set aside
└── Scenes/<SCENE-ID>.scene.json   canonical SCN-001 bytes; document id == file name
```

## App-side look (ShowSceneSnapshot)

Visual (projectM, Circular, Linear, Photo, Video, Text), bar count, orientation, spacing, glow
(enabled, intensity, radius, threshold), text spec, photo store ID, video store ID ↔ SCN-001 document
(research SHOW-001-D5).
