# Contract: REC-007 countdown

## C1 Coordinator

| Call | In state | Result |
|---|---|---|
| `toggle()` | idle, countdown Off | start at once (REC-003) |
| `toggle()` | idle, countdown n s | refusal (no countdown) or `.countingDown(n)` |
| `toggle()` | countingDown, more than 0.25 s left | cancel (`user`) |
| `toggle()` | countingDown, 0.25 s or less left | ignored |
| `toggle()` | recording, started by a countdown less than 0.5 s ago | ignored |
| `toggle()` | recording otherwise | stop (`user`) |
| `cancelCountdown()` | countingDown | cancel (`user`) |
| tick at start + k | countingDown | `.countingDown(n − k)`; at k = n the start path runs once |
| `checkContext()` | countingDown | cancel on no visual, visual changed or lost, frame loop stopped, blackout, pause |
| `appEnteredBackground()` | countingDown | cancel (`background`) |

## C2 Status rows (recording lane)

| ID | When | Visible | Spoken | Cause | Presentation |
|---|---|---|---|---|---|
| X9d | each second | "Recording in N" | "Recording in N" for the first, then "N" | user | persistent (the overlay) |
| X9e | cancelled | "Countdown cancelled" or "Countdown cancelled: <reason>." | same | user / system | caption |

## C3 UI identifiers

- `recordingCountdown` (label "Recording in N", value N), `recordingCountdownCancel` (button, Escape).
- Record item `record` reads "Cancel countdown" while counting.
- Settings rows `recordingCountdown.off|3|5|10`.

## C4 Storage

`settings.recording.countdown`: `off`, `3`, `5`, `10`; backed up; erased with Settings; reset by `-uitestResetNotice`.
