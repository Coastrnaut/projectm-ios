# Data Model: SHOW-005 Cue Hold and Skip

## ShowCue (ShowControl, extended)

| Field | Type | Rule |
|---|---|---|
| `skipped` | Bool | default false; edited by `ShowCueList.setSkipped`; copied by Duplicate Scene; kept by move, rename, reorder |

File: optional `skip` in the cue entry; `true` written only when skipped; absent/null/false = not skipped; any other
JSON type dropped with `ShowDecodeWarning.droppedSkipFlags(n)`.

## ShowStepOutcome (extended)

`.allSkipped`: Next or Previous when every cue is skipped; nothing changes.

## Stepping rules

- Next: Standby → first cue not skipped; cue i → first cue j > i not skipped; none → `.atEnd` (or `.allSkipped`).
- Previous: cue i → last cue j < i not skipped; none or Standby → `.atStart` (or `.allSkipped`).
- `canGoNext` / `canGoPrevious` true exactly when Next / Previous would move.
- Go to Cue: any cue, skipped or not.

## Hold (app, session only)

`ShowAutoAdvanceCoordinator.isOperatorHeld: Bool` (false at launch). Effective timeline hold = `isOperatorHeld ||
pause || blackout not live || repair pending || app not active`.

`ShowAdvanceTimeline.rearm(cueID:remaining:at:)`: sets a pending advance for `cueID` with `remaining` left (held when
the timeline is held, else running with deadline now + remaining).
