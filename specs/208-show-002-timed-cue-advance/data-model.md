# Data Model: SHOW-002 Timed Cue Advance

## ShowCueDwell (ShowControl)

| Field | Type | Rule |
|---|---|---|
| `seconds` | Int | 1…3600 (`minimumSeconds`, `maximumSeconds`); init throws `ShowDwellError.outOfRange` otherwise |

- `duration: Duration` = `.seconds(seconds)`.
- `presets`: 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600 s.
- `clockText`: "0:05", "1:30", "60:00" (m:ss). `spokenText`: "5 seconds", "1 minute 30 seconds".

## ShowCue (changed)

- New optional `dwell: ShowCueDwell?` (nil = Off). `ShowCueList.setDwell(_:to:)` sets it (unknown cue throws);
  `insert(... dwell:)` carries it for Duplicate Scene.

## ShowAdvanceTimeline (ShowControl)

State (`phase`):

| Phase | Fields | Meaning |
|---|---|---|
| `idle` | — | nothing pending |
| `running` | `cueID`, `deadline: Duration` | advance due at `deadline` |
| `held` | `cueID`, `remaining: Duration` | frozen |

Transitions:

- `cueStarted(cue, hasNext, at: now)`: dwell nil or no next → `idle`; else held? `held(cue, dwell)` : `running(cue, now + dwell)`.
- `setHeld(true, at: now)`: `running(c, d)` → `held(c, max(0, d − now))`. `setHeld(false, at: now)`: `held(c, r)` → `running(c, now + r)`.
- `due(at: now) -> UUID?`: `running(c, d)` with `now ≥ d` → returns `c`, phase `idle` (fires once). Else nil.
- `remaining(at: now)`: running → `max(0, d − now)`; held → `r`; idle → nil.
- `cancel()` → `idle`.

## ShowTimedAdvance (ShowControl)

- `tick(list: inout ShowCueList, timeline: inout ShowAdvanceTimeline, at now) -> ShowStep?`: if `due` returns the active cue's ID, `list.next()`; when it moved, `cueStarted(new active, hasNext, now)`; returns the step. A due cue that is no longer active returns nil (cancelled).
- `step(...)`: helper used by tests for manual steps (Next/Previous/Go) followed by `cueStarted`.

## Countdown (app)

`ShowCountdown { seconds: Int; held: Bool }` — `seconds` = remaining rounded up to whole seconds. Text "Next in 0:42" / "Next in 0:42, held"; spoken "next cue in 42 seconds" / "countdown held, 42 seconds left".
