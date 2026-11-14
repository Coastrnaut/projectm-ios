# Data Model: UIX-002 Quick Scene Switcher

All types are in memory only (UIX-002-R12).

## SceneSwitcherEntry (value, Equatable, Sendable)

| Field | Type | Rule |
|---|---|---|
| `cueID` | UUID | identity of the row (a scene shown by two cues gives two rows) |
| `number` | Int | 1-based position in the show |
| `label` | String | the cue label |
| `sceneName` | String? | the stored scene's name; nil when unreadable or equal to the label |
| `isActive` | Bool | the cue is the show's active cue |
| `isMissing` | Bool | the cue's scene ID is in the show's unreadable set |

`entries(list:sceneNames:unreadable:)` builds them in show order.

## SceneSwitcherFilter (pure)

`results(_ entries: [SceneSwitcherEntry], query: String) -> [SceneSwitcherEntry]` per research
UIX-002-D2. `fold(_:)` is the shared normalization.

## SceneSwitcherModel (@MainActor @Observable)

| Field | Type | Rule |
|---|---|---|
| `isOpen` | Bool | |
| `query` | String | the field's text, never trimmed in place |
| `highlightedCueID` | UUID? | nil only when there are no results |
| `abandonedQuery` | String | the query at the last close without a choice; "" after a choice |
| `focusReturnRevision` | Int | bumped on a close without a choice |
| `probe` | SceneSwitchLatencyProbe | |

Transitions:

- `open(entries)`: `isOpen = true`; `query = abandonedQuery`; highlight = previous highlight if still
  in results (only when a query was restored), else the active entry if in results, else the first.
- `queryChanged(entries)`: highlight kept if still in results, else first result, else nil.
- `moveHighlight(by: ±1, entries)`: within results, clamped at both ends (no wrap); from nil to the
  first result.
- `close(chose: Bool)`: `isOpen = false`; `abandonedQuery = chose ? "" : query`; `query = ""` after a
  choice; `focusReturnRevision += 1` when not chose.

## SceneSwitchLatencyProbe (value)

| Field | Type |
|---|---|
| `budget` | Double = 0.250 s |
| `pending` | (sceneID: String, cueID: UUID, start: Double)? |
| `last` | SceneSwitchMeasurement? |

- `begin(sceneID:cueID:now:)` sets `pending` (a new begin replaces a pending one).
- `finish(_ outcome: Outcome, now:) -> SceneSwitchMeasurement?`: nil without `pending`; else records
  `last`, clears `pending`. `Outcome`: `applied`, `repairShown`, `failed`.

## SceneSwitchMeasurement (value)

`outcome`, `sceneID`, `cueID`, `seconds`; `milliseconds` (rounded to 0.1), `withinBudget`
(`seconds <= budget`), `probeText` = `"<outcome>|<sceneID>|<ms>|<ok|over>"` (ms with one decimal,
POSIX formatting).
