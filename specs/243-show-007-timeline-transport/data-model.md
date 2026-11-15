# Data Model: SHOW-007 Timeline Transport

## ShowTimeline (pure, ShowControl)

| Field | Type | Rule |
|---|---|---|
| `entries` | `[Entry]` | non-skipped cues in show order up to and including the first without a dwell |
| `Entry.cueID` / `index` | `UUID` / `Int` | `index` is the cue's index in the list |
| `Entry.start` | `Duration` | sum of the earlier entries' spans |
| `Entry.span` | `Duration?` | the dwell; nil only for the last entry (open end) |
| `duration` | `Duration` | sum of spans (an open end adds 0) |
| `isOpenEnded` | `Bool` | last entry has no span |
| `canLoop` | `Bool` | not open-ended and duration > 0 |

`locate(t, looping)`: t < 0 → 0; looping and `canLoop` → t mod duration; otherwise clamped to duration. The entry
with start ≤ t < start + span; t = duration → last entry with elapsed = span (remaining 0) or, open-ended, the last
entry with elapsed 0. Returns `Point(cueID, index, elapsed, remaining: Duration?)`.

## ShowSeekAction

`.none` | `.reposition(cueID, remaining)` | `.apply(cueID, remaining)`; remaining nil for an open end.

## ShowScrub

`isScrubbing`, `previewTime: Duration?`; `begin()`, `move(to:)`, `end() -> Duration?` (nil when nothing moved),
`cancel()`.

## Loop setting

`settings.show.loop`: Bool, absent = off. In `AppSettings.allKeys` (UI-test reset, Settings erase), excluded from
backup (`LibrarySettingsPolicy.excludedKeys`), allowed in `run_device_tests.py`.
