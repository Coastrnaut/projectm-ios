# Data Model: REC-007 Recording countdown

## RecordingCountdownLength (enum, String raw value)

| Case | Raw | Seconds |
|---|---|---|
| off | `off` | 0 (default; absent or unknown reads as off) |
| three | `3` | 3 |
| five | `5` | 5 |
| ten | `10` | 10 |

## RecordingCountdownSetting (main actor, observable)

- `length: RecordingCountdownLength`, stored on change under `settings.recording.countdown`; removed by `-uitestResetNotice`.

## VideoRecordingCoordinator.State

`idle → countingDown(remaining) → … → countingDown(1) → recording → finishing → idle`;
`countingDown → idle` on cancel or on a refusal at completion. `allCases` lists `countingDown(1)` as the representative.

## Countdown (coordinator-private)

- `generation: Int` — increments on begin, cancel and completion.
- `deadline: Double` — the countdown clock's time of completion.
- `startedRecordingAt: Double?` — the clock time of the start a countdown caused (late-tap guard).
- `timer: RecordingCountdownTimer?` — the next scheduled tick.

## RecordingCountdownCancel (enum)

`user`, `background`, `leftVisualizer`, `visualLost`, `presentationLost`, `blackedOut`, `paused`; each
with a caption text. Stored as `lastCountdownCancel` with a sequence number for the status row.

## Counters (tests, diagnostics)

- `writerCreations: Int` — writers the coordinator has created (incremented before each writer is made).
